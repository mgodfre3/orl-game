param azureLocation string
param customLocationResourceID string

// SSH Key parameters
param sshKeyName string
@description('Whether to create a new SSH key or use an existing one')
param createSshKey bool = true
param sshKeyResourceGroupName string

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
@allowed(['Linux', 'Windows'])
param nodePoolOSType string
param nodePoolCount int
param nodePoolLabel string
param nodePoolLabelValue string
param nodePoolTaint string
param netWorkProfilNetworkPolicy string
param networkProfileLoadBalancerCount int

// Reference existing SSH key if not creating a new one
resource sshKeyExisting 'Microsoft.Compute/sshPublicKeys@2023-09-01' existing = if (!createSshKey) {
  name: sshKeyName
  scope: resourceGroup(sshKeyResourceGroupName)
}

// Get the SSH key resource from the subscription level (created in main.bicep)
resource sshKeyNew 'Microsoft.Compute/sshPublicKeys@2023-09-01' existing = if (createSshKey) {
  name: sshKeyName
  scope: resourceGroup(sshKeyResourceGroupName)
}

// Conditionally create logical network if it doesn't exist and createLogicalNetwork is true
resource logicalNetworkNew 'Microsoft.AzureStackHCI/logicalNetworks@2024-01-01' = if (createLogicalNetwork) {
  name: logicalNetworkName
  location: azureLocation
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationResourceID
  }
  properties: {
    vmSwitchName: vmSwitchName
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: addressPrefix
          ipAllocationMethod: ipAllocationMethod
          vlan: vlanId > 0 ? {
            vlanId: vlanId
          } : null
          routeTable: {
            routes: !empty(defaultGateway) ? [
              {
                name: 'default'
                properties: {
                  addressPrefix: '0.0.0.0/0'
                  nextHopIpAddress: defaultGateway
                }
              }
            ] : []
          }
          ipPools: ipAllocationMethod == 'Static' ? [
            {
              name: 'default'
              properties: {
                addressPrefix: addressPrefix
                autoAssign: 'True'
              }
            }
          ] : []
        }
      }
    ]
    dhcpOptions: !empty(dnsServers) ? {
      dnsServers: dnsServers
    } : null
  }
}

// Reference existing logical network if not creating a new one
resource logicalNetworkExisting 'Microsoft.AzureStackHCI/logicalNetworks@2024-01-01' existing = if (!createLogicalNetwork) {
  name: logicalNetworkName
}

// Create the connected cluster.
// This is the Arc representation of the AKS cluster, used to create a Managed Identity for the provisioned cluster.
resource connectedCluster 'Microsoft.Kubernetes/ConnectedClusters@2024-01-01' = {
  location: azureLocation
  name: connectedClusterName
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'ProvisionedCluster'
  properties: {
    // agentPublicKeyCertificate must be empty for provisioned clusters that will be created next.
    agentPublicKeyCertificate: ''
    aadProfile: {
      enableAzureRBAC: false
    }
  }
}

// Create the provisioned cluster instance. 
// This is the actual AKS cluster and provisioned on your Azure Local cluster via the Arc Resource Bridge.
resource provisionedClusterInstance 'Microsoft.HybridContainerService/provisionedClusterInstances@2024-01-01' = {
  name: 'default'
  scope: connectedCluster
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationResourceID
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    linuxProfile: {
      ssh: {
        publicKeys: [
          {
            keyData: createSshKey ? sshKeyNew.properties.publicKey : sshKeyExisting.properties.publicKey
          }
        ]
      }
    }
    controlPlane: {
      count: controlPlaneNodeCount
      vmSize: controlPlaneVMSize
    }
    networkProfile: {
      networkPolicy: netWorkProfilNetworkPolicy
      loadBalancerProfile: {
        count: networkProfileLoadBalancerCount
      }
    }
    agentPoolProfiles: [
      {
        name: nodePoolName
        count: nodePoolCount
        vmSize: nodePoolVMSize
        osType: nodePoolOSType
        nodeLabels: {
          '${nodePoolLabel}': nodePoolLabelValue
        }
        nodeTaints: [
          nodePoolTaint
        ]
      }
    ]
    cloudProviderProfile: {
      infraNetworkProfile: {
        vnetSubnetIds: [
          createLogicalNetwork ? logicalNetworkNew.id : logicalNetworkExisting.id
        ]
      }
    }
    storageProfile: {
      nfsCsiDriver: {
        enabled: true
      }
      smbCsiDriver: {
        enabled: true
      }
    }
  }
  dependsOn: [
    createLogicalNetwork ? logicalNetworkNew : logicalNetworkExisting
    createSshKey ? sshKeyNew : sshKeyExisting
  ]
}

// Create SSH key if requested
resource sshKey 'Microsoft.Compute/sshPublicKeys@2023-09-01' = if (createSshKey) {
  name: sshKeyName
  location: azureLocation
  properties: {
    // The public key will be generated automatically by Azure
  }
}

// Outputs
output connectedClusterId string = connectedCluster.id
output connectedClusterName string = connectedCluster.name
output logicalNetworkId string = createLogicalNetwork ? logicalNetworkNew.id : logicalNetworkExisting.id
output logicalNetworkName string = logicalNetworkName
output provisionedClusterInstanceId string = provisionedClusterInstance.id
output sshKeyId string = createSshKey ? sshKeyNew.id : sshKeyExisting.id
output sshPublicKey string = createSshKey ? sshKeyNew.properties.publicKey : sshKeyExisting.properties.publicKey
