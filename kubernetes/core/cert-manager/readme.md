# Cert-Manager Installation

```bash
# Install the CRDs
kubectl apply --server-side \
-f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.crds.yaml

# Configure the Helm repositories
helm repo add jetstack https://charts.jetstack.io
helm repo add cert-manager-webhook-pdns https://zachomedia.github.io/cert-manager-webhook-pdns
helm repo update

# Install the Cert Manager and the PowerDNS Webhook Charts
helm upgrade --install cert-manager jetstack/cert-manager \
--version v1.17.2 \
--namespace cert-manager \
--create-namespace \
--set installCRDs=false \
--values kubernetes/core/cert-manager/values.cert-manager.yaml

helm upgrade --install \
cert-manager-webhook-pdns cert-manager-webhook-pdns/cert-manager-webhook-pdns \
--version 3.2.3 \
--namespace cert-manager \
--values kubernetes/core/cert-manager/values.cert-manager-webhook-pdns.yaml
```
