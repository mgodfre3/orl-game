// Bicep template for deploying AKS Arc cluster on Azure Local (Azure Stack HCI)
// This template creates supporting resources and uses deployment scripts for AKS Arc creation

@description('The name of the AKS Arc cluster')
param clusterName string = 'mario-aksarc'

@description('The Azure region where resources will be deployed')
param location string = 'eastus'

@description('The name of the custom location for Azure Stack HCI')
param customLocationName string

@description('The logical network name on Azure Stack HCI')
param logicalNetworkName string

@description('The SSH key name for cluster nodes')
param sshKeyName string = '${clusterName}-key'

@description('The VM size for cluster nodes')
param nodeVmSize string = 'Standard_A2_v2'

@description('The number of worker nodes')
param nodeCount int = 2

@description('The number of control plane nodes')
param controlPlaneCount int = 1

@description('Azure AD admin group object IDs')
param aadAdminGroupObjectIds array

@description('Azure Arc Gateway resource ID')
param gatewayResourceId string

@description('Enable Azure Hybrid Benefit')
param enableAhub bool = true

@description('Kubernetes version')
param kubernetesVersion string = '1.30.9'

@description('Enable ArgoCD GitOps extension')
param enableArgoCD bool = true

@description('Enable MetalLB extension')
param enableMetalLB bool = true

// Variables
var subscriptionId = subscription().subscriptionId
var customLocationResourceId = '/subscriptions/${subscriptionId}/resourcegroups/${resourceGroup().name}/providers/microsoft.extendedlocation/customlocations/${customLocationName}'
var logicalNetworkResourceId = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup().name}/providers/microsoft.azurestackhci/logicalnetworks/${logicalNetworkName}'

// Azure Container Registry for storing game images
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'marioacr${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
  
  tags: {
    purpose: 'mario-game'
    environment: 'demo'
  }
}

// User-assigned managed identity for deployment scripts
resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${clusterName}-deployment-identity'
  location: location
}

// Role assignment for the managed identity on current resource group
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, deploymentIdentity.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// SSH Key creation and AKS Arc cluster creation using deployment script
resource aksArcDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${clusterName}-deployment-script'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.55.0'
    timeout: 'PT90M' // Increased timeout to 90 minutes
    retentionInterval: 'PT4H' // Keep logs for 4 hours
    environmentVariables: [
      {
        name: 'CLUSTER_NAME'
        value: clusterName
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'CUSTOM_LOCATION'
        value: customLocationResourceId
      }
      {
        name: 'LOGICAL_NETWORK'
        value: logicalNetworkResourceId
      }
      {
        name: 'SSH_KEY_NAME'
        value: sshKeyName
      }
      {
        name: 'NODE_VM_SIZE'
        value: nodeVmSize
      }
      {
        name: 'NODE_COUNT'
        value: string(nodeCount)
      }
      {
        name: 'CONTROL_PLANE_COUNT'
        value: string(controlPlaneCount)
      }
      {
        name: 'ADMIN_GROUPS'
        value: join(aadAdminGroupObjectIds, ',')
      }
      {
        name: 'GATEWAY_ID'
        value: gatewayResourceId
      }
      {
        name: 'KUBERNETES_VERSION'
        value: kubernetesVersion
      }
      {
        name: 'ENABLE_AHUB'
        value: enableAhub ? 'true' : 'false'
      }
      {
        name: 'LOCATION'
        value: location
      }
      {
        name: 'DEPLOYMENT_IDENTITY_ID'
        value: deploymentIdentity.properties.principalId
      }
    ]
    scriptContent: '''
      set -e
      echo "Starting AKS Arc cluster deployment at $(date)"
      echo "Using Kubernetes version: $KUBERNETES_VERSION"
      
      echo "Installing required Azure CLI extensions..."
      # Install extensions with proper error handling
      az extension add --name aksarc --yes --only-show-errors 2>/dev/null || echo "aksarc extension already installed or failed to install"
      az extension add --name connectedk8s --yes --only-show-errors 2>/dev/null || echo "connectedk8s extension already installed or failed to install"
      az extension add --name k8s-extension --yes --only-show-errors 2>/dev/null || echo "k8s-extension already installed or failed to install"
      az extension add --name k8s-configuration --yes --only-show-errors 2>/dev/null || echo "k8s-configuration already installed or failed to install"
      
      # Grant read access to the gateway resource if needed
      if [ "$GATEWAY_ID" != "" ] && [ "$GATEWAY_ID" != "null" ]; then
        echo "Granting read access to gateway resource..."
        az role assignment create \
          --assignee "$DEPLOYMENT_IDENTITY_ID" \
          --role "Reader" \
          --scope "$GATEWAY_ID" \
          --only-show-errors 2>/dev/null || echo "Gateway role assignment already exists or failed"
        
        # Wait a moment for permissions to propagate
        sleep 30
      fi
      
      echo "Creating or retrieving SSH key..."
      # Create SSH key if it doesn't exist, or get existing one
      az sshkey create --name "$SSH_KEY_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --only-show-errors 2>/dev/null || echo "SSH key already exists or creation failed"
      
      # Wait a moment for the key to be available
      sleep 10
      
      # Get the SSH public key
      SSH_KEY=$(az sshkey show --name "$SSH_KEY_NAME" --resource-group "$RESOURCE_GROUP" --query publicKey -o tsv 2>/dev/null)
      
      if [ -z "$SSH_KEY" ]; then
        echo "ERROR: Failed to retrieve SSH key"
        echo "Trying to list available SSH keys..."
        az sshkey list --resource-group "$RESOURCE_GROUP" -o table
        exit 1
      fi
      
      echo "SSH key retrieved successfully"
      echo "Creating AKS Arc cluster: $CLUSTER_NAME at $(date)"
      
      # Check if cluster already exists
      EXISTING_CLUSTER=$(az aksarc show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
      if [ "$EXISTING_CLUSTER" != "NotFound" ]; then
        echo "Cluster already exists with state: $EXISTING_CLUSTER"
        if [ "$EXISTING_CLUSTER" = "Succeeded" ]; then
          echo "Using existing cluster"
          CLUSTER_ID=$(az aksarc show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
          SSH_KEY_ID=$(az sshkey show --name "$SSH_KEY_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || echo "")
          
          cat > $AZ_SCRIPTS_OUTPUT_PATH << EOF
{
  "clusterId": "$CLUSTER_ID",
  "sshKeyId": "$SSH_KEY_ID",
  "sshKeyName": "$SSH_KEY_NAME"
}
EOF
          echo "Deployment script completed successfully using existing cluster!"
          exit 0
        fi
      fi
      
      # Build the command with proper parameter handling
      CREATE_CMD="az aksarc create"
      CREATE_CMD="$CREATE_CMD --name $CLUSTER_NAME"
      CREATE_CMD="$CREATE_CMD --resource-group $RESOURCE_GROUP"
      CREATE_CMD="$CREATE_CMD --custom-location $CUSTOM_LOCATION"
      CREATE_CMD="$CREATE_CMD --vnet-ids $LOGICAL_NETWORK"
      CREATE_CMD="$CREATE_CMD --aad-admin-group-object-ids $ADMIN_GROUPS"
      CREATE_CMD="$CREATE_CMD --control-plane-count $CONTROL_PLANE_COUNT"
      CREATE_CMD="$CREATE_CMD --node-count $NODE_COUNT"
      CREATE_CMD="$CREATE_CMD --node-vm-size $NODE_VM_SIZE"
      CREATE_CMD="$CREATE_CMD --ssh-key-value \"$SSH_KEY\""
      CREATE_CMD="$CREATE_CMD --kubernetes-version $KUBERNETES_VERSION"
      CREATE_CMD="$CREATE_CMD --location $LOCATION"
      CREATE_CMD="$CREATE_CMD --only-show-errors"
      
      # Add optional parameters
      if [ "$GATEWAY_ID" != "" ] && [ "$GATEWAY_ID" != "null" ]; then
        CREATE_CMD="$CREATE_CMD --gateway-id $GATEWAY_ID"
      fi
      
      # Handle enable-ahub parameter correctly
      if [ "$ENABLE_AHUB" = "true" ]; then
        CREATE_CMD="$CREATE_CMD --enable-ahub"
      fi
      
      echo "Executing command: $CREATE_CMD"
      
      # Execute the command with timeout handling
      timeout 3600 bash -c "eval $CREATE_CMD" || {
        echo "ERROR: Cluster creation command timed out or failed"
        echo "Checking cluster state..."
        az aksarc show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" 2>/dev/null || echo "Cluster does not exist"
        exit 1
      }
      
      echo "Waiting for cluster to be ready..."
      TIMEOUT=3600  # 60 minutes max wait time
      ELAPSED=0
      
      while [ $ELAPSED -lt $TIMEOUT ]; do
        STATE=$(az aksarc show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
        echo "Cluster state: $STATE (${ELAPSED}s elapsed) - $(date)"
        
        if [ "$STATE" = "Succeeded" ]; then
          break
        elif [ "$STATE" = "Failed" ]; then
          echo "ERROR: Cluster creation failed!"
          az aksarc show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --only-show-errors
          exit 1
        elif [ "$STATE" = "Canceled" ]; then
          echo "ERROR: Cluster creation was canceled!"
          exit 1
        fi
        
        sleep 60  # Check every minute instead of every 30 seconds
        ELAPSED=$((ELAPSED + 60))
      done
      
      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: Timeout waiting for cluster creation"
        echo "Final cluster state check..."
        az aksarc show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --only-show-errors
        exit 1
      fi
      
      echo "Cluster created successfully at $(date)!"
      CLUSTER_ID=$(az aksarc show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
      SSH_KEY_ID=$(az sshkey show --name "$SSH_KEY_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || echo "")
      
      # Output results
      cat > $AZ_SCRIPTS_OUTPUT_PATH << EOF
{
  "clusterId": "$CLUSTER_ID",
  "sshKeyId": "$SSH_KEY_ID",
  "sshKeyName": "$SSH_KEY_NAME"
}
EOF
      
      echo "Deployment script completed successfully at $(date)!"
    '''
  }
  dependsOn: [
    roleAssignment
  ]
}

// Post-deployment script for extensions
resource extensionsDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (enableArgoCD || enableMetalLB) {
  name: '${clusterName}-extensions-script'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.55.0'
    timeout: 'PT45M'
    retentionInterval: 'PT2H'
    environmentVariables: [
      {
        name: 'CLUSTER_NAME'
        value: clusterName
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'ENABLE_ARGOCD'
        value: string(enableArgoCD)
      }
      {
        name: 'ENABLE_METALLB'
        value: string(enableMetalLB)
      }
    ]
    scriptContent: '''
      set -e
      echo "Installing extensions for cluster: $CLUSTER_NAME at $(date)"
      
      # Wait for cluster to be fully ready and connected to Arc
      echo "Waiting for cluster to be connected to Arc..."
      TIMEOUT=900  # 15 minutes
      ELAPSED=0
      
      while [ $ELAPSED -lt $TIMEOUT ]; do
        CONN_STATE=$(az connectedk8s show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" --query connectivityStatus -o tsv 2>/dev/null || echo "NotFound")
        echo "Arc connectivity state: $CONN_STATE (${ELAPSED}s elapsed) - $(date)"
        
        if [ "$CONN_STATE" = "Connected" ]; then
          break
        fi
        
        sleep 30
        ELAPSED=$((ELAPSED + 30))
      done
      
      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "WARNING: Timeout waiting for Arc connectivity, proceeding anyway..."
      fi
      
      if [ "$ENABLE_ARGOCD" = "true" ]; then
        echo "Installing ArgoCD extension at $(date)..."
        az k8s-extension create \
          --name argocd \
          --extension-type microsoft.argocd \
          --cluster-type connectedClusters \
          --resource-group "$RESOURCE_GROUP" \
          --cluster-name "$CLUSTER_NAME" \
          --auto-upgrade-minor-version true \
          --release-train stable \
          --only-show-errors || echo "ArgoCD extension installation failed or already exists"
      fi
      
      if [ "$ENABLE_METALLB" = "true" ]; then
        echo "Installing MetalLB extension at $(date)..."
        az k8s-extension create \
          --name metallb \
          --extension-type microsoft.metallb \
          --cluster-type connectedClusters \
          --resource-group "$RESOURCE_GROUP" \
          --cluster-name "$CLUSTER_NAME" \
          --auto-upgrade-minor-version true \
          --release-train stable \
          --only-show-errors || echo "MetalLB extension installation failed or already exists"
      fi
      
      echo "Extensions installation completed at $(date)"
      echo '{"status": "completed"}' > $AZ_SCRIPTS_OUTPUT_PATH
    '''
  }
  dependsOn: [
    aksArcDeploymentScript
  ]
}

// Output important values for post-deployment configuration
output clusterName string = clusterName
output clusterResourceId string = aksArcDeploymentScript.properties.outputs.clusterId
output acrLoginServer string = containerRegistry.properties.loginServer
output acrName string = containerRegistry.name
output sshKeyName string = aksArcDeploymentScript.properties.outputs.sshKeyName
output sshKeyId string = aksArcDeploymentScript.properties.outputs.sshKeyId
output customLocationResourceId string = customLocationResourceId
output logicalNetworkResourceId string = logicalNetworkResourceId

// Extension outputs
output argoCDExtensionName string = enableArgoCD ? 'argocd' : ''
output metalLBExtensionName string = enableMetalLB ? 'metallb' : ''

// Access commands
output clusterConnectionCommand string = 'az connectedk8s proxy -n ${clusterName} -g ${resourceGroup().name}'

// Manual extension installation commands (if automated installation fails)
output argoCDInstallCommand string = 'az k8s-extension create --name argocd --extension-type microsoft.argocd --cluster-type connectedClusters --resource-group ${resourceGroup().name} --cluster-name ${clusterName}'
output metalLBInstallCommand string = 'az k8s-extension create --name metallb --extension-type microsoft.metallb --cluster-type connectedClusters --resource-group ${resourceGroup().name} --cluster-name ${clusterName}'

// Build and deployment commands
output buildCommands string = '''
# Login to ACR and build Mario image
az acr login --name ${containerRegistry.name}
docker build -t ${containerRegistry.properties.loginServer}/mario-clone:v1 ../mario-clone
docker push ${containerRegistry.properties.loginServer}/mario-clone:v1
'''

output verificationCommands string = '''
# Verify cluster
az aksarc show --name ${clusterName} --resource-group ${resourceGroup().name}
az connectedk8s proxy -n ${clusterName} -g ${resourceGroup().name}

# Check extensions
az k8s-extension list --cluster-name ${clusterName} --resource-group ${resourceGroup().name} --cluster-type connectedClusters
'''

// ArgoCD Configuration commands for manual setup
output argoCDSetupCommands string = '''
# After cluster is ready and ArgoCD is installed, create the Mario application
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mario-clone
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/mgodfre3/orl-game
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
EOF
'''
