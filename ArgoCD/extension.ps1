
$Subscription="fbaf508b-cb61-4383-9cda-a42bfa0c7bc9"
$RESOURCE_GROUP="California"
$custom_location="California"
$CLUSTER_NAME="ca-mario"
$Cluster_ResourceGroup="California"
$connectedClusterRg="California"
$ssh_key="ca-mario-key"
$nodepoolvm_size="Standard_D"
$nodecount="1"

$location="eastus"
$custom_location="/subscriptions/$Subscription/resourcegroups/$RESOURCE_GROUP/providers/microsoft.extendedlocation/customlocations/$custom_location"
$entra_groups=@("be0c17dc-9a37-48c5-9691-751a27a4c1b9,f5157bd2-8ce4-48b6-82df-69b9de7540a9")
$gwid="/subscriptions/fbaf508b-cb61-4383-9cda-a42bfa0c7bc9/resourceGroups/AdaptiveCloud-ArcGateway/providers/Microsoft.HybridCompute/gateways/ac-arcgateway-eus"

az k8s-extension create --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --cluster-type connectedClusters --name argocd --extension-type Microsoft.ArgoCD --release-train preview --config deployWithHighAvailability=false --config namespaceInstall=false --config "config-maps.argocd-cmd-params-cm.data.application\.namespaces=namespace1,namespace2"

az k8s-runtime load-balancer enable --resource-uri subscriptions/$Subscription/resourceGroups/$connectedClusterRg/providers/Microsoft.Kubernetes/connectedClusters/$CLUSTER_NAME
