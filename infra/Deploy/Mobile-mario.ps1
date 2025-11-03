.\infra\deploy\\master-deploy.ps1 `
    -ResourceGroupName "ACX-MobileAzL" `
    -SubscriptionId "fbaf508b-cb61-4383-9cda-a42bfa0c7bc9" `
    -CustomLocationName "ACX-Mobile" `
    -LogicalNetworkName "mobile-lnet-vlan50" `
    -ClusterName "mobile-mario" `
    -MetalLBIPRange "172.25.10.200-201" `
    -MarioIP "172.25.10.200" `
    -ArgocdIP "172.25.10.201" `
    -AADAdminGroupObjectId "be0c17dc-9a37-48c5-9691-751a27a4c1b9","f5157bd2-8ce4-48b6-82df-69b9de7540a9","af0ac67a-fcb3-4c19-a950-c32f938ee163" `
    -ACRName "acxcontregwus2" `
    -ACRResourceGroupName "ACX-ContainerRegistry-WUS2" `
    -Location "eastus"



    az account set --subscription "fbaf508b-cb61-4383-9cda-a42bfa0c7bc9"

az aksarc create `
  --name "mobile-mario" `
  --resource-group "ACX-MobileAzL" `
  --custom-location "/subscriptions/fbaf508b-cb61-4383-9cda-a42bfa0c7bc9/resourcegroups/ACX-MobileAzL/providers/microsoft.extendedlocation/customlocations/Mobile" `
  --vnet-ids "/subscriptions/fbaf508b-cb61-4383-9cda-a42bfa0c7bc9/resourceGroups/ACX-MobileAzL/providers/microsoft.azurestackhci/logicalnetworks/mobile-lnet-vlan50" `
  --aad-admin-group-object-ids "be0c17dc-9a37-48c5-9691-751a27a4c1b9,f5157bd2-8ce4-48b6-82df-69b9de7540a9,af0ac67a-fcb3-4c19-a950-c32f938ee163" `
  --generate-ssh-keys `
  --load-balancer-count 0 `
  --kubernetes-version 1.30.9 `
  --control-plane-count 1 `
  --node-count 2 `
  --node-vm-size Standard_A4_v2