# Infrastructure Deployment for Mario Clone on AKS Arc

This directory contains Bicep templates and deployment scripts for deploying the Mario Clone game on Azure Kubernetes Service (AKS) Arc-enabled clusters running on Azure Local (Azure Stack HCI).

## Files Overview

- `aksarc-azurelocal.bicep` - Main Bicep template for AKS Arc cluster and ACR
- `aksarc-azurelocal.parameters.json` - Generic parameters template (customize before use)
- `aksarc-azurelocal.parameters.example.json` - Example parameters file with real values
- `deploy-aksarc.ps1` - PowerShell deployment script
- `main.bicep` - Legacy template for standard AKS (kept for reference)

## Prerequisites

Before deploying, ensure you have:

1. **Azure Stack HCI Infrastructure**
   - Azure Stack HCI cluster registered with Azure
   - Custom location configured
   - Logical network (VLAN) configured
   - Arc Gateway deployed (if using gateway connectivity)

2. **Azure CLI and Extensions**
   ```powershell
   # Install Azure CLI extensions
   az extension add --name connectedk8s
   az extension add --name k8s-extension
   az extension add --name k8s-configuration
   az extension add --name aksarc
   ```

3. **Azure Permissions**
   - Contributor access to the resource group
   - Azure Arc Kubernetes permissions
   - Azure AD admin group object IDs

## Configuration Setup

### Step 1: Customize Parameters

1. Copy the generic parameters file:
   ```powershell
   copy aksarc-azurelocal.parameters.json my-deployment.parameters.json
   ```

2. Edit `my-deployment.parameters.json` and replace the placeholder values:

   ```json
   {
     "customLocationName": {
       "value": "YOUR_CUSTOM_LOCATION_NAME"  // e.g., "California"
     },
     "logicalNetworkName": {
       "value": "YOUR_LOGICAL_NETWORK_NAME"  // e.g., "ca-lnet-vlan26"
     },
     "aadAdminGroupObjectIds": {
       "value": [
         "YOUR_AAD_GROUP_ID_1",
         "YOUR_AAD_GROUP_ID_2"
       ]
     },
     "gatewayResourceId": {
       "value": "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/YOUR_GATEWAY_RG/providers/Microsoft.HybridCompute/gateways/YOUR_GATEWAY_NAME"
     }
   }
   ```

### Step 2: Find Your Required Values

**Custom Location Name:**
```powershell
# List available custom locations
az customlocation list --query "[].{Name:name, ResourceGroup:resourceGroup}" --output table
```

**Logical Network Name:**
```powershell
# List logical networks in your Azure Stack HCI
az stack-hci-vm network lnet list --resource-group YOUR_RG --query "[].name" --output table
```

**Azure AD Group Object IDs:**
```powershell
# Find your Azure AD group object IDs
az ad group list --query "[?displayName=='YOUR_GROUP_NAME'].objectId" --output tsv
```

**Arc Gateway Resource ID:**
```powershell
# Find your Arc Gateway (if using disconnected scenarios)
az hybridcompute gateway list --query "[].{Name:name, ResourceGroup:resourceGroup, Id:id}" --output table
```

## Quick Deployment

### Option 1: Using the PowerShell Script (Recommended)

```powershell
# Navigate to the infra directory
cd infra

# Run the deployment script with your customized parameters
.\deploy-aksarc.ps1 -ResourceGroupName "YOUR_RESOURCE_GROUP" -SubscriptionId "YOUR_SUBSCRIPTION_ID" -ParametersFile "my-deployment.parameters.json"
```

### Option 2: Direct Bicep Deployment

```powershell
# Deploy using Azure CLI
az deployment group create \
  --resource-group YOUR_RESOURCE_GROUP \
  --template-file aksarc-azurelocal.bicep \
  --parameters @my-deployment.parameters.json
```

## Parameter Reference

### Required Parameters (Must be customized)

| Parameter | Description | Example |
|-----------|-------------|---------|
| `customLocationName` | Azure Stack HCI custom location name | `California` |
| `logicalNetworkName` | Logical network for cluster networking | `ca-lnet-vlan26` |
| `aadAdminGroupObjectIds` | Azure AD admin group object IDs | `["be0c17dc-9a37..."]` |
| `gatewayResourceId` | Arc Gateway resource ID (if applicable) | `/subscriptions/.../gateways/my-gateway` |

### Optional Parameters (Can use defaults)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `clusterName` | `mario-aksarc` | Name of the AKS Arc cluster |
| `location` | `eastus` | Azure region for metadata |
| `sshKeyName` | `mario-cluster-key` | SSH key name for cluster nodes |
| `nodeVmSize` | `Standard_A2_v2` | VM size for worker nodes |
| `nodeCount` | `2` | Number of worker nodes |
| `controlPlaneCount` | `1` | Number of control plane nodes |
| `enableAhub` | `true` | Enable Azure Hybrid Benefit |
| `kubernetesVersion` | `1.28.9` | Kubernetes version |

## Example Configurations

### Small Environment (Dev/Test)
```json
{
  "nodeVmSize": { "value": "Standard_A2_v2" },
  "nodeCount": { "value": 1 },
  "controlPlaneCount": { "value": 1 }
}
```

### Production Environment
```json
{
  "nodeVmSize": { "value": "Standard_D4s_v3" },
  "nodeCount": { "value": 3 },
  "controlPlaneCount": { "value": 3 }
}
```

### High-Performance Gaming
```json
{
  "nodeVmSize": { "value": "Standard_D8s_v3" },
  "nodeCount": { "value": 4 },
  "controlPlaneCount": { "value": 3 }
}
```

## Post-Deployment Steps

After successful deployment, the script will output commands for:

1. **Connect to cluster**:
   ```bash
   az connectedk8s proxy -n <cluster-name> -g <resource-group>
   ```

2. **Install Flux GitOps**:
   ```bash
   az k8s-extension create --name fluxExtension --extension-type microsoft.flux --cluster-type connectedClusters --resource-group <rg> --cluster-name <cluster>
   ```

3. **Install MetalLB**:
   ```bash
   az k8s-extension create --name metallb --extension-type microsoft.metallb --cluster-type connectedClusters --resource-group <rg> --cluster-name <cluster>
   ```

4. **Configure GitOps**:
   ```bash
   az k8s-configuration flux create --resource-group <rg> --cluster-name <cluster> --cluster-type connectedClusters --name mario-gitops --namespace mario-gitops --url https://github.com/mgodfre3/orl-game --branch main --kustomization name=main path=./k8s prune=true
   ```

## Container Registry

The template also creates an Azure Container Registry (ACR) for storing the Mario game container images.

### Build and Push Game Image

```powershell
# Login to ACR
az acr login --name <acr-name>

# Build and push Mario game image
docker build -t <acr-login-server>/mario-clone:v1 ./mario-clone
docker push <acr-login-server>/mario-clone:v1
```

## Troubleshooting

### Common Issues

1. **Custom Location Not Found**
   - Verify the custom location exists: `az customlocation show -n <name> -g <rg>`
   - Check that Azure Stack HCI is registered with Azure

2. **Logical Network Issues**
   - Ensure the logical network name matches exactly
   - Verify VLAN configuration on Azure Stack HCI

3. **Permission Errors**
   - Check Azure AD admin group object IDs are correct
   - Verify sufficient permissions on subscription/resource group

4. **Gateway Connectivity**
   - For disconnected scenarios, ensure Arc Gateway is properly configured
   - Verify gateway resource ID is correct

### Useful Commands

```powershell
# Check cluster status
az aksarc show -n <cluster-name> -g <resource-group>

# Get cluster credentials
az connectedk8s proxy -n <cluster-name> -g <resource-group>

# Check extensions
az k8s-extension list --cluster-name <cluster-name> --resource-group <resource-group> --cluster-type connectedClusters

# View logs
kubectl logs -n flux-system deployment/fluxcd-controller
kubectl logs -n metallb-system deployment/metallb-controller
```

## Architecture

```
Azure Cloud
├── Resource Group
│   ├── AKS Arc Cluster (Connected Cluster)
│   ├── Azure Container Registry
│   └── SSH Public Key
└── Azure Stack HCI (On-premises)
    ├── Custom Location
    ├── Logical Network (VLAN)
    └── Arc Gateway (optional)
```

The deployment creates:
- AKS Arc cluster on Azure Stack HCI
- Azure Container Registry for game images
- SSH key for node access
- Network configuration for external access
- Extensions for GitOps and load balancing

## Security Considerations

- SSH keys are managed through Azure
- Azure AD integration for cluster access
- Container registry with admin access enabled
- Network policies through Calico CNI
- RBAC enabled by default

## Scaling and Performance

- Auto-scaling disabled by default (can be enabled)
- HPA (Horizontal Pod Autoscaler) supported
- MetalLB for external load balancing
- Resource limits configured in game deployment

For production deployments, consider:
- Enabling auto-scaling
- Configuring resource quotas
- Setting up monitoring and alerting
- Implementing backup strategies

