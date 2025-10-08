## Configuring Flux GitOps with Azure Arc on AKS

After deploying your AKS cluster and Azure Arc onboarding, follow these steps to enable Flux GitOps:

### 1. Install the Flux extension on your AKS cluster

```sh
az k8s-extension create \
  --name fluxExtension \
  --extension-type microsoft.flux \
  --cluster-type managedClusters \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <AKS_CLUSTER_NAME>
```

```sh
az k8s-extension create \
  --name fluxExtension \
  --extension-type microsoft.flux \
  --cluster-type managedClusters \
  --resource-group california \
  --cluster-name ca-mario
```

### 2. Create a Flux configuration to sync your Git repository

```sh
az k8s-configuration flux create \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <AKS_CLUSTER_NAME> \
  --cluster-type managedClusters \
  --name <CONFIG_NAME> \
  --namespace <NAMESPACE> \
  --url https://github.com/<YOUR_GITHUB_USER>/<YOUR_REPO> \
  --branch main \
  --kustomization name=main path=./k8s prune=true
```

- Replace `<RESOURCE_GROUP>`, `<AKS_CLUSTER_NAME>`, `<CONFIG_NAME>`, `<NAMESPACE>`, `<YOUR_GITHUB_USER>`, and `<YOUR_REPO>` with your actual values.

### 3. (Optional) For private repositories, add authentication

Add these flags to the `az k8s-configuration flux create` command:
```sh
  --https-user <your-github-username> --https-key <your-personal-access-token>
```

### 4. Verify Flux is running

```sh
kubectl get pods -n flux-system
kubectl get kustomizations -A
```

### References

- [Azure Arc Flux documentation](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-use-gitops-flux2)
- [az k8s-extension docs](https://learn.microsoft.com/en-us/cli/azure/k8s-extension)

## Installing MetalLB with Azure Arc

After your AKS cluster is onboarded to Azure Arc, you can install the MetalLB load balancer using the Azure CLI:

### 1. Install the MetalLB extension

```sh
az k8s-extension create \
  --name metallb \
  --extension-type microsoft.metallb \
  --cluster-type managedClusters \
  --resource-group <RESOURCE_GROUP> \
  --cluster-name <AKS_CLUSTER_NAME>
```

### 2. Configure MetalLB IP Address Pool

Create a MetalLB IP address pool YAML (example: `metallb-config.yaml`):

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-addresspool
  namespace: kube-system
spec:
  addresses:
    - 10.20.243.220-10.20.243.221
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: kube-system
spec: {}
```

Apply the configuration:

```sh
kubectl apply -f metallb-config.yaml
```

### 3. Verify MetalLB is running

```sh
kubectl get pods -n kube-system -l app=metallb
kubectl get ipaddresspool -n kube-system
```

### References

- [Azure Arc MetalLB documentation](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/azure-arc-k8s-metrics-lb)
- [az k8s-extension docs](https://learn.microsoft.com/en-us/cli/azure/k8s-extension)

