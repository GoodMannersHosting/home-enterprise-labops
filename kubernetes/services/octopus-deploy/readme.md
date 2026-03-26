# Octopus Deploy

```
# Apply First Resources
kubectl apply -k kubernetes/services/octopus-deploy

# Add Helm Repositories
helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
helm repo update

# Render/Deploy MSSQL (BJW-S app-template v4.4.0)
helm template octopus-mssql --namespace octopus \
bjw-s/app-template --version 4.4.0 \
--values kubernetes/services/octopus-deploy/mssql.values.yaml | \
kubectl apply -f-

# Render/Deploy Octopus Deploy
helm template octopus-deploy --namespace octopus \
oci://ghcr.io/octopusdeploy/octopusdeploy-helm \
--version 1.11.0 \
--values kubernetes/services/octopus-deploy/od.values.yaml | \
kubectl apply -f-
```
