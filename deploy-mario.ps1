<#
.SYNOPSIS
    Deploy Mario Clone game to AKS Arc cluster with ArgoCD GitOps
.DESCRIPTION
    This script fully automates the deployment of Mario Clone game using ArgoCD on an AKS Arc cluster.
.PARAMETER ACRName
    Name of the Azure Container Registry (without the full FQDN). Default: acxcontregwus2
.PARAMETER ImageTag
    Docker image tag to use for the deployment. Default: latest
.PARAMETER MarioIP
    IP address for the Mario game LoadBalancer service. Default: 172.22.86.148
.PARAMETER ArgoCDIP
    IP address for the ArgoCD LoadBalancer service. Default: 172.22.86.149
.PARAMETER SkipBuild
    Skip the Docker build and push step (use existing image)
.PARAMETER UpdateGit
    Automatically commit and push kustomization.yaml changes to Git
.EXAMPLE
    .\deploy-mario.ps1
.EXAMPLE
    .\deploy-mario.ps1 -ImageTag v3 -MarioIP 172.22.86.150 -ArgoCDIP 172.22.86.151
.EXAMPLE
    .\deploy-mario.ps1 -SkipBuild -UpdateGit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ACRName = "acxcontregwus2",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageTag = "latest",
    
    [Parameter(Mandatory=$false)]
    [string]$MarioIP = "172.22.86.148",
    
    [Parameter(Mandatory=$false)]
    [string]$ArgoCDIP = "172.22.86.149",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild,
    
    [Parameter(Mandatory=$false)]
    [switch]$UpdateGit
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host @"
========================================
    Mario Clone Deployment Script
========================================
Cluster: $(kubectl config current-context)
ACR: $ACRName
Image Tag: $ImageTag
Mario IP: $MarioIP
ArgoCD IP: $ArgoCDIP
========================================
"@ -ForegroundColor Cyan

# Verify prerequisites
Write-Host "`n[Prerequisite Check]" -ForegroundColor Yellow
Write-Host "Checking required tools..." -ForegroundColor Gray

$tools = @(
    @{Name="kubectl"; Command="kubectl version --client"},
    @{Name="docker"; Command="docker --version"},
    @{Name="az"; Command="az version"}
)

foreach ($tool in $tools) {
    try {
        $null = Invoke-Expression $tool.Command 2>&1
        Write-Host "  ✓ $($tool.Name) found" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ $($tool.Name) not found - please install it" -ForegroundColor Red
        exit 1
    }
}

try {
    $null = kubectl cluster-info 2>&1
    Write-Host "  ✓ Connected to Kubernetes cluster" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Cannot connect to Kubernetes cluster" -ForegroundColor Red
    exit 1
}

# Step 1: Build and push Docker image
if (-not $SkipBuild) {
    Write-Host "`n[1/7] Building and pushing Docker image..." -ForegroundColor Yellow
    Set-Location -Path "$ScriptDir\mario-clone"
    
    Write-Host "Verifying all files are downloaded from OneDrive..." -ForegroundColor Gray
    $testFile = Get-Item "sprites.js" -ErrorAction SilentlyContinue
    if ($testFile -and ($testFile.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        Write-Host "  ⚠ Files are still in OneDrive cloud. Downloading..." -ForegroundColor Yellow
        attrib -U /S /D *.* 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }
    
    Write-Host "Logging into ACR: $ACRName" -ForegroundColor Gray
    az acr login --name $ACRName
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✗ Failed to login to ACR" -ForegroundColor Red
        exit 1
    }
    
    $acrFQDN = "$ACRName-c6chcgfjardafsb5.azurecr.io"
    $imageName = "$acrFQDN/mario-clone:$ImageTag"
    
    Write-Host "Building Docker image: $imageName" -ForegroundColor Gray
    docker build -t $imageName .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✗ Docker build failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Pushing image to ACR..." -ForegroundColor Gray
    docker push $imageName
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✗ Docker push failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "  ✓ Image built and pushed successfully" -ForegroundColor Green
}
else {
    Write-Host "`n[1/7] Skipping Docker build (using existing image)" -ForegroundColor Yellow
}

# Step 2: Update kustomization.yaml
Write-Host "`n[2/7] Updating kustomization.yaml..." -ForegroundColor Yellow
Set-Location -Path "$ScriptDir\k8s"

$kustomizationPath = "kustomization.yaml"
$kustomization = Get-Content $kustomizationPath -Raw
$kustomization = $kustomization -replace 'newTag:.*', "newTag: $ImageTag"
$kustomization | Set-Content $kustomizationPath -NoNewline -Encoding UTF8

Write-Host "  ✓ Updated kustomization.yaml to use tag: $ImageTag" -ForegroundColor Green

# Step 3: Configure MetalLB IP pools
Write-Host "`n[3/7] Configuring MetalLB..." -ForegroundColor Yellow

Write-Host "Removing MetalLB webhook validations..." -ForegroundColor Gray
kubectl delete validatingwebhookconfigurations metallb-webhook-configuration --ignore-not-found=true 2>&1 | Out-Null

$metallbConfig = @"
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ca-mario
  namespace: kube-system
spec:
  addresses:
    - $MarioIP-$ArgoCDIP
  autoAssign: true
  avoidBuggyIPs: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ca-mario
  namespace: kube-system
spec:
  ipAddressPools:
    - ca-mario
"@

$metallbConfigPath = "metallb-pool-temp.yaml"
$metallbConfig | Set-Content $metallbConfigPath -Encoding UTF8
kubectl apply -f $metallbConfigPath 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ MetalLB configured with IP range: $MarioIP-$ArgoCDIP" -ForegroundColor Green
    Remove-Item $metallbConfigPath -Force
}
else {
    Write-Host "  ✗ Failed to configure MetalLB" -ForegroundColor Red
    exit 1
}

# Step 4: Create namespace
Write-Host "`n[4/7] Creating namespace..." -ForegroundColor Yellow
kubectl create namespace mario-game --dry-run=client -o yaml | kubectl apply -f - 2>&1 | Out-Null
Write-Host "  ✓ Namespace 'mario-game' ready" -ForegroundColor Green

# Step 5: Get ACR credentials and create secret
Write-Host "`n[5/7] Configuring ACR authentication..." -ForegroundColor Yellow

Write-Host "Retrieving ACR credentials..." -ForegroundColor Gray
$acrCredsJson = az acr credential show --name $ACRName
$acrCreds = $acrCredsJson | ConvertFrom-Json

$acrServer = "$ACRName-c6chcgfjardafsb5.azurecr.io"
$acrUsername = $acrCreds.username
$acrPassword = $acrCreds.passwords[0].value

Write-Host "Creating ACR secret in mario-game namespace..." -ForegroundColor Gray
kubectl create secret docker-registry acr-auth `
    --docker-server=$acrServer `
    --docker-username=$acrUsername `
    --docker-password=$acrPassword `
    --namespace=mario-game `
    --dry-run=client -o yaml | kubectl apply -f - 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ ACR authentication configured" -ForegroundColor Green
}
else {
    Write-Host "  ✗ Failed to create ACR secret" -ForegroundColor Red
    exit 1
}

# Step 6: Deploy ArgoCD application
Write-Host "`n[6/7] Deploying ArgoCD application..." -ForegroundColor Yellow
Set-Location -Path "$ScriptDir"

kubectl apply -f ArgoCD\mario-application.yaml 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ ArgoCD application deployed" -ForegroundColor Green
}
else {
    Write-Host "  ⚠ ArgoCD application may already exist" -ForegroundColor Yellow
}

Start-Sleep -Seconds 3
kubectl patch application mario-clone -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>&1 | Out-Null

# Step 7: Wait for deployment and verify
Write-Host "`n[7/7] Waiting for deployment..." -ForegroundColor Yellow

Write-Host "Waiting for Mario pod to be ready (timeout: 5 minutes)..." -ForegroundColor Gray
$waitResult = kubectl wait --for=condition=ready pod -l app=mario-clone -n mario-game --timeout=300s 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Mario pod is ready" -ForegroundColor Green
}
else {
    Write-Host "  ⚠ Pod not ready yet, but deployment may still be in progress" -ForegroundColor Yellow
}

Start-Sleep -Seconds 5
$serviceJson = kubectl get svc mario-clone-service -n mario-game -o json 2>&1
if ($LASTEXITCODE -eq 0) {
    $service = $serviceJson | ConvertFrom-Json
    $externalIP = $service.status.loadBalancer.ingress[0].ip
}
else {
    $externalIP = "Pending"
}

if ($UpdateGit) {
    Write-Host "`n[Git Update] Committing and pushing changes..." -ForegroundColor Yellow
    Set-Location -Path $ScriptDir
    
    git add k8s/kustomization.yaml
    git commit -m "Update Mario image tag to $ImageTag"
    git push
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Changes pushed to Git" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Git push failed or no changes to commit" -ForegroundColor Yellow
    }
}

Write-Host @"

========================================
       Deployment Complete!
========================================

📦 Image: $ACRName-c6chcgfjardafsb5.azurecr.io/mario-clone:$ImageTag
🎮 Mario Game URL: http://$externalIP
🔧 ArgoCD UI URL: http://$ArgoCDIP

========================================
         Status Summary
========================================
"@ -ForegroundColor Green

Write-Host "`nArgoCD Application:" -ForegroundColor Yellow
kubectl get application mario-clone -n argocd 2>&1

Write-Host "`nPods:" -ForegroundColor Yellow
kubectl get pods -n mario-game 2>&1

Write-Host "`nServices:" -ForegroundColor Yellow
kubectl get svc -n mario-game 2>&1

Write-Host @"

========================================
       Next Steps
========================================
"@ -ForegroundColor Cyan

if ($externalIP -eq "Pending") {
    Write-Host "⏳ LoadBalancer IP is still pending. Check MetalLB configuration." -ForegroundColor Yellow
    Write-Host "   Run: kubectl describe svc mario-clone-service -n mario-game" -ForegroundColor Gray
}
else {
    Write-Host "✓ Mario Game is ready at: http://$externalIP" -ForegroundColor Green
    Write-Host "  Open this URL in your browser to play!" -ForegroundColor Gray
}

Write-Host "`n📊 Monitor ArgoCD: http://$ArgoCDIP" -ForegroundColor Cyan
Write-Host "🔄 To update deployment: .\deploy-mario.ps1 -ImageTag v3 -UpdateGit" -ForegroundColor Gray

Write-Host "`n========================================`n" -ForegroundColor Green