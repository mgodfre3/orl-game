using 'main.bicep'

param azureLocation = 'eastus' // TODO: add your Azure location.
param deploymentResourceGroupName = 'acx-game' // The resource group where bicep template deploys to.
// This ID should refer to an existing custom location resource.
param customLocationResourceID = '/subscriptions/fbaf508b-cb61-4383-9cda-a42bfa0c7bc9/resourcegroups/california/providers/microsoft.extendedlocation/customlocations/california'

// SSH Key parameters
param sshKeyName = 'ca-mario-ssh-key' // TODO: add your SSH key name
param createSshKey = true // Set to true to create new SSH key, false to use existing

// Logical network parameters
param logicalNetworkName = 'ca-lnet-vlan26' // TODO: add your logical network name
param createLogicalNetwork = false // Set to true to create new logical network, false to use existing
// The following parameters are only needed if createLogicalNetwork = true
param vmSwitchName = 'Default Switch' // TODO: add your Hyper-V virtual switch name (required if creating new)
param addressPrefix = '192.168.26.0/24' // TODO: add your network CIDR (required if creating new)
param defaultGateway = '192.168.26.1' // TODO: add your default gateway IP (required if creating new)
param dnsServers = ['8.8.8.8', '8.8.4.4'] // TODO: add your DNS servers (required if creating new)
param ipAllocationMethod = 'Dynamic' // Dynamic or Static IP allocation
param vlanId = 26 // TODO: add your VLAN ID (0 for no VLAN)

// Provisioned cluster
param connectedClusterName = 'ca-mario' // TODO: add your connected cluster name.
param kubernetesVersion = '1.30.9' // TODO: add your Kubernetes version
// You may leave the following values as is for simplicity.
param controlPlaneVMSize = 'Standard_A4_v2' // TODO: add your control plane node size.
param controlPlaneNodeCount = 1 // TODO: add your control plane node count.
param nodePoolName = 'nodepool1' // TODO: add your node pool node name.
param nodePoolVMSize = 'Standard_A4_v2' // TODO: add your node pool VM size.
param nodePoolOSType = 'Linux' // TODO: add your node pool OS type.
param nodePoolCount = 1 // TODO: add your node pool node count.
param nodePoolLabel = 'myLabel' // TODO: add your node pool label key.
param nodePoolLabelValue = 'myValue' // TODO: add your node pool label value.
param nodePoolTaint = 'myTaint' // TODO: add your node pool taint.
param netWorkProfilNetworkPolicy = 'calico' // TODO: add your networkProfile's networkPolicy.
param networkProfileLoadBalancerCount = 0 // TODO: add your networkProfile's loadBalancerProfile.count.
