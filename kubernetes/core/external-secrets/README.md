# external-secrets

[External Secrets Operator](https://external-secrets.io/) — syncs secrets
from OpenBao into native Kubernetes Secrets, so they don't need to live in
git as sealed secrets. The `openbao-labops` `ClusterSecretStore` authenticates
once with the controller's ServiceAccount and the namespaced `labops-eso`
role. Consumers only need an `ExternalSecret` that references this store.

## What's here

| File | Purpose |
|------|---------|
| `values.yaml` | Helm values for the `external-secrets` chart, installed into the `external-secrets` namespace by [`../../applications/external-secrets.yaml`](../../applications/external-secrets.yaml) |
| `clustersecretstore.yaml` | Cluster-wide connection to the `homelab-dan` OpenBao namespace using the read-only `labops-eso` role |

## Bootstrapping OpenBao's Kubernetes auth

The Kubernetes-auth mount, policies, and roles on the OpenBao side (not this
repo) are managed in `~/src/hcloud-security-cluster/bao/` — see
`setup-kubernetes-auth.sh` there. That bootstrap depends on
[`../kube-system/openbao-auth/`](../kube-system/openbao-auth/) being synced
first (it gives OpenBao a token to call this cluster's TokenReview API).

## Adding a new OpenBao-backed secret

For a new consumer in namespace `<ns>`:

1. Store the value below `secret/dan/` in the `homelab-dan` OpenBao namespace.
2. Add an `ExternalSecret` with `secretStoreRef.name: openbao-labops` and
   `secretStoreRef.kind: ClusterSecretStore`.

## Troubleshooting

```bash
kubectl get clustersecretstore openbao-labops
kubectl describe clustersecretstore openbao-labops

kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>

kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```
