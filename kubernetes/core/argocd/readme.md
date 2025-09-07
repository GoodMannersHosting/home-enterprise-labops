# ArgoCD

```bash
# Install Base Resources; some resources may fail, we can loop through it twice to ensure all resources are applied
for i in 1 2; do kubectl apply -k kubernetes/core/argocd --server-side; done

# Template
helm template argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
--namespace argocd \
--create-namespace \
--version 8.3.0 \
--skip-crds \
--values kubernetes/core/argocd/values.yaml

# Deploy
helm upgrade --install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
--namespace argocd \
--version 8.3.5 \
--skip-crds \
--values kubernetes/core/argocd/values.yaml
```
