<#
.SYNOPSIS
    Deploys AKS Arc cluster on Azure Stack HCI using Bicep template

.DESCRIPTION
    This script deploys an AKS Arc enabled Kubernetes cluster on Azure Stack HCI
    using the Bicep template with configurable parameters and proper error handling.

.PARAMETER SubscriptionId
    Azure subscription ID

.PARAMETER ResourceGroupName
    Name of the resource group to deploy to

.PARAMETER Location
    Azure region for the deployment

.PARAMETER ClusterName
    Name of the AKS Arc cluster

.PARAMETER CustomLocationName
    Name of the custom location on Azure Stack HCI

.PARAMETER LogicalNetworkName
    Name of the logical network

.PARAMETER SshKeyName
    Name of the SSH key resource

.PARAMETER NodeVMSize
    VM size for worker nodes

.PARAMETER NodeCount
    Number of worker nodes

.PARAMETER ControlPlaneNodeCount
    Number of control plane nodes

.PARAMETER AadAdminGroupIds
    Array of Azure AD group object IDs for admin access

.PARAMETER GatewayResourceId
    Arc Gateway resource ID (optional)

.PARAMETER EnableAhub
    Enable Azure Hybrid Benefit

.PARAMETER KubernetesVersion
    Kubernetes version to deploy

.PARAMETER TemplateFile
    Path to the Bicep template file

.PARAMETER ParametersFile
    Path to the parameters file

.PARAMETER CreateSshKey
    Whether to create a new SSH key

.PARAMETER CreateLogicalNetwork
    Whether to create a new logical network

.PARAMETER VmSwitchName
    Hyper-V virtual switch name (required if creating logical network)

.PARAMETER AddressPrefix
    Network CIDR (required if creating logical network)

.PARAMETER DefaultGateway
    Default gateway IP (required if creating logical network)

.PARAMETER DnsServers
    DNS servers array (required if creating logical network)

.PARAMETER VlanId
    VLAN ID (optional)

.PARAMETER UseLegacyAzCli
    Use legacy az aksarc commands instead of Bicep template

.EXAMPLE
    .\deploy.ps1 -SubscriptionId "fbaf508b-cb61-4383-9cda-a42bfa0c7bc9" -ResourceGroupName "Toronto" -ClusterName "tor-vi" -CustomLocationName "Toronto" -LogicalNetworkName "tor-lnet-vlan26"

.EXAMPLE
    .\deploy.ps1 -ParametersFile ".\aksarc.bicepparam" -Verbose

.EXAMPLE
    .\deploy.ps1 -SubscriptionId "fbaf508b-cb61-4383-9cda-a42bfa0c7bc9" -ResourceGroupName "Toronto" -ClusterName "tor-vi" -CustomLocationName "Toronto" -LogicalNetworkName "tor-lnet-vlan26" -UseLegacyAzCli
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory = $true)]
    [string]$ClusterName,
    
    [Parameter(Mandatory = $true)]
    [string]$CustomLocationName,
    
    [Parameter(Mandatory = $true)]
    [string]$LogicalNetworkName,
    
    [Parameter(Mandatory = $false)]
    [string]$SshKeyName = "$ClusterName-ssh-key",
    
    [Parameter(Mandatory = $false)]
    [string]$NodeVMSize = "Standard_A4_v2",
    
    [Parameter(Mandatory = $false)]
    [int]$NodeCount = 1,
    
    [Parameter(Mandatory = $false)]
    [int]$ControlPlaneNodeCount = 1,
    
    [Parameter(Mandatory = $false)]
    [string[]]$AadAdminGroupIds = @("be0c17dc-9a37-48c5-9691-751a27a4c1b9", "f5157bd2-8ce4-48b6-82df-69b9de7540a9", "af0ac67a-fcb3-4c19-a950-c32f938ee163"),
    
    [Parameter(Mandatory = $false)]
    [string]$GatewayResourceId = "/subscriptions/fbaf508b-cb61-4383-9cda-a42bfa0c7bc9/resourceGroups/AdaptiveCloud-ArcGateway/providers/Microsoft.HybridCompute/gateways/ac-arcgateway-eus",
    
    [Parameter(Mandatory = $false)]
    [bool]$EnableAhub = $true,
    
    [Parameter(Mandatory = $false)]
    [string]$KubernetesVersion = "1.30.9",
    
    [Parameter(Mandatory = $false)]
    [string]$TemplateFile = "..\main.bicep",
    
    [Parameter(Mandatory = $false)]
    [string]$ParametersFile = "",
    
    [Parameter(Mandatory = $false)]
    [bool]$CreateSshKey = $true,
    
    [Parameter(Mandatory = $false)]
    [bool]$CreateLogicalNetwork = $false,
    
    [Parameter(Mandatory = $false)]
    [string]$VmSwitchName = "Default Switch",
    
    [Parameter(Mandatory = $false)]
    [string]$AddressPrefix = "192.168.26.0/24",
    
    [Parameter(Mandatory = $false)]
    [string]$DefaultGateway = "192.168.26.1",
    
    [Parameter(Mandatory = $false)]
    [string[]]$DnsServers = @("8.8.8.8", "8.8.4.4"),
    
    [Parameter(Mandatory = $false)]
    [int]$VlanId = 26,
    
    [Parameter(Mandatory = $false)]
    [switch]$UseLegacyAzCli
)

# Error handling
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# Function to validate prerequisites
function Test-Prerequisites {
    Write-ColorOutput "Checking prerequisites..." "Yellow"
    
    # Check if Azure CLI is installed
    try {
        $azVersion = az version --output json 2>$null | ConvertFrom-Json
        Write-ColorOutput "Azure CLI version: $($azVersion.'azure-cli')" "Green"
    }
    catch {
        Write-Error "Azure CLI is not installed or not in PATH. Please install Azure CLI."
        exit 1
    }
    
    # Check if logged in to Azure
    try {
        $account = az account show --output json 2>$null | ConvertFrom-Json
        Write-ColorOutput "Logged in as: $($account.user.name)" "Green"
    }
    catch {
        Write-Error "Not logged in to Azure. Please run 'az login'."
        exit 1
    }
    
    # Check if template file exists (only if not using legacy CLI)
    if (-not $UseLegacyAzCli -and -not (Test-Path $TemplateFile)) {
        Write-Error "Template file not found: $TemplateFile"
        exit 1
    }
    
    Write-ColorOutput "Prerequisites check passed!" "Green"
}

# Function to set Azure subscription
function Set-AzureSubscription {
    param([string]$SubscriptionId)
    
    Write-ColorOutput "Setting subscription to: $SubscriptionId" "Yellow"
    
    try {
        az account set --subscription $SubscriptionId
        $currentSub = az account show --query id -o tsv
        
        if ($currentSub -eq $SubscriptionId) {
            Write-ColorOutput "Successfully set subscription: $SubscriptionId" "Green"
        }
        else {
            throw "Failed to set subscription"
        }
    }
    catch {
        Write-Error "Failed to set subscription: $_"
        exit 1
    }
}

# Function to check/create resource group
function Ensure-ResourceGroup {
    param(
        [string]$ResourceGroupName,
        [string]$Location
    )
    
    Write-ColorOutput "Checking resource group: $ResourceGroupName" "Yellow"
    
    $rg = az group show --name $ResourceGroupName --output json 2>$null
    
    if ($rg) {
        Write-ColorOutput "Resource group exists: $ResourceGroupName" "Green"
    }
    else {
        Write-ColorOutput "Creating resource group: $ResourceGroupName" "Yellow"
        try {
            az group create --name $ResourceGroupName --location $Location --output none
            Write-ColorOutput "Resource group created successfully: $ResourceGroupName" "Green"
        }
        catch {
            Write-Error "Failed to create resource group: $_"
            exit 1
        }
    }
}

# Function for legacy Azure CLI deployment
function Start-LegacyAzCliDeployment {
    Write-ColorOutput "Using legacy Azure CLI deployment method..." "Yellow"
    
    # Build resource IDs
    $customLocationResourceId = "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/microsoft.extendedlocation/customlocations/$CustomLocationName"
    $vnetArmId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.azurestackhci/logicalnetworks/$LogicalNetworkName"
    
    try {
        # Create SSH key if needed
        if ($CreateSshKey) {
            Write-ColorOutput "Creating SSH key: $SshKeyName" "Yellow"
            az sshkey create --name $SshKeyName --resource-group $ResourceGroupName --location $Location
        }
        
        # Get SSH public key
        Write-ColorOutput "Retrieving SSH public key..." "Yellow"
        $pubkeyResult = az sshkey show --name $SshKeyName --resource-group $ResourceGroupName | ConvertFrom-Json
        
        if (-not $pubkeyResult.publicKey) {
            throw "Failed to retrieve SSH public key"
        }
        
        # Build az aksarc create command
        Write-ColorOutput "Creating AKS Arc cluster: $ClusterName" "Yellow"
        
        $createCmd = @(
            "az", "aksarc", "create"
            "-g", $ResourceGroupName
            "--custom-location", $customLocationResourceId
            "-n", $ClusterName
            "--vnet-ids", $vnetArmId
            "--aad-admin-group-object-ids", ($AadAdminGroupIds -join ",")
            "--control-plane-count", $ControlPlaneNodeCount
            "--node-vm-size", $NodeVMSize
            "--node-count", $NodeCount
            "--ssh-key-value", $pubkeyResult.publicKey
        )
        
        if ($EnableAhub) {
            $createCmd += "--enable-ahub"
        }
        
        if ($GatewayResourceId) {
            $createCmd += @("--gateway-id", $GatewayResourceId)
        }
        
        if ($KubernetesVersion) {
            $createCmd += @("--kubernetes-version", $KubernetesVersion)
        }
        
        Write-ColorOutput "Executing: $($createCmd -join ' ')" "White"
        
        # Execute the command
        & $createCmd[0] $createCmd[1..($createCmd.Length-1)]
        
        if ($LASTEXITCODE -ne 0) {
            throw "az aksarc create command failed with exit code: $LASTEXITCODE"
        }
        
        Write-ColorOutput "AKS Arc cluster created successfully!" "Green"
        
        return @{
            ClusterName = $ClusterName
            ResourceGroup = $ResourceGroupName
            SshKeyName = $SshKeyName
        }
    }
    catch {
        Write-Error "Legacy deployment failed: $_"
        exit 1
    }
}

# Function to create deployment parameters for Bicep
function New-DeploymentParameters {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $deploymentName = "aksarc-deployment-$timestamp"
    
    # Build custom location resource ID
    $customLocationResourceId = "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/microsoft.extendedlocation/customlocations/$CustomLocationName"
    
    if ($ParametersFile -and (Test-Path $ParametersFile)) {
        Write-ColorOutput "Using parameters file: $ParametersFile" "Yellow"
        return @{
            DeploymentName = $deploymentName
            UseParametersFile = $true
            ParametersFile = $ParametersFile
        }
    }
    else {
        Write-ColorOutput "Using inline parameters" "Yellow"
        
        $parameters = @{
            azureLocation = $Location
            deploymentResourceGroupName = $ResourceGroupName
            customLocationResourceID = $customLocationResourceId
            sshKeyName = $SshKeyName
            createSshKey = $CreateSshKey
            logicalNetworkName = $LogicalNetworkName
            createLogicalNetwork = $CreateLogicalNetwork
            connectedClusterName = $ClusterName
            kubernetesVersion = $KubernetesVersion
            controlPlaneVMSize = "Standard_A4_v2"
            controlPlaneNodeCount = $ControlPlaneNodeCount
            nodePoolName = "nodepool1"
            nodePoolVMSize = $NodeVMSize
            nodePoolOSType = "Linux"
            nodePoolCount = $NodeCount
            nodePoolLabel = "environment"
            nodePoolLabelValue = "demo"
            nodePoolTaint = "demo=true:NoSchedule"
            netWorkProfilNetworkPolicy = "calico"
            networkProfileLoadBalancerCount = 0
        }
        
        # Add logical network parameters if creating new network
        if ($CreateLogicalNetwork) {
            $parameters.vmSwitchName = $VmSwitchName
            $parameters.addressPrefix = $AddressPrefix
            $parameters.defaultGateway = $DefaultGateway
            $parameters.dnsServers = $DnsServers
            $parameters.ipAllocationMethod = "Dynamic"
            $parameters.vlanId = $VlanId
        }
        
        return @{
            DeploymentName = $deploymentName
            UseParametersFile = $false
            Parameters = $parameters
        }
    }
}

# Function to deploy Bicep template
function Start-BicepTemplateDeployment {
    param($DeploymentConfig)
    
    Write-ColorOutput "Starting Bicep template deployment..." "Yellow"
    Write-ColorOutput "Deployment Name: $($DeploymentConfig.DeploymentName)" "White"
    Write-ColorOutput "Template File: $TemplateFile" "White"
    
    try {
        if ($DeploymentConfig.UseParametersFile) {
            Write-ColorOutput "Deploying with parameters file..." "Yellow"
            
            $result = az deployment sub create `
                --name $DeploymentConfig.DeploymentName `
                --location $Location `
                --template-file $TemplateFile `
                --parameters "@$($DeploymentConfig.ParametersFile)" `
                --output json
        }
        else {
            Write-ColorOutput "Deploying with inline parameters..." "Yellow"
            
            # Convert parameters to JSON
            $parametersJson = $DeploymentConfig.Parameters | ConvertTo-Json -Depth 10 -Compress
            $parametersFile = [System.IO.Path]::GetTempFileName() + ".json"
            $parametersJson | Out-File -FilePath $parametersFile -Encoding UTF8
            
            try {
                $result = az deployment sub create `
                    --name $DeploymentConfig.DeploymentName `
                    --location $Location `
                    --template-file $TemplateFile `
                    --parameters "@$parametersFile" `
                    --output json
            }
            finally {
                # Clean up temp file
                if (Test-Path $parametersFile) {
                    Remove-Item $parametersFile -Force
                }
            }
        }
        
        if ($result) {
            $deploymentResult = $result | ConvertFrom-Json
            Write-ColorOutput "Deployment completed successfully!" "Green"
            
            # Display outputs
            if ($deploymentResult.properties.outputs) {
                Write-ColorOutput "Deployment Outputs:" "Cyan"
                $deploymentResult.properties.outputs | ConvertTo-Json -Depth 3 | Write-Host
            }
            
            return $deploymentResult
        }
        else {
            throw "Deployment returned no result"
        }
    }
    catch {
        Write-Error "Deployment failed: $_"
        
        # Try to get deployment operation details
        try {
            Write-ColorOutput "Getting deployment operation details..." "Yellow"
            az deployment operation sub list --name $DeploymentConfig.DeploymentName --output table
        }
        catch {
            Write-Warning "Could not retrieve deployment operation details"
        }
        
        exit 1
    }
}

# Function to display post-deployment information - FIXED
function Show-PostDeploymentInfo {
    param($Result)
    
    Write-ColorOutput "=== Post-Deployment Information ===" "Cyan"
    
    # Initialize variables
    $clusterName = ""
    $resourceGroup = $ResourceGroupName
    $sshKeyName = ""
    
    # Check if this is a hashtable (legacy deployment) or an object (Bicep deployment)
    if ($Result -is [hashtable]) {
        # Legacy deployment result
        $clusterName = $Result.ClusterName
        $resourceGroup = $Result.ResourceGroup
        $sshKeyName = $Result.SshKeyName
        Write-ColorOutput "Legacy deployment detected" "Green"
    }
    elseif ($Result -and $Result.properties -and $Result.properties.outputs) {
        # Bicep deployment result
        $outputs = $Result.properties.outputs
        
        if ($outputs.connectedClusterName -and $outputs.connectedClusterName.value) {
            $clusterName = $outputs.connectedClusterName.value
        }
        
        if ($outputs.sshKeyName -and $outputs.sshKeyName.value) {
            $sshKeyName = $outputs.sshKeyName.value
        }
        
        Write-ColorOutput "Bicep deployment detected" "Green"
    }
    else {
        Write-ColorOutput "Unable to determine deployment result format" "Yellow"
        $clusterName = $ClusterName  # Fallback to parameter value
        $sshKeyName = $SshKeyName    # Fallback to parameter value
    }
    
    # Display the information
    Write-ColorOutput "Cluster Name: $clusterName" "Green"
    Write-ColorOutput "Resource Group: $resourceGroup" "Green"
    
    if ($clusterName) {
        Write-ColorOutput "`nTo connect to your cluster:" "Yellow"
        Write-Host "az connectedk8s proxy -n $clusterName -g $resourceGroup" -ForegroundColor White
        
        Write-ColorOutput "`nTo verify cluster status:" "Yellow"
        Write-Host "az connectedk8s show -n $clusterName -g $resourceGroup" -ForegroundColor White
        
        Write-ColorOutput "`nTo get cluster credentials:" "Yellow"
        Write-Host "az aksarc get-credentials -n $clusterName -g $resourceGroup" -ForegroundColor White
    }
    
    if ($sshKeyName) {
        Write-ColorOutput "`nSSH Key: $sshKeyName" "Green"
        Write-ColorOutput "To get SSH private key:" "Yellow"
        Write-Host "az sshkey show -n $sshKeyName -g $resourceGroup --query privateKey -o tsv" -ForegroundColor White
    }
    
    Write-ColorOutput "`n=== Deployment Complete ===" "Green"
}

# Main execution
function Main {
    try {
        Write-ColorOutput "Starting AKS Arc deployment script..." "Cyan"
        Write-ColorOutput "Cluster: $ClusterName" "White"
        Write-ColorOutput "Resource Group: $ResourceGroupName" "White"
        Write-ColorOutput "Location: $Location" "White"
        Write-ColorOutput "Deployment Method: $(if ($UseLegacyAzCli) { 'Legacy Azure CLI' } else { 'Bicep Template' })" "White"
        
        # Run prerequisites check
        Test-Prerequisites
        
        # Set subscription
        Set-AzureSubscription -SubscriptionId $SubscriptionId
        
        # Ensure resource group exists
        Ensure-ResourceGroup -ResourceGroupName $ResourceGroupName -Location $Location
        
        # Choose deployment method
        if ($UseLegacyAzCli) {
            # Use legacy Azure CLI deployment
            $result = Start-LegacyAzCliDeployment
        }
        else {
            # Use Bicep template deployment
            $deploymentConfig = New-DeploymentParameters
            $result = Start-BicepTemplateDeployment -DeploymentConfig $deploymentConfig
        }
        
        # Show post-deployment information
        Show-PostDeploymentInfo -Result $result
        
        Write-ColorOutput "Script completed successfully!" "Green"
    }
    catch {
        Write-Error "Script failed: $_"
        exit 1
    }
}

# Execute main function
Main