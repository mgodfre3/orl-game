targetScope='subscription'

param azureLocation string
param deploymentResourceGroupName string
param customLocationResourceID string

// SSH Key parameters
param sshKeyName string
@description('Whether to create a new SSH key or use an existing one')
param createSshKey bool = true

// Logical network parameters
param logicalNetworkName string
@description('Whether to create a new logical network or use an existing one')
param createLogicalNetwork bool = false
@description('VM switch name for the logical network (required if creating new)')
param vmSwitchName string = ''
@description('Address prefix for the logical network (required if creating new)')
param addressPrefix string = ''
@description('Default gateway for the logical network (required if creating new)')
param defaultGateway string = ''
@description('DNS servers for the logical network (required if creating new)')
param dnsServers array = []
@description('IP allocation method for the logical network')
@allowed(['Static', 'Dynamic'])
param ipAllocationMethod string = 'Dynamic'
@description('VLAN ID for the logical network (optional)')
param vlanId int = 0

// Provisioned cluster parameters
param connectedClusterName string
param kubernetesVersion string
param controlPlaneVMSize string
param controlPlaneNodeCount int
param nodePoolName string
param nodePoolVMSize string
param nodePoolOSType string
param nodePoolCount int
param nodePoolLabel string
param nodePoolLabelValue string
param nodePoolTaint string
param netWorkProfilNetworkPolicy string
param networkProfileLoadBalancerCount int

resource deploymentResourceGroup'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: deploymentResourceGroupName
  location: azureLocation
}

// Create SSH key if requested
resource sshKey 'Microsoft.Compute/sshPublicKeys@2023-09-01' = if (createSshKey) {
  name: sshKeyName
  location: azureLocation
  properties: {
    // The public key will be generated automatically by Azure
  }
  dependsOn: [
    deploymentResourceGroup
  ]
}

module aksarcModule 'aksarc.bicep' = {
  name: '${deployment().name}-aks-arc'
  scope: resourceGroup(deploymentResourceGroupName)
  params:{
    azureLocation: azureLocation
    customLocationResourceID: customLocationResourceID
    
    // SSH Key parameters
    sshKeyName: sshKeyName
    createSshKey: createSshKey
    sshKeyResourceGroupName: deploymentResourceGroupName
    
    // Logical network parameters
    logicalNetworkName: logicalNetworkName
    createLogicalNetwork: createLogicalNetwork
    vmSwitchName: vmSwitchName
    addressPrefix: addressPrefix
    defaultGateway: defaultGateway
    dnsServers: dnsServers
    ipAllocationMethod: ipAllocationMethod
    vlanId: vlanId
    
    // Cluster parameters
    connectedClusterName: connectedClusterName
    kubernetesVersion: kubernetesVersion
    controlPlaneVMSize: controlPlaneVMSize
    controlPlaneNodeCount: controlPlaneNodeCount
    nodePoolName: nodePoolName
    nodePoolVMSize: nodePoolVMSize
    nodePoolOSType: nodePoolOSType
    nodePoolCount: nodePoolCount
    nodePoolLabel: nodePoolLabel
    nodePoolLabelValue: nodePoolLabelValue
    nodePoolTaint: nodePoolTaint
    netWorkProfilNetworkPolicy: netWorkProfilNetworkPolicy
    networkProfileLoadBalancerCount: networkProfileLoadBalancerCount
  }
  dependsOn: [
    deploymentResourceGroup
    sshKey
  ]
}

// Outputs
output connectedClusterId string = aksarcModule.outputs.connectedClusterId
output connectedClusterName string = aksarcModule.outputs.connectedClusterName
output logicalNetworkId string = aksarcModule.outputs.logicalNetworkId
output logicalNetworkName string = aksarcModule.outputs.logicalNetworkName
output provisionedClusterInstanceId string = aksarcModule.outputs.provisionedClusterInstanceId
output sshKeyId string = createSshKey ? sshKey.id : ''
output sshKeyName string = sshKeyName
output sshPublicKey string = createSshKey ? sshKey.properties.publicKey : ''
