// Bicep file to provision AKS and ACR
param location string = resourceGroup().location

param aksName string = 'mario-aks'
param acrName string = 'mariocloneacr'
param agentCount int = 1
param agentVMSize string = 'Standard_DS2_v2'
param adminUsername string = 'azureuser'


resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2023-05-01' = {
  name: aksName
  location: location
  properties: {
    dnsPrefix: aksName
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: agentCount
        vmSize: agentVMSize
        osType: 'Linux'
        mode: 'System'
      }
    ]
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7...your-public-key-here...'
          }
        ]
      }
    }
    servicePrincipalProfile: {
      clientId: 'msi'
      secret: ''
    }
    enableRBAC: true
    addonProfiles: {
      azurearc: {
        enabled: true
      }
    }
  }
}


// Arc and Flux resources are typically onboarded post-AKS creation using Azure CLI or ARM templates, not directly in Bicep for managed AKS. For best practice, remove these resources from Bicep and use post-deployment scripts for Arc onboarding and GitOps (Flux) setup.

output acrLoginServer string = acr.properties.loginServer
output aksNameOut string = aks.name
