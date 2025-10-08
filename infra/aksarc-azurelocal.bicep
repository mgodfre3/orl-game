// Bicep template for deploying AKS Arc cluster on Azure Local (Azure Stack HCI)
// This template creates the necessary resources for Mario Clone game deployment

@description('The name of the AKS Arc cluster')
param clusterName string = 'mario-aksarc'

@description('The Azure region where resources will be deployed')
param location string = 'eastus'

@description('The resource group name')
param resourceGroupName string = resourceGroup().name

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

@description('Azure AD admin group object IDs (comma-separated)')
param aadAdminGroupObjectIds array

@description('Azure Arc Gateway resource ID')
param gatewayResourceId string

@description('Enable Azure Hybrid Benefit')
param enableAhub bool = true

@description('Kubernetes version')
param kubernetesVersion string = '1.28.9'

// Variables for constructing resource IDs
var subscriptionId = subscription().subscriptionId
var customLocationResourceId = '/subscriptions/${subscriptionId}/resourcegroups/${resourceGroupName}/providers/microsoft.extendedlocation/customlocations/${customLocationName}'
var logicalNetworkResourceId = '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/microsoft.azurestackhci/logicalnetworks/${logicalNetworkName}'

// SSH Key resource
resource sshKey 'Microsoft.Compute/sshPublicKeys@2023-03-01' = {
  name: sshKeyName
  location: location
  properties: {
    publicKey: '' // This will be populated during deployment
  }
}

// AKS Arc Cluster
resource aksArcCluster 'Microsoft.Kubernetes/connectedClusters@2024-01-01' = {
  name: clusterName
  location: location
  kind: 'ProvisionedCluster'
  properties: {
    // Basic cluster configuration
    agentPublicKeyCertificate: ''
    aadProfile: {
      managed: true
      adminGroupObjectIDs: aadAdminGroupObjectIds
      enableAzureRBAC: true
    }
    
    // Extended location for Azure Stack HCI
    extendedLocation: {
      type: 'CustomLocation'
      name: customLocationResourceId
    }
    
    // Infrastructure configuration
    infrastructure: {
      count: controlPlaneCount
    }
    
    // Node pool configuration  
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        mode: 'System'
        maxPods: 110
        osDiskSizeGB: 128
        enableAutoScaling: false
      }
    ]
    
    // Network configuration
    networkProfile: {
      networkPlugin: 'calico'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.96.0.0/12'
      dnsServiceIP: '10.96.0.10'
      loadBalancerSku: 'standard'
    }
    
    // Linux profile with SSH key
    linuxProfile: {
      adminUsername: 'azureuser'
      ssh: {
        publicKeys: [
          {
            keyData: sshKey.properties.publicKey
          }
        ]
      }
    }
    
    // Azure Stack HCI specific configuration
    azureStackHCIProfile: {
      logicalNetworkIds: [
        logicalNetworkResourceId
      ]
    }
    
    // Additional properties
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    
    // Gateway configuration for Arc connectivity
    gateway: {
      resourceId: gatewayResourceId
    }
    
    // Azure Hybrid Benefit
    licenseProfile: enableAhub ? {
      azureHybridBenefit: 'True'
    } : null
  }
  
  tags: {
    purpose: 'mario-game'
    environment: 'demo'
    deployment: 'gitops'
  }
}

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
    anonymousPullEnabled: false
  }
  
  tags: {
    purpose: 'mario-game'
    environment: 'demo'
  }
}

// Output important values for post-deployment configuration
output clusterName string = aksArcCluster.name
output clusterResourceId string = aksArcCluster.id
output acrLoginServer string = containerRegistry.properties.loginServer
output acrName string = containerRegistry.name
output sshKeyName string = sshKey.name
output customLocationResourceId string = customLocationResourceId
output logicalNetworkResourceId string = logicalNetworkResourceId

// Output deployment commands for GitOps setup
output fluxExtensionCommand string = 'az k8s-extension create --name fluxExtension --extension-type microsoft.flux --cluster-type connectedClusters --resource-group ${resourceGroupName} --cluster-name ${clusterName}'
output metallbExtensionCommand string = 'az k8s-extension create --name metallb --extension-type microsoft.metallb --cluster-type connectedClusters --resource-group ${resourceGroupName} --cluster-name ${clusterName}'
output gitopsConfigCommand string = 'az k8s-configuration flux create --resource-group ${resourceGroupName} --cluster-name ${clusterName} --cluster-type connectedClusters --name mario-gitops --namespace mario-gitops --url https://github.com/mgodfre3/orl-game --branch main --kustomization name=main path=./k8s prune=true'
