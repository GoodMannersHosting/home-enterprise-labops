# CI Workflows

Example Argo Workflows in the `cicd` namespace, deployed via ArgoCD.

## Webhook Example

A webhook-triggered workflow that you can trigger from the internet with curl. The workflow runs with a service account that has **no RBAC permissions** (no cluster access).

### Prerequisites

1. Argo Workflows server with `client` auth mode (Bearer token) enabled
2. ArgoCD has synced the `ci-workflows` application

### Obtain a token

Argo Workflows requires the legacy token from a Secret (not `kubectl create token`). After the argo-workflows and ci-workflows apps have synced, run:

```bash
TOKEN="Bearer $(kubectl get secret webhook-client.service-account-token -n argo -o=jsonpath='{.data.token}' | base64 --decode)"
```

The Secret is created by the argo-workflows Helm chart. It may take a few seconds after sync for the token to be populated.

### Trigger the workflow

```bash
# Basic trigger (uses default message "triggered via webhook")
curl -X POST "https://workflows.cloud.danmanners.com/api/v1/events/cicd/webhook" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'

# With custom message
curl -X POST "https://workflows.cloud.danmanners.com/api/v1/events/cicd/webhook" \
  -H "Authorization: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message": "hello from curl"}'
```

### Security model

- **webhook-client** SA (argo namespace): Minimal RBAC (create workflows, get templates in `cicd` only). Used for API auth.
- **workflow-no-access** SA: Minimal RBAC (workflowtaskresults create/patch only). No access to secrets, other pods, or cluster resources.
