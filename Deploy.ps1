$Subscription="fbaf508b-cb61-4383-9cda-a42bfa0c7bc9"
$RESOURCE_GROUP="California"
$custom_location="California"
$CLUSTER_NAME="ca-mario"
$Cluster_ResourceGroup="California"
$ssh_key="ca-mario-key"
$nodepoolvm_size="Standard_A2_v2"
$lnet_name="ca-lnet-vlan26"
$location="eastus"
$custom_location="/subscriptions/$Subscription/resourcegroups/$RESOURCE_GROUP/providers/microsoft.extendedlocation/customlocations/$custom_location"
$VNET_arm_id="/subscriptions/$Subscription/resourceGroups/$RESOURCE_GROUP/providers/microsoft.azurestackhci/logicalnetworks/$lnet_name"
$entra_groups=@("be0c17dc-9a37-48c5-9691-751a27a4c1b9,f5157bd2-8ce4-48b6-82df-69b9de7540a9")
$gwid="/subscriptions/fbaf508b-cb61-4383-9cda-a42bfa0c7bc9/resourceGroups/AdaptiveCloud-ArcGateway/providers/Microsoft.HybridCompute/gateways/ac-arcgateway-eus"

#$control_plan_ip="172.21.228.59"

az sshkey create --name $ssh_key --resource-group $RESOURCE_GROUP --location $location
$pubkey=az sshkey show --name $ssh_key --resource-group $RESOURCE_GROUP | ConvertFrom-Json


az aksarc create -g $Cluster_ResourceGroup --custom-location $custom_location -n $CLUSTER_NAME --vnet-ids $vnet_arm_id --aad-admin-group-object-ids "be0c17dc-9a37-48c5-9691-751a27a4c1b9,f5157bd2-8ce4-48b6-82df-69b9de7540a9,af0ac67a-fcb3-4c19-a950-c32f938ee163" --control-plane-count 1  --enable-ahub --node-vm-size $nodepoolvm_size --node-count 2   --ssh-key-value $pubkey.publickey --gateway-id $gwid
