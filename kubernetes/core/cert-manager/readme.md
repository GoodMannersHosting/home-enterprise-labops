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

## Troubleshooting with PowerDNS

```bash
# Get the PowerDNS API Key
export powerdns_api_key=$(kubectl get secrets -n powerdns as-secrets -ojson | jq -r '.data."api-key"|@base64d')
# Set the PowerDNS Zone
export zone="example.com"
curl -sH "X-API-Key: ${powerdns_api_key}" \
"http://172.31.0.16:8081/api/v1/servers/localhost/zones/${zone}" | \
jq -r '.rrsets[] | select(.name|startswith("whatever_hostname_goes_here"))'
```
