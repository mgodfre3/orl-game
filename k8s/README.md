# Mario Clone Kubernetes Deployment

This directory contains Kubernetes manifests for deploying the Mario Clone game application.

## Directory Structure

- `namespace.yaml` - Creates the `mario-game` namespace
- `deployment.yaml` - Mario Clone application deployment
- `service.yaml` - LoadBalancer service for external access
- `config.yaml` - ConfigMap for application configuration
- `hpa.yaml` - Horizontal Pod Autoscaler configuration
- `kustomization.yaml` - Kustomize configuration for the main application
- `metallb/` - MetalLB IP pool configurations

## Deployment Order

**Important**: MetalLB configuration must be deployed before the application to ensure LoadBalancer services get IP addresses assigned.

### Option 1: Using Kustomize (Recommended)

```bash
# 1. First, apply MetalLB configuration (must be in kube-system namespace)
kubectl apply -f metallb/metallb-config.yaml

# 2. Then apply the main application
kubectl apply -k .
```

### Option 2: Using Individual Manifests

```bash
# 1. Apply MetalLB IP pool configuration
kubectl apply -f metallb/metallb-config.yaml

# 2. Apply application manifests
kubectl apply -f namespace.yaml
kubectl apply -f config.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f hpa.yaml
```

### Option 3: Using ArgoCD

If you're using ArgoCD, make sure to:
1. Apply the MetalLB configuration manually first: `kubectl apply -f metallb/metallb-config.yaml`
2. Then sync the ArgoCD application which will deploy resources from the kustomization

## MetalLB Configuration

The MetalLB configuration defines the IP address pool that LoadBalancer services can use:

- **IP Pool**: Two individual IP addresses: `172.25.10.200` and `172.25.10.201`
- **Namespace**: `kube-system` (required by MetalLB)
- **Pool Name**: `mario-pool`

### Available MetalLB Configurations

There are multiple MetalLB configuration files for different scenarios:

1. **`metallb/metallb-config.yaml`** (Primary, Recommended)
   - Format: Two separate /32 addresses: `172.25.10.200/32` and `172.25.10.201/32`
   - Includes both IPs needed for mario-clone (172.25.10.200) and argocd (172.25.10.201)
   
2. **`mario-metallb-config.yaml`** (Single IP)
   - Format: Single /32 address: `172.25.10.200/32`
   - Only includes IP for mario-clone service
   
3. **`kube-system-metallb-pool.yaml`** (Auto-assign)
   - Format: IP range: `172.25.10.200-172.25.10.201`
   - Auto-assigns IPs from the range
   - Enables auto-assignment feature

**Recommendation**: Use `metallb/metallb-config.yaml` for production deployments.

## Troubleshooting MetalLB IP Assignment

If your LoadBalancer service shows `EXTERNAL-IP` as `<pending>`:

### 1. Check MetalLB is installed

```bash
kubectl get pods -n metallb-system
```

If MetalLB is not installed, install it using:

```bash
# For AKS Arc clusters
az k8s-extension create \
  --name metallb \
  --extension-type microsoft.metallb \
  --cluster-type connectedClusters \
  --resource-group <your-rg> \
  --cluster-name <your-cluster>

# For standard Kubernetes clusters
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
```

### 2. Verify IP Address Pool is configured

```bash
kubectl get ipaddresspool -n kube-system
kubectl get l2advertisement -n kube-system
```

Expected output should show the `mario-pool` IPAddressPool and `mario-l2` L2Advertisement.

If not present, apply the configuration:

```bash
kubectl apply -f metallb/metallb-config.yaml
```

### 3. Check for IP conflicts

```bash
kubectl get svc -A | grep LoadBalancer
```

Ensure that the requested IP in `service.yaml` (`172.25.10.200`) is within the MetalLB pool and not already assigned to another service.

### 4. Check service configuration

```bash
kubectl describe svc mario-clone-service -n mario-game
```

Look for events that might indicate why the IP isn't being assigned.

### 5. Check MetalLB controller logs

```bash
kubectl logs -n metallb-system deployment/controller
kubectl logs -n kube-system deployment/controller
```

Look for errors related to IP allocation or configuration issues.

## Service Configuration

The Mario Clone service is configured as:

- **Type**: LoadBalancer
- **Requested IP**: `172.25.10.200` (specified via `loadBalancerIP`)
- **Port**: 80 (HTTP)
- **Selector**: `app: mario-clone`

### Note on loadBalancerIP Deprecation

The `loadBalancerIP` field is deprecated in Kubernetes 1.24+ and may be removed in future versions. For better forward compatibility, consider using MetalLB-specific annotations instead:

```yaml
metadata:
  annotations:
    metallb.universe.tf/address-pool: mario-pool
    # Or specify exact IP:
    # metallb.universe.tf/loadBalancer-IPs: 172.25.10.200
```

For now, `loadBalancerIP` is still supported and works with MetalLB, but plan to migrate to annotations in future updates.

## Image Configuration

The deployment uses a container image from Azure Container Registry (ACR). The image reference is managed through Kustomize:

- **Base Image**: `mario-clone`
- **Repository**: Set in `kustomization.yaml`
- **Tag**: Set in `kustomization.yaml` (default: `v4`)

To use a different tag:

```bash
cd k8s
kustomize edit set image mario-clone=<your-acr>.azurecr.io/mario-clone:<new-tag>
kubectl apply -k .
```

## Scaling

The deployment includes a Horizontal Pod Autoscaler (HPA) that automatically scales based on CPU utilization:

- **Min Replicas**: 1
- **Max Replicas**: 10
- **Target CPU**: 50%

View current scaling status:

```bash
kubectl get hpa -n mario-game
```

## Verifying Deployment

```bash
# Check all resources
kubectl get all -n mario-game

# Check service external IP
kubectl get svc mario-clone-service -n mario-game

# Check pod logs
kubectl logs -n mario-game -l app=mario-clone

# Access the application (once EXTERNAL-IP is assigned)
curl http://<EXTERNAL-IP>
```

## Clean Up

To remove the deployment:

```bash
# Remove application resources
kubectl delete -k .

# Optionally remove MetalLB configuration
kubectl delete -f metallb/metallb-config.yaml
```
