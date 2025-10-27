@'
param(
    [Parameter(Mandatory=$false)]
    [string]$ClusterContext = "ca-mario",
    
    [Parameter(Mandatory=$false)]
    [string]$ArgocdNamespace = "argocd",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("basic", "environments", "applicationset", "all")]
    [string]$DeploymentType = "basic",
    
    [Parameter(Mandatory=$false)]
    [string]$GitRepo = "https://github.com/mgodfre3/orl-game.git",
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

if ($Verbose) {
    $VerbosePreference = "Continue"
}

Write-Host "=== Mario Clone ArgoCD Deployment ===" -ForegroundColor Green
Write-Host "Cluster Context: $ClusterContext" -ForegroundColor Yellow
Write-Host "ArgoCD Namespace: $ArgocdNamespace" -ForegroundColor Yellow
Write-Host "Deployment Type: $DeploymentType" -ForegroundColor Yellow
Write-Host "Git Repository: $GitRepo" -ForegroundColor Yellow
Write-Host ""

# Set kubectl context
Write-Verbose "Setting kubectl context to $ClusterContext"
kubectl config use-context $ClusterContext
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set kubectl context to '$ClusterContext'. Please check if the context exists."
    exit 1
}

# Verify ArgoCD is installed and running
Write-Host "Checking ArgoCD installation..." -ForegroundColor Yellow
$argoCdPods = kubectl get pods -n $ArgocdNamespace -l app.kubernetes.io/name=argocd-server --no-headers 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "ArgoCD not found in namespace '$ArgocdNamespace'. Please install ArgoCD first."
    Write-Host "To install ArgoCD, run:" -ForegroundColor Cyan
    Write-Host "kubectl create namespace $ArgocdNamespace" -ForegroundColor White
    Write-Host "kubectl apply -n $ArgocdNamespace -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml" -ForegroundColor White
    exit 1
}

Write-Verbose "ArgoCD pods found: $argoCdPods"

# Create ArgoCD namespace if it doesn't exist
Write-Verbose "Ensuring ArgoCD namespace exists"
kubectl create namespace $ArgocdNamespace --dry-run=client -o yaml | kubectl apply -f - >$null

Write-Host "Deploying ArgoCD applications..." -ForegroundColor Yellow

# Get current directory for file paths
$currentDir = Get-Location

switch ($DeploymentType) {
    "basic" {
        Write-Host "Deploying basic ArgoCD application..." -ForegroundColor Blue
        kubectl apply -f "$currentDir\mario-application.yaml"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Basic application deployed successfully" -ForegroundColor Green
        } else {
            Write-Error "❌ Failed to deploy basic application"
        }
    }
    
    "all" {
        Write-Host "Deploying all ArgoCD configurations..." -ForegroundColor Blue
        kubectl apply -f "$currentDir\mario-application.yaml"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ All configurations deployed successfully" -ForegroundColor Green
        } else {
            Write-Error "❌ Failed to deploy all configurations"
        }
    }
}

# Wait for applications to be created
Write-Host "`nWaiting for ArgoCD applications to be created..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Check application status
Write-Host "`nChecking ArgoCD application status..." -ForegroundColor Yellow
kubectl get applications -n $ArgocdNamespace -o wide

Write-Host "`nChecking ArgoCD project status..." -ForegroundColor Yellow
kubectl get appprojects -n $ArgocdNamespace

# Get ArgoCD server information
Write-Host "`n=== ArgoCD Server Information ===" -ForegroundColor Green

# Try to get LoadBalancer IP first
$argocdService = kubectl get svc -n $ArgocdNamespace argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
if ($argocdService -and $argocdService -ne "null" -and $argocdService.Trim() -ne "") {
    Write-Host "ArgoCD UI (LoadBalancer): https://$argocdService" -ForegroundColor Cyan
} else {
    Write-Host "ArgoCD UI (Port-forward): kubectl port-forward svc/argocd-server -n $ArgocdNamespace 8080:443" -ForegroundColor Cyan
    Write-Host "Then access: https://localhost:8080" -ForegroundColor Cyan
}

# Get initial admin password
Write-Host "`n=== ArgoCD Admin Credentials ===" -ForegroundColor Green
$adminPassword = kubectl get secret -n $ArgocdNamespace argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>$null
if ($adminPassword -and $adminPassword -ne "null") {
    try {
        $decodedPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($adminPassword))
        Write-Host "Username: admin" -ForegroundColor White
        Write-Host "Password: $decodedPassword" -ForegroundColor White
    } catch {
        Write-Host "Password found but failed to decode. Use this command:" -ForegroundColor Yellow
        Write-Host "kubectl get secret -n $ArgocdNamespace argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" -ForegroundColor White
    }
} else {
    Write-Host "Admin password secret not found. This is normal for newer ArgoCD installations." -ForegroundColor Yellow
    Write-Host "Reset admin password with:" -ForegroundColor Cyan
    Write-Host "argocd admin initial-password -n $ArgocdNamespace" -ForegroundColor White
}

Write-Host "`n=== Deployment Summary ===" -ForegroundColor Green
Write-Host "✅ ArgoCD applications configured and deployed" -ForegroundColor Green
Write-Host "🎮 Mario Clone will be deployed to your cluster automatically" -ForegroundColor Green
Write-Host "🔄 Applications will sync automatically when Git repository changes" -ForegroundColor Green

Write-Host "`nDeployment completed successfully! 🚀" -ForegroundColor Green
'@ | Out-File -FilePath "deploy-argocd-apps.ps1" -Encoding UTF8