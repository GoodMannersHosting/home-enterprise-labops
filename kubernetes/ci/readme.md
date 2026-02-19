# CI Workflows

Example Argo Workflows in the `cicd` namespace, deployed via ArgoCD.

## Webhook Example

A webhook-triggered workflow that you can trigger from the internet with curl. The workflow runs with a service account that has **no RBAC permissions** (no cluster access).

### Prerequisites

1. Argo Workflows server with `client` auth mode (Bearer token) enabled
2. ArgoCD has synced the `ci-workflows` application

### Obtain a token

```bash
kubectl create token webhook-client -n cicd --duration=8760h
```

### Trigger the workflow

```bash
# Basic trigger (uses default message "triggered via webhook")
curl -X POST "https://workflows.cloud.danmanners.com/api/v1/events/cicd/webhook" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'

# With custom message
curl -X POST "https://workflows.cloud.danmanners.com/api/v1/events/cicd/webhook" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "hello from curl"}'
```

### Security model

- **webhook-client** SA: Minimal RBAC (create workflows, get templates in `cicd` only). Used for API auth.
- **workflow-no-access** SA: No RoleBindings. Workflow step pods run with zero cluster access.
