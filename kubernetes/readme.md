# Temporary Setup Commands

These commands will be wrapped behind GoTasks in the future.

## Gateway API

```bash
kubectl apply --server-side -k kubernetes/core/gateway-api
```

## Install Cilium

```bash
# Add the Cilium Helm repository and update
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium
helm upgrade --install cilium cilium/cilium \
--namespace=kube-system --version 1.17.5 \
--values kubernetes/core/kube-system/cilium/values.yaml

# Set up the BGP config
kubectl apply --server-side -k kubernetes/core/kube-system/cilium/bgp
```

## CoreDNS

```bash
# Add the CoreDNS Helm repository and update
helm repo add coredns https://coredns.github.io/helm
helm repo update

# Install CoreDNS
helm upgrade --install coredns coredns/coredns \
--namespace=kube-system --version 1.39.2 \
--values kubernetes/core/kube-system/coredns/values.yaml
```

## Istio

```bash
# Set the Istio Version
ISTIO_VERSION=1.26.0
# Add the Istio Helm repository and update
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

# Install Istio
helm upgrade --install istio-base istio/base \
--create-namespace --namespace istio-system \
--version ${ISTIO_VERSION} \
--values kubernetes/core/istio-system/istio-base.values.yaml

# Install Istiod
helm upgrade --install istiod istio/istiod -n istio-system \
--version ${ISTIO_VERSION} \
--values kubernetes/core/istio-system/istiod.values.yaml \
--wait

# Install Istio CNI
helm upgrade --install istio-cni istio/cni \
--namespace istio-system \
--version ${ISTIO_VERSION} \
--values kubernetes/core/istio-system/cni.values.yaml \
--wait

# Install Istio ZTunnel
helm upgrade --install istio-ztunnel istio/ztunnel \
--namespace istio-system \
--version ${ISTIO_VERSION} \
--values kubernetes/core/istio-system/ztunnel.values.yaml \
--wait
```

## Istio Ingress

```bash
helm install istio-ingress istio/gateway \
--create-namespace -n istio-ingress --wait
```

## Validation Steps

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.25/samples/bookinfo/platform/kube/bookinfo.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.25/samples/bookinfo/gateway-api/bookinfo-gateway.yaml
```

## Sealed Secrets

```bash
# Add the Sealed Secrets Helm repository and update
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

# Create the Sealed Secrets namespace
kubectl create namespace sealed-secrets

# Create the Sealed Secrets key
kubectl create secret tls sealed-secrets-key \
--cert=./keys/sealed-secret.crt \
--key=./keys/sealed-secret.key \
--namespace sealed-secrets

# Label the Sealed Secrets key for the Sealed Secrets controller
kubectl label secret/sealed-secrets-key \
--namespace sealed-secrets \
sealedsecrets.bitnami.com/sealed-secrets-key=true

# Install Sealed Secrets
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
--namespace sealed-secrets \
--version 2.17.2 --values kubernetes/core/sealed-secrets/values.yaml
```

## Cert Manager

```bash
# Set the Cert Manager version
export CERT_MANAGER_VERSION="v1.17.1"

# Add the Cert Manager Helm repository and update
kubectl apply --server-side \
-f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.crds.yaml"

# Add the Jetstack Helm repository and update
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install Cert Manager
helm upgrade --install cert-manager jetstack/cert-manager \
--create-namespace --namespace cert-manager \
--version ${CERT_MANAGER_VERSION}
```

## Metrics Server

```bash
# Add the Metrics Server Helm repository and update
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

# Install the Metrics Server
helm upgrade --install metrics-server metrics-server/metrics-server \
--namespace kube-system --version 3.12.2 \
--values kubernetes/core/kube-system/metrics-server/values.yaml
```

## Cluster API Initialization

Create a file at `~/.keys/proxmox` with the following content:

```yaml
url: https://url.here:8006
token: root@pam!capi
secret: secret-key-goes-here
```

Then, we can initialize Cluster API with the following command:

```bash
export PROXMOX_URL="$(cat ~/.keys/proxmox | grep url | awk '{print $2}')"
export PROXMOX_TOKEN="$(cat ~/.keys/proxmox | grep token | awk '{print $2}')"
export PROXMOX_SECRET="$(cat ~/.keys/proxmox | grep secret | awk '{print $2}')"

clusterctl init --ipam in-cluster:v1.0.1 \
--infrastructure proxmox:v0.7.0 \
--bootstrap talos:v0.6.7 \
--control-plane talos:v0.5.8
```
