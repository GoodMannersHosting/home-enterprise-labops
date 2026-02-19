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

## Golang-samples Build (Multi-arch)

Builds the [golang-samples run/helloworld](https://github.com/GoogleCloudPlatform/golang-samples/tree/main/run/helloworld) Dockerfile for amd64 and arm64, then pushes a multi-arch manifest to Harbor. Uses Buildah (rootless, no Docker-in-Docker). Flow: [Clone] → [Build amd64 ∥ Build arm64] → [Manifest + Push] (4 containers total).

### Prerequisites

1. Create Harbor credentials secret (before first run):

```bash
kubectl create secret docker-registry harbor-push-cicd -n cicd \
  --docker-server=harbor.cloud.danmanners.com \
  --docker-username=<robot-or-user> \
  --docker-password=<token-or-password>
```

Create a Robot Account in Harbor's `library` project with Push Artifact permission, or use a user with push access.

2. Ensure the `library/golang-samples` repository exists in Harbor (or create it on first push).

3. For arm64 on amd64 nodes, ensure `qemu-user-static` is available in the Buildah image or add an init step.
4. Each architecture has a dedicated ceph-block PVC (workspace, amd64-storage, arm64-storage).

### Submit the workflow

```bash
argo submit -n cicd --from workflowtemplate/golang-samples-build
```

### Result

Pushes `harbor.cloud.danmanners.com/library/golang-samples:demo` as a multi-arch manifest. Intermediate tags `demo-amd64` and `demo-arm64` remain in Harbor (optional cleanup step can be added).
