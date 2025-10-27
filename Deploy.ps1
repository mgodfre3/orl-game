# PowerShell script to deploy AKS Arc cluster with ArgoCD using Bicep template
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$ParametersFile = "aksarc-azurelocal.parameters.json",
    
    [Parameter(Mandatory=$false)]
    [string]$TemplateFile = "aksarc-azurelocal.bicep",
    
    [Parameter(Mandatory=$false)]
    [switch]$WaitForDeployment = $true
)

# Set the subscription
Write-Host "Starting AKS Arc deployment with ArgoCD GitOps" -ForegroundColor Green
Write-Host "Setting subscription to: $SubscriptionId" -ForegroundColor Yellow
az account set --subscription $SubscriptionId

# Verify the resource group exists
Write-Host "Checking resource group: $ResourceGroupName" -ForegroundColor Green
$rg = az group show --name $ResourceGroupName --query name --output tsv 2>$null
if (-not $rg) {
    Write-Error "Resource group '$ResourceGroupName' not found. Please create it first."
    exit 1
}

# Deploy the Bicep template
Write-Host "Starting deployment of AKS Arc cluster with ArgoCD..." -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "Template: $TemplateFile" -ForegroundColor Yellow
Write-Host "Parameters: $ParametersFile" -ForegroundColor Yellow

$deploymentName = "aksarc-argocd-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

try {
    Write-Host "Deploying infrastructure (this may take 15-30 minutes)..." -ForegroundColor Yellow
    
    $deployment = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file $TemplateFile `
        --parameters @$ParametersFile `
        --name $deploymentName `
        --verbose | ConvertFrom-Json

    if ($deployment) {
        Write-Host "Infrastructure deployment completed successfully!" -ForegroundColor Green
        
        # Extract outputs
        $outputs = $deployment.properties.outputs
        $clusterName = $outputs.clusterName.value
        $acrName = $outputs.acrName.value
        $acrLoginServer = $outputs.acrLoginServer.value
        $argoCDExtension = $outputs.argoCDExtensionName.value
        $metalLBExtension = $outputs.metalLBExtensionName.value
        
        Write-Host "Deployment Summary:" -ForegroundColor Cyan
        Write-Host "Cluster Name: $clusterName" -ForegroundColor White
        Write-Host "ACR Name: $acrName" -ForegroundColor White
        Write-Host "ACR Login Server: $acrLoginServer" -ForegroundColor White
        Write-Host "ArgoCD Extension: $argoCDExtension" -ForegroundColor White
        Write-Host "MetalLB Extension: $metalLBExtension" -ForegroundColor White
        
        if ($WaitForDeployment) {
            Write-Host "Waiting for extensions to be ready..." -ForegroundColor Yellow
            
            # Wait for ArgoCD extension
            $maxWaitTime = 600 # 10 minutes
            $waitTime = 0
            do {
                Start-Sleep -Seconds 30
                $waitTime += 30
                $extensionStatus = az k8s-extension show --name $argoCDExtension --cluster-name $clusterName --resource-group $ResourceGroupName --cluster-type connectedClusters --query "installState" --output tsv 2>$null
                Write-Host "ArgoCD Extension Status: $extensionStatus" -ForegroundColor Yellow
            } while ($extensionStatus -ne "Installed" -and $waitTime -lt $maxWaitTime)
            
            if ($extensionStatus -eq "Installed") {
                Write-Host "ArgoCD extension is ready!" -ForegroundColor Green
            } else {
                Write-Warning "ArgoCD extension may still be installing. Check status manually."
            }
        }
        
        Write-Host "Next Steps:" -ForegroundColor Cyan
        
        Write-Host "1. Connect to cluster:" -ForegroundColor White
        Write-Host "   $($outputs.clusterConnectionCommand.value)" -ForegroundColor Gray
        
        Write-Host "2. Build and push Mario game image:" -ForegroundColor White
        Write-Host $outputs.buildCommands.value -ForegroundColor Gray
        
        Write-Host "3. Access ArgoCD UI:" -ForegroundColor White
        Write-Host "   $($outputs.argoCDAccessCommand.value)" -ForegroundColor Gray
        Write-Host "   Username: admin" -ForegroundColor Gray
        Write-Host "   Password: Run this command to get password:" -ForegroundColor Gray
        Write-Host "   $($outputs.argoCDPasswordCommand.value)" -ForegroundColor Gray
        
        Write-Host "4. Verify deployment:" -ForegroundColor White
        Write-Host $outputs.verificationCommands.value -ForegroundColor Gray
        
        Write-Host "5. Access Mario game:" -ForegroundColor White
        Write-Host "   The game will be available at the load balancer IP once deployed" -ForegroundColor Gray
        Write-Host "   Check service status: kubectl get svc -n mario-game" -ForegroundColor Gray
        
    } else {
        Write-Error "Deployment failed. Check the error messages above."
        exit 1
    }
}
catch {
    Write-Error "Deployment failed with error: $_"
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "1. Check that all required Azure CLI extensions are installed:" -ForegroundColor White
    Write-Host "   - az extension add --name connectedk8s" -ForegroundColor Gray
    Write-Host "   - az extension add --name k8s-extension" -ForegroundColor Gray
    Write-Host "   - az extension add --name k8s-configuration" -ForegroundColor Gray
    Write-Host "   - az extension add --name aksarc" -ForegroundColor Gray
    Write-Host "2. Verify custom location and logical network exist" -ForegroundColor White
    Write-Host "3. Check Azure Arc Gateway connectivity" -ForegroundColor White
    Write-Host "4. Verify Azure AD group permissions" -ForegroundColor White
    exit 1
}

Write-Host "Mario Clone AKS Arc with ArgoCD deployment completed!" -ForegroundColor Green
Write-Host "The GitOps workflow will automatically deploy the Mario game to your cluster." -ForegroundColor Yellow
Write-Host "Check the ArgoCD UI to monitor the application deployment status." -ForegroundColor Yellow