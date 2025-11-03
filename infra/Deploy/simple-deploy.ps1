param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$CustomLocationName,
    
    [Parameter(Mandatory=$true)]
    [string]$LogicalNetworkName,
    
    [Parameter(Mandatory=$true)]
    [string]$ClusterName,
    
    [Parameter(Mandatory=$true)]
    [string]$MetalLBIPRange,
    
    [Parameter(Mandatory=$true)]
    [string]$MarioIP,
    
    [Parameter(Mandatory=$false)]
    [string]$ArgocdIP = "",
    
    [Parameter(Mandatory=$true)]
    [string[]]$AADAdminGroupObjectId,
    
    [Parameter(Mandatory=$true)]
    [string]$ACRName,
    
    [Parameter(Mandatory=$true)]
    [string]$ACRResourceGroupName
)

Write-Host "Setting subscription..." -ForegroundColor Cyan
az account set --subscription $SubscriptionId

$customLocationId = "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/microsoft.extendedlocation/customlocations/$CustomLocationName"
$logicalNetworkId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.azurestackhci/logicalnetworks/$LogicalNetworkName"
$aadGroups = $AADAdminGroupObjectId -join ","

Write-Host "Creating AKS Arc cluster (this takes 15-30 minutes)..." -ForegroundColor Cyan
az aksarc create `
  --name $ClusterName `
  --resource-group $ResourceGroupName `
  --custom-location $customLocationId `
  --vnet-ids $logicalNetworkId `
  --aad-admin-group-object-ids $aadGroups `
  --generate-ssh-keys `
  --load-balancer-count 0 `
  --kubernetes-version 1.30.9 `
  --control-plane-count 1 `
  --node-count 2 `
  --node-vm-size Standard_A4_v2

Write-Host "Getting credentials..." -ForegroundColor Cyan
az aksarc get-credentials --name $ClusterName --resource-group $ResourceGroupName --overwrite-existing
kubectl config use-context $ClusterName

Write-Host "Installing MetalLB..." -ForegroundColor Cyan
az k8s-extension create `
  --resource-group $ResourceGroupName `
  --cluster-name $ClusterName `
  --cluster-type connectedClusters `
  --name metallb `
  --extension-type microsoft.arcnetworking `
  --scope cluster `
  --release-namespace kube-system `
  --config service.type=LoadBalancer

Write-Host "Waiting for MetalLB..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

Write-Host "Configuring MetalLB IP pool..." -ForegroundColor Cyan
$metalLBFile = "$env:TEMP\metallb-config.yaml"
"apiVersion: metallb.io/v1beta1" | Out-File -FilePath $metalLBFile -Encoding utf8
"kind: IPAddressPool" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"metadata:" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"  name: mario-pool" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"  namespace: kube-system" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"spec:" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"  addresses:" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"  - $MetalLBIPRange" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"---" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"apiVersion: metallb.io/v1beta1" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"kind: L2Advertisement" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"metadata:" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"  name: mario-l2" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"  namespace: kube-system" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"spec:" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"  ipAddressPools:" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append
"  - mario-pool" | Out-File -FilePath $metalLBFile -Encoding utf8 -Append

kubectl apply -f $metalLBFile
Remove-Item $metalLBFile

Write-Host "Installing ArgoCD..." -ForegroundColor Cyan
$argoArgs = @(
    "k8s-extension", "create",
    "--resource-group", $ResourceGroupName,
    "--cluster-name", $ClusterName,
    "--cluster-type", "connectedClusters",
    "--name", "argocd",
    "--extension-type", "Microsoft.ArgoCD",
    "--scope", "cluster",
    "--release-namespace", "argocd",
    "--config", "argocd-server.service.type=LoadBalancer"
)
if ($ArgocdIP) {
    $argoArgs += "--config"
    $argoArgs += "argocd-server.service.loadBalancerIP=$ArgocdIP"
}
& az @argoArgs

Write-Host "Waiting for ArgoCD..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

Write-Host "Attaching ACR..." -ForegroundColor Cyan
$acrId = az acr show --name $ACRName --resource-group $ACRResourceGroupName --query id --output tsv
az aksarc update --name $ClusterName --resource-group $ResourceGroupName --attach-acr $acrId

Write-Host "Building Docker image..." -ForegroundColor Cyan
$acrLoginServer = az acr show --name $ACRName --resource-group $ACRResourceGroupName --query loginServer --output tsv
az acr login --name $ACRName
docker build -t "$acrLoginServer/mario-clone:v4" ./mario-clone
docker push "$acrLoginServer/mario-clone:v4"

Write-Host "Updating kustomization..." -ForegroundColor Cyan
(Get-Content k8s/kustomization.yaml -Raw) -replace 'newName:.*',"newName: $acrLoginServer/mario-clone" -replace 'newTag:.*','newTag: v4' | Set-Content k8s/kustomization.yaml

Write-Host "Updating service IP..." -ForegroundColor Cyan
(Get-Content k8s/service.yaml -Raw) -replace 'loadBalancerIP:.*',"loadBalancerIP: `"$MarioIP`"" | Set-Content k8s/service.yaml

Write-Host "Creating namespace..." -ForegroundColor Cyan
kubectl create namespace mario-game --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Deploying Mario app via ArgoCD..." -ForegroundColor Cyan
$argoAppFile = "$env:TEMP\mario-app.yaml"
@"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mario-game
  namespace: argocd
spec:
  destination:
    namespace: mario-game
    server: https://kubernetes.default.svc.cluster.local
  source:
    path: mario-app
    repoURL: https://github.com/your-repo/mario-app.git
    targetRevision: HEAD
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncWindow:
    - open: "00:00"
      close: "23:59"
      timezone: "*"
"@ | Out-File -FilePath $argoAppFile -Encoding utf8

kubectl apply -f $argoAppFile -n argocd
Remove-Item $argoAppFile

Write-Host "All tasks completed successfully!" -ForegroundColor Green