# ArgoCD

```bash
# Template
helm template argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
--namespace argocd \
--create-namespace \
--version 8.0.0 \
--skip-crds \
--values kubernetes/core/argocd/values.yaml

# Deploy
helm upgrade --install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
--namespace argocd \
--version 8.0.0 \
--skip-crds \
--values kubernetes/core/argocd/values.yaml
```
