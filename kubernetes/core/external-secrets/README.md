# external-secrets

[External Secrets Operator](https://external-secrets.io/) — syncs secrets
from OpenBao into native Kubernetes Secrets, so they don't need to live in
git as sealed secrets. Only the operator itself lives here; each consumer
owns its own `SecretStore`/`ExternalSecret` in its own namespace (see
[`../../services/llm-router/`](../../services/llm-router/) for the first
one), since OpenBao access here is granted per-secret via narrowly-scoped
Vault policies rather than one broadly-shared connection.

## What's here

| File | Purpose |
|------|---------|
| `values.yaml` | Helm values for the `external-secrets` chart, installed into the `external-secrets` namespace by [`../../applications/external-secrets.yaml`](../../applications/external-secrets.yaml) |

## Bootstrapping OpenBao's Kubernetes auth

The Kubernetes-auth mount, policies, and roles on the OpenBao side (not this
repo) are managed in `~/src/hcloud-security-cluster/bao/` — see
`setup-kubernetes-auth.sh` there. That bootstrap depends on
[`../kube-system/openbao-auth/`](../kube-system/openbao-auth/) being synced
first (it gives OpenBao a token to call this cluster's TokenReview API).

## Adding a new OpenBao-backed secret

For a new consumer in namespace `<ns>`:

1. In `~/src/hcloud-security-cluster/bao/`, add a policy scoped to the new
   secret's path and a role (`bao/kubernetes/*.json`) bound to a new
   ServiceAccount name in `<ns>`.
2. In `<ns>`, add a `ServiceAccount`, a namespaced `SecretStore` (vault
   provider, `auth.kubernetes` pointing at that role/ServiceAccount), and an
   `ExternalSecret` referencing it — see
   [`../../services/llm-router/secretstore.yaml`](../../services/llm-router/secretstore.yaml)
   and `externalsecret.yaml` as a template.

## Troubleshooting

```bash
kubectl get secretstore -A
kubectl describe secretstore <name> -n <namespace>

kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>

kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```
