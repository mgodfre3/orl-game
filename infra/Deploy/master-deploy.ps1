<#
.SYNOPSIS
    Automated deployment script for AKS Arc cluster with ArgoCD and Mario game
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
    [string]$ACRResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$GatewayResourceId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$GitRepo = "https://github.com/mgodfre3/orl-game.git",
    
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

# Helper Functions
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
    
    Write-Info "Waiting for $ResourceType $ResourceName to be ready..."
    
    $elapsed = 0
    $interval = 30
    
    while ($elapsed -lt $MaxWaitSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        
        try {
            $result = & $CheckCommand
            if ($result) {
                Write-Success "$ResourceType $ResourceName is ready!"
                return $true
            }
        }
        catch {
            Write-Verbose "Check failed: $_"
        }
        
        Write-Info "Still waiting... $elapsed of $MaxWaitSeconds seconds"
    }
    
    Write-Warning "$ResourceType $ResourceName did not become ready in time"
    return $false
}

# Main Deployment
Write-Step "Starting Automated AKS Arc Deployment"
Write-Host "Configuration:" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "  Cluster Name: $ClusterName" -ForegroundColor Gray
Write-Host "  Custom Location: $CustomLocationName" -ForegroundColor Gray
Write-Host "  Logical Network: $LogicalNetworkName" -ForegroundColor Gray
Write-Host "  MetalLB IP Range: $MetalLBIPRange" -ForegroundColor Gray
Write-Host "  Mario Service IP: $MarioIP" -ForegroundColor Gray
Write-Host "  ACR: $ACRName (RG: $ACRResourceGroupName)" -ForegroundColor Gray
Write-Host "  Git Repository: $GitRepo" -ForegroundColor Gray

# Set Azure subscription
Write-Step "Step 1: Setting Azure Subscription"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to set Azure subscription" }
Write-Success "Azure subscription set"

# Verify resource group
Write-Step "Step 2: Verifying Resource Group"
$rg = az group show --name $ResourceGroupName --query name --output tsv 2>$null
if (-not $rg) { throw "Resource group $ResourceGroupName not found" }
Write-Success "Resource group verified"

# Get Gateway Resource ID if not provided
if (-not $GatewayResourceId) {
    Write-Info "Attempting to find gateway..."
    $gateways = az hybridcompute gateway list --resource-group $ResourceGroupName --query "[].id" --output tsv 2>$null
    if ($gateways) {
        $GatewayResourceId = ($gateways -split "`n")[0]
        Write-Info "Found gateway: $GatewayResourceId"
    }
}

# Create AKS Arc cluster
if (-not $SkipClusterCreation) {
    Write-Step "Step 3: Creating AKS Arc Cluster"
    
    $customLocationId = "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/microsoft.extendedlocation/customlocations/$CustomLocationName"
    $logicalNetworkId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.azurestackhci/logicalnetworks/$LogicalNetworkName"
    $aadGroupsStr = $AADAdminGroupObjectId -join ","
    
    Write-Info "Creating AKS Arc cluster $ClusterName (this may take 15-30 minutes)..."
    
    $createArgs = @(
        "aksarc", "create",
        "--name", $ClusterName,
        "--resource-group", $ResourceGroupName,
        "--custom-location", $customLocationId,
        "--vnet-ids", $logicalNetworkId,
        "--aad-admin-group-object-ids", $aadGroupsStr,
        "--generate-ssh-keys",
        "--load-balancer-count", "0",
        "--kubernetes-version", $KubernetesVersion,
        "--control-plane-count", "1",
        "--node-count", $NodeCount.ToString(),
        "--node-vm-size", "Standard_A4_v2"
    )
    
    if ($GatewayResourceId) {
        $createArgs += "--arc-gateway-resource-id", $GatewayResourceId
    }
    
    & az @createArgs
    if ($LASTEXITCODE -ne 0) { throw "Failed to create AKS Arc cluster" }
    Write-Success "AKS Arc cluster created successfully"
} else {
    Write-Info "Skipping cluster creation"
}

# Get cluster credentials
Write-Step "Step 4: Getting Cluster Credentials"
az aksarc get-credentials --name $ClusterName --resource-group $ResourceGroupName --overwrite-existing
if ($LASTEXITCODE -ne 0) { throw "Failed to get cluster credentials" }
kubectl config use-context $ClusterName
Write-Success "Cluster credentials configured"

# Verify connectivity
Write-Info "Verifying cluster connectivity..."
kubectl get nodes
if ($LASTEXITCODE -ne 0) { throw "Failed to connect to cluster" }
Write-Success "Cluster is accessible"

# Deploy MetalLB extension
Write-Step "Step 5: Deploying MetalLB Extension"
$metallbExtName = "metallb"
$existingMetalLB = az k8s-extension show --name $metallbExtName --cluster-name $ClusterName --resource-group $ResourceGroupName --cluster-type connectedClusters --query "name" --output tsv 2>$null

if (-not $existingMetalLB) {
    Write-Info "Installing MetalLB Arc extension..."
    az k8s-extension create --resource-group $ResourceGroupName --cluster-name $ClusterName --cluster-type connectedClusters --name $metallbExtName --extension-type microsoft.arcnetworking --scope cluster --release-namespace kube-system --config service.type=LoadBalancer
    if ($LASTEXITCODE -ne 0) { throw "Failed to create MetalLB extension" }
    
    Wait-ForResource -ResourceType "Extension" -ResourceName $metallbExtName -CheckCommand {
        $status = az k8s-extension show --name $metallbExtName --cluster-name $ClusterName --resource-group $ResourceGroupName --cluster-type connectedClusters --query "installState" --output tsv 2>$null
        return ($status -eq "Installed")
    }
} else {
    Write-Info "MetalLB extension already exists"
}

# Configure MetalLB IP pool
Write-Info "Configuring MetalLB IP pool..."
$metallbYaml = @"
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
"@

$metallbYaml | kubectl apply -f -
Write-Success "MetalLB configured with IP range $MetalLBIPRange"

# Deploy ArgoCD extension
Write-Step "Step 6: Deploying ArgoCD Extension"
$argocdExtName = "argocd"
$existingArgoCD = az k8s-extension show --name $argocdExtName --cluster-name $ClusterName --resource-group $ResourceGroupName --cluster-type connectedClusters --query "name" --output tsv 2>$null

if (-not $existingArgoCD) {
    Write-Info "Installing ArgoCD Arc extension..."
    $argocdArgs = @("k8s-extension", "create", "--resource-group", $ResourceGroupName, "--cluster-name", $ClusterName, "--cluster-type", "connectedClusters", "--name", $argocdExtName, "--extension-type", "Microsoft.ArgoCD", "--scope", "cluster", "--release-namespace", "argocd", "--config", "argocd-server.service.type=LoadBalancer")
    if ($ArgocdIP) { $argocdArgs += "--config", "argocd-server.service.loadBalancerIP=$ArgocdIP" }
    & az @argocdArgs
    if ($LASTEXITCODE -ne 0) { throw "Failed to create ArgoCD extension" }
    
    Wait-ForResource -ResourceType "Extension" -ResourceName $argocdExtName -CheckCommand {
        $status = az k8s-extension show --name $argocdExtName --cluster-name $ClusterName --resource-group $ResourceGroupName --cluster-type connectedClusters --query "installState" --output tsv 2>$null
        return ($status -eq "Installed")
    }
} else {
    Write-Info "ArgoCD extension already exists"
}

Write-Info "Waiting for ArgoCD pods..."
Start-Sleep -Seconds 30
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s 2>$null
Write-Success "ArgoCD is ready"

# Verify ACR
Write-Step "Step 7: Verifying Azure Container Registry"
$acrExists = az acr show --name $ACRName --resource-group $ACRResourceGroupName --query name --output tsv 2>$null
if (-not $acrExists) { throw "ACR $ACRName not found in RG $ACRResourceGroupName" }
$acrLoginServer = az acr show --name $ACRName --resource-group $ACRResourceGroupName --query loginServer --output tsv
Write-Success "ACR verified: $acrLoginServer"

# Attach ACR
Write-Info "Attaching ACR to cluster..."
$acrId = az acr show --name $ACRName --resource-group $ACRResourceGroupName --query id --output tsv
az aksarc update --name $ClusterName --resource-group $ResourceGroupName --attach-acr $acrId 2>$null
Write-Success "ACR attached"

# Build and push image
if (-not $SkipImageBuild) {
    Write-Step "Step 8: Building Docker Image"
    az acr login --name $ACRName
    Write-Info "Building v4..."
    docker build -t "$acrLoginServer/mario-clone:v4" ./mario-clone
    if ($LASTEXITCODE -eq 0) {
        docker push "$acrLoginServer/mario-clone:v4"
        docker tag "$acrLoginServer/mario-clone:v4" "$acrLoginServer/mario-clone:latest"
        docker push "$acrLoginServer/mario-clone:latest"
        Write-Success "Image pushed: v4"
    }
}

# Update kustomization
Write-Step "Step 9: Updating Configuration"
if (Test-Path "k8s/kustomization.yaml") {
    $content = Get-Content "k8s/kustomization.yaml" -Raw
    $content = $content -replace 'newName:.*', "newName: $acrLoginServer/mario-clone"
    $content = $content -replace 'newTag:.*', "newTag: v4"
    $content | Set-Content "k8s/kustomization.yaml"
    Write-Success "Kustomization updated"
}

if (Test-Path "k8s/service.yaml") {
    $content = Get-Content "k8s/service.yaml" -Raw
    $content = $content -replace 'loadBalancerIP:.*', "loadBalancerIP: `"$MarioIP`""
    $content | Set-Content "k8s/service.yaml"
    Write-Success "Service IP configured"
}

# Create namespace
Write-Step "Step 10: Creating Namespace"
kubectl create namespace mario-game --dry-run=client -o yaml | kubectl apply -f -

# Deploy application
Write-Step "Step 11: Deploying Mario via ArgoCD"
$argoAppYaml = @"
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
"@

$argoAppYaml | kubectl apply -f -
Write-Success "Mario application configured"

# Get ArgoCD password
Write-Step "Step 12: Getting ArgoCD Credentials"
Start-Sleep -Seconds 10
$argocdPassword = kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>$null
if ($argocdPassword) {
    try {
        $decodedPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($argocdPassword))
        Write-Host "`nArgoCD Credentials:" -ForegroundColor Cyan
        Write-Host "  Username: admin" -ForegroundColor White
        Write-Host "  Password: $decodedPassword" -ForegroundColor White
    } catch {
        Write-Info "Get password: kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    }
}

# Wait for services
Write-Step "Step 13: Waiting for Services"
Start-Sleep -Seconds 20
kubectl get svc -n mario-game
kubectl get svc -n argocd

$actualMarioIP = kubectl get svc -n mario-game mario-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
$actualArgocdIP = kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null

# Summary
Write-Step "Deployment Complete!"
$marioUrl = if ($actualMarioIP) { $actualMarioIP } else { $MarioIP }
$argoUrl = if ($actualArgocdIP) { $actualArgocdIP } else { $ArgocdIP }

Write-Host ""
Write-Host "✅ Cluster: $ClusterName" -ForegroundColor Green
Write-Host "✅ ArgoCD: Installed" -ForegroundColor Green
Write-Host "✅ MetalLB: $MetalLBIPRange" -ForegroundColor Green
Write-Host "✅ Mario: Deployed" -ForegroundColor Green
Write-Host "✅ ACR: $acrLoginServer" -ForegroundColor Green
Write-Host ""
Write-Host "Mario Game:  http://$marioUrl" -ForegroundColor Cyan
Write-Host "ArgoCD UI:   https://$argoUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎮 Deployment completed! 🚀" -ForegroundColor Green