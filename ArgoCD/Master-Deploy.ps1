<#
.SYNOPSIS
    Automated deployment script for AKS Arc cluster with ArgoCD and Mario game

.DESCRIPTION
    This script automates the complete deployment process:
    1. Creates AKS Arc cluster on Azure Stack HCI
    2. Deploys and configures ArgoCD GitOps
    3. Deploys MetalLB for load balancing
    4. Configures Mario game application
    5. Builds and pushes Docker images

.PARAMETER ResourceGroupName
    The Azure resource group name

.PARAMETER SubscriptionId
    The Azure subscription ID

.PARAMETER CustomLocationName
    The custom location name for Azure Stack HCI

.PARAMETER LogicalNetworkName
    The logical network name on Azure Stack HCI

.PARAMETER ClusterName
    The name for the AKS Arc cluster (default: mario-aksarc)

.PARAMETER MetalLBIPRange
    The IP range for MetalLB (e.g., "172.22.232.182-183")

.PARAMETER MarioIP
    The specific IP for Mario service load balancer

.PARAMETER ArgocdIP
    The specific IP for ArgoCD service load balancer

.PARAMETER GitRepo
    The Git repository URL (default: https://github.com/mgodfre3/orl-game.git)

.PARAMETER AADAdminGroupObjectId
    Azure AD admin group object ID(s) - comma separated if multiple

.PARAMETER GatewayResourceId
    Azure Arc Gateway resource ID

.PARAMETER SkipClusterCreation
    Skip cluster creation if cluster already exists

.PARAMETER SkipImageBuild
    Skip Docker image build and push

.EXAMPLE
    .\deploy-complete.ps1 -ResourceGroupName "ACX-MobileAzL" -SubscriptionId "fbaf508b-cb61-4383-9cda-a42bfa0c7bc9" -CustomLocationName "ACX-Mobile" -LogicalNetworkName "lnet-cluster01-external" -MetalLBIPRange "172.22.232.182-183" -MarioIP "172.22.232.183" -ArgocdIP "172.22.232.182" -AADAdminGroupObjectId "your-aad-group-id" -GatewayResourceId "/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.HybridCompute/gateways/xxx"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$CustomLocationName,
    
    [Parameter(Mandatory=$true)]
    [string]$LogicalNetworkName,
    
    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "mario-aksarc",
    
    [Parameter(Mandatory=$true)]
    [string]$MetalLBIPRange,
    
    [Parameter(Mandatory=$true)]
    [string]$MarioIP,
    
    [Parameter(Mandatory=$false)]
    [string]$ArgocdIP = "",
    
    [Parameter(Mandatory=$false)]
    [string]$GitRepo = "https://github.com/mgodfre3/orl-game.git",
    
    [Parameter(Mandatory=$true)]
    [string]$AADAdminGroupObjectId,
    
    [Parameter(Mandatory=$true)]
    [string]$GatewayResourceId,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipClusterCreation,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipImageBuild,
    
    [Parameter(Mandatory=$false)]
    [int]$NodeCount = 2,
    
    [Parameter(Mandatory=$false)]
    [string]$KubernetesVersion = "1.30.9"
)

$ErrorActionPreference = "Stop"

# ==================== Helper Functions ====================

function Write-Step {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Yellow
}

function Wait-ForResource {
    param(
        [string]$ResourceType,
        [string]$ResourceName,
        [int]$MaxWaitSeconds = 600,
        [scriptblock]$CheckCommand
    )
    
    Write-Info "Waiting for $ResourceType '$ResourceName' to be ready..."
    $elapsed = 0
    $interval = 30
    
    while ($elapsed -lt $MaxWaitSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        
        $result = & $CheckCommand
        if ($result) {
            Write-Success "$ResourceType '$ResourceName' is ready!"
            return $true
        }
        
        Write-Info "Still waiting... ($elapsed/$MaxWaitSeconds seconds)"
    }
    
    Write-Warning "$ResourceType '$ResourceName' did not become ready in time"
    return $false
}

# ==================== Main Deployment ====================

Write-Step "Starting Automated AKS Arc Deployment"
Write-Host "Configuration:" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "  Cluster Name: $ClusterName" -ForegroundColor Gray
Write-Host "  Custom Location: $CustomLocationName" -ForegroundColor Gray
Write-Host "  Logical Network: $LogicalNetworkName" -ForegroundColor Gray
Write-Host "  MetalLB IP Range: $MetalLBIPRange" -ForegroundColor Gray
Write-Host "  Mario Service IP: $MarioIP" -ForegroundColor Gray
Write-Host "  Git Repository: $GitRepo" -ForegroundColor Gray

# Set Azure subscription
Write-Step "Step 1: Setting Azure Subscription"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Failed to set Azure subscription"
}
Write-Success "Azure subscription set"

# Verify resource group
Write-Step "Step 2: Verifying Resource Group"
$rg = az group show --name $ResourceGroupName --query name --output tsv 2>$null
if (-not $rg) {
    throw "Resource group '$ResourceGroupName' not found"
}
Write-Success "Resource group verified"

# Create AKS Arc cluster
if (-not $SkipClusterCreation) {
    Write-Step "Step 3: Creating AKS Arc Cluster"
    
    # Get custom location and logical network resource IDs
    $customLocationId = "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/microsoft.extendedlocation/customlocations/$CustomLocationName"
    $logicalNetworkId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.azurestackhci/logicalnetworks/$LogicalNetworkName"
    
    Write-Info "Creating AKS Arc cluster '$ClusterName'..."
    Write-Info "This may take 15-30 minutes..."
    
    $createClusterCmd = @"
az aksarc create ``
    --name $ClusterName ``
    --resource-group $ResourceGroupName ``
    --custom-location $customLocationId ``
    --vnet-ids $logicalNetworkId ``
    --aad-admin-group-object-ids $AADAdminGroupObjectId ``
    --generate-ssh-keys ``
    --load-balancer-count 0 ``
    --arc-gateway-resource-id $GatewayResourceId ``
    --kubernetes-version $KubernetesVersion ``
    --control-plane-count 1 ``
    --node-count $NodeCount ``
    --node-vm-size Standard_A4_v2
"@
    
    Invoke-Expression $createClusterCmd
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create AKS Arc cluster"
    }
    Write-Success "AKS Arc cluster created successfully"
} else {
    Write-Info "Skipping cluster creation (cluster already exists)"
}

# Get cluster credentials
Write-Step "Step 4: Getting Cluster Credentials"
az aksarc get-credentials --name $ClusterName --resource-group $ResourceGroupName --overwrite-existing
if ($LASTEXITCODE -ne 0) {
    throw "Failed to get cluster credentials"
}
kubectl config use-context $ClusterName
Write-Success "Cluster credentials configured"

# Deploy MetalLB extension
Write-Step "Step 5: Deploying MetalLB Extension"
$metallbExtName = "metallb-$ClusterName"

Write-Info "Installing MetalLB Arc extension..."
az k8s-extension create `
    --resource-group $ResourceGroupName `
    --cluster-name $ClusterName `
    --cluster-type connectedClusters `
    --name $metallbExtName `
    --extension-type microsoft.arcnetworking `
    --scope cluster `
    --release-namespace kube-system `
    --config service.type=LoadBalancer

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create MetalLB extension"
}

# Wait for MetalLB to be ready
Wait-ForResource -ResourceType "Extension" -ResourceName $metallbExtName -CheckCommand {
    $status = az k8s-extension show --name $metallbExtName --cluster-name $ClusterName --resource-group $ResourceGroupName --cluster-type connectedClusters --query "installState" --output tsv 2>$null
    return ($status -eq "Installed")
}

Write-Success "MetalLB extension installed"

# Configure MetalLB IP pool
Write-Info "Configuring MetalLB IP address pool..."
@"
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: mario-pool
  namespace: kube-system
spec:
  addresses:
  - $MetalLBIPRange
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: mario-l2
  namespace: kube-system
spec:
  ipAddressPools:
  - mario-pool
"@ | kubectl apply -f -

Write-Success "MetalLB configured with IP range $MetalLBIPRange"

# Deploy ArgoCD extension
Write-Step "Step 6: Deploying ArgoCD Extension"
$argocdExtName = "argocd-$ClusterName"

Write-Info "Installing ArgoCD Arc extension..."
az k8s-extension create `
    --resource-group $ResourceGroupName `
    --cluster-name $ClusterName `
    --cluster-type connectedClusters `
    --name $argocdExtName `
    --extension-type Microsoft.ArgoCD `
    --scope cluster `
    --release-namespace argocd `
    --config argocd-server.service.type=LoadBalancer $(if ($ArgocdIP) { "--config argocd-server.service.loadBalancerIP=$ArgocdIP" })

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create ArgoCD extension"
}

# Wait for ArgoCD to be ready
Wait-ForResource -ResourceType "Extension" -ResourceName $argocdExtName -CheckCommand {
    $status = az k8s-extension show --name $argocdExtName --cluster-name $ClusterName --resource-group $ResourceGroupName --cluster-type connectedClusters --query "installState" --output tsv 2>$null
    return ($status -eq "Installed")
}

Write-Success "ArgoCD extension installed"

# Wait for ArgoCD pods to be ready
Write-Info "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
Write-Success "ArgoCD pods are ready"

# Create ACR (if needed)
Write-Step "Step 7: Setting up Azure Container Registry"
$acrName = "acxcontregwus2" # Use existing or create new
$acrExists = az acr show --name $acrName --resource-group $ResourceGroupName 2>$null
if (-not $acrExists) {
    Write-Info "Creating Azure Container Registry..."
    az acr create --name $acrName --resource-group $ResourceGroupName --sku Basic --admin-enabled true
}
$acrLoginServer = az acr show --name $acrName --resource-group $ResourceGroupName --query loginServer --output tsv
Write-Success "ACR ready: $acrLoginServer"

# Attach ACR to cluster
Write-Info "Attaching ACR to cluster..."
$acrId = az acr show --name $acrName --resource-group $ResourceGroupName --query id --output tsv
az aksarc update --name $ClusterName --resource-group $ResourceGroupName --attach-acr $acrId 2>$null

# Build and push Mario image
if (-not $SkipImageBuild) {
    Write-Step "Step 8: Building and Pushing Mario Docker Image"
    
    # Login to ACR
    az acr login --name $acrName
    
    # Build and push
    Write-Info "Building Docker image..."
    docker build -t "$acrLoginServer/mario-clone:v4" ./mario-clone
    
    if ($LASTEXITCODE -eq 0) {
        Write-Info "Pushing Docker image to ACR..."
        docker push "$acrLoginServer/mario-clone:v4"
        Write-Success "Docker image pushed: $acrLoginServer/mario-clone:v4"
    } else {
        Write-Warning "Docker build failed, but continuing..."
    }
} else {
    Write-Info "Skipping image build"
}

# Create namespace
Write-Step "Step 9: Creating Kubernetes Namespace"
kubectl create namespace mario-game --dry-run=client -o yaml | kubectl apply -f -
Write-Success "Namespace 'mario-game' created"

# Deploy Mario application via ArgoCD
Write-Step "Step 10: Deploying Mario Application via ArgoCD"

@"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mario-game
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $GitRepo
    targetRevision: main
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: mario-game
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
"@ | kubectl apply -f -

Write-Success "Mario application configured in ArgoCD"

# Update kustomization to use v4
Write-Info "Updating kustomization to use v4 tag..."
$kustomizationPath = "k8s/kustomization.yaml"
if (Test-Path $kustomizationPath) {
    (Get-Content $kustomizationPath) -replace 'newTag:.*', "newTag: v4" | Set-Content $kustomizationPath
    Write-Success "Kustomization updated to v4"
}

# Get ArgoCD admin password
Write-Step "Step 11: Getting ArgoCD Credentials"
Start-Sleep -Seconds 10
$argocdPassword = kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>$null
if ($argocdPassword) {
    $decodedPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($argocdPassword))
    Write-Host "`nArgoCD Credentials:" -ForegroundColor Cyan
    Write-Host "  Username: admin" -ForegroundColor White
    Write-Host "  Password: $decodedPassword" -ForegroundColor White
}

# Get service IPs
Write-Step "Step 12: Getting Service Information"
Start-Sleep -Seconds 10

Write-Host "`nService Endpoints:" -ForegroundColor Cyan
kubectl get svc -n mario-game
kubectl get svc -n argocd argocd-server

Write-Host "`nMario Game URL:" -ForegroundColor Green
Write-Host "  http://$MarioIP" -ForegroundColor White

if ($ArgocdIP) {
    Write-Host "`nArgoCD UI URL:" -ForegroundColor Green
    Write-Host "  https://$ArgocdIP" -ForegroundColor White
} else {
    $argocdIP = kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($argocdIP) {
        Write-Host "`nArgoCD UI URL:" -ForegroundColor Green
        Write-Host "  https://$argocdIP" -ForegroundColor White
    }
}

# Final summary
Write-Step "Deployment Complete!"
Write-Host @"

✅ AKS Arc Cluster: $ClusterName
✅ ArgoCD GitOps: Installed and configured
✅ MetalLB: Configured with IP range $MetalLBIPRange
✅ Mario Game: Deployed via GitOps
✅ ACR: $acrLoginServer

Next Steps:
1. Access Mario game at: http://$MarioIP
2. Monitor ArgoCD for sync status
3. Make changes to the Git repo and watch automatic deployment
4. Use 'kubectl get pods -n mario-game' to check pod status

Useful Commands:
- Check application status: kubectl get applications -n argocd
- View pods: kubectl get pods -n mario-game
- View services: kubectl get svc -n mario-game
- ArgoCD sync: kubectl get applications -n argocd mario-game

"@ -ForegroundColor Green