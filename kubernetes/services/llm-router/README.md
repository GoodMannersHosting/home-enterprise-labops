# llm-router

A single OpenAI-compatible endpoint in front of every llama.cpp (`llama-server`)
deployment in the cluster, via [litellm-operator](https://github.com/home-operations/litellm-operator).
Instead of clients juggling `nvidia-vllm`'s and `intel-vllm`'s separate
LoadBalancer IPs and API keys, they hit one host with one key and pick a
backend by `model` name.

Despite the app names, **neither backend is actually vLLM** — both
`nvidia-vllm` and `intel-vllm` run `ghcr.io/ggml-org/llama.cpp`'s
`llama-server`. See `../intel-vllm/README.md` for why the name stuck.

## Prerequisite

The `litellm-operator` Argo app ([`../../applications/litellm-operator.yaml`](../../applications/litellm-operator.yaml))
must be synced first — it installs the `LiteLLMProxy`/`LiteLLMModel` CRDs this
directory's manifests depend on. If it syncs after this app, ArgoCD's
`selfHeal` will retry until the CRDs land; no manual ordering needed.

The `external-secrets` Argo app ([`../../applications/external-secrets.yaml`](../../applications/external-secrets.yaml))
must also be synced first — it installs the `SecretStore`/`ExternalSecret`
CRDs `secretstore.yaml`/`externalsecret.yaml` depend on. The operator itself
runs in the `external-secrets` namespace; the `SecretStore` here is
namespaced to `aiml` since this secret has exactly one consumer.

## What's here

| File | Purpose |
|------|---------|
| `proxy.yaml` | `LiteLLMProxy` — owns the router's Deployment/Service/ConfigMap and its `HTTPRoute` (no `modelSelector`, so it adopts every `LiteLLMModel` in `aiml`) |
| `model-nvidia.yaml` | `LiteLLMModel` pointing at `nvidia-vllm-core.aiml.svc.cluster.local:8080`, reusing the existing `nvidia-llm-api-key` secret |
| `model-intel.yaml` | `LiteLLMModel` pointing at `intel-vllm-core.aiml.svc.cluster.local:8080`, reusing the existing `intel-llm-api-key` secret |
| `serviceaccount.yaml` | `vault-litellm-reader` — the identity OpenBao's `kubernetes-labops` auth role trusts for reading the master key |
| `secretstore.yaml` | `SecretStore` named `openbao-litellm`, pointing at `https://keeper.goodmanners.services` (OpenBao), authenticating via Kubernetes auth as `vault-litellm-reader` |
| `externalsecret.yaml` | `ExternalSecret` that materializes `LITELLM_MASTER_KEY` for the router as the `litellm-master-key` Secret, synced hourly from OpenBao |
| `servicemonitor.yaml` | Scrapes the router's `/metrics` (enabled via `spec.callbacks`) for the existing `monitoring` (kube-prometheus-stack) install |

Runs in `applyMode: file` (the CRD default) — no Postgres/Redis dependency,
config renders into a ConfigMap and the proxy rolls on change. Good enough for
a small number of static backends; if per-app virtual keys or a live admin UI
become worth it later, switch to `applyMode: api` (needs a Postgres-backed
proxy, see `cnpg`/`database`) and add `LiteLLMVirtualKey` resources.

## Secret source: OpenBao

`LITELLM_MASTER_KEY` lives in the OpenBao instance at
`https://keeper.goodmanners.services` (managed in
`~/src/hcloud-security-cluster/bao/`), not in git — no sealed secret here.
`secretstore.yaml` authenticates to it as the `vault-litellm-reader`
ServiceAccount via a Kubernetes auth mount (`kubernetes-labops`) that trusts
this cluster's TokenReview API; see
`~/src/hcloud-security-cluster/bao/setup-kubernetes-auth.sh` for how that
trust and the read-only `eso-labops-litellm` policy are bootstrapped. The
Vault role behind it (`eso-litellm`) only grants read on this one secret
path — if more secrets migrate off sealed-secrets later, they'll each get
their own scoped `SecretStore`/role rather than widening this one.

To set or rotate the key (needs a Vault root/admin token, run from a machine
with `bao` configured against `keeper.goodmanners.services`):

```bash
bao kv put secret/labops/aiml/litellm-master-key \
  master-key="sk-$(openssl rand -hex 32)"
```

`externalsecret.yaml` picks up the change within its `refreshInterval` (1h);
force an immediate resync with:

```bash
kubectl annotate externalsecret litellm-master-key -n aiml \
  force-sync=$(date +%s) --overwrite
```

## Endpoints

| Audience | URL |
|----------|-----|
| **In-cluster** | `http://router.aiml.svc.cluster.local:4000/v1` |
| **LAN / public** | `https://llm.cloud.danmanners.com/v1` |

DNS is automatic: `external-dns` already watches the `gateway-httproute`
source for the `cloud.danmanners.com` zone, so no per-service annotation or
manual record is needed (unlike `intel-vllm`'s dedicated LoadBalancer).

### Auth

Clients send:

```http
Authorization: Bearer <LITELLM_MASTER_KEY>
```

### Smoke test

```bash
curl -s https://llm.cloud.danmanners.com/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

curl -s https://llm.cloud.danmanners.com/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"nvidia-llama","messages":[{"role":"user","content":"hi"}],"max_tokens":32}'
```

Swap `model` for `intel-llama` to hit the Arc B70 box instead.

## Observability

- **Metrics**: `servicemonitor.yaml` and the matching ones added to
  `../nvidia-vllm/` and `../intel-vllm/` all carry `release: monitoring` —
  the label kube-prometheus-stack's Prometheus requires by default, assuming
  the `monitoring` Argo app's Helm release is named `monitoring` (the Argo CD
  default when no `helm.releaseName` is set). Confirm with
  `kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'`
  and adjust the label if the release is actually named something else.
- **Uptime**: added as a static entry in `../../core/gatus/resources/config.yaml`
  rather than the usual `gatus.home-operations.com/*` annotation, because the
  operator owns this `HTTPRoute` and doesn't expose an annotations field on it.
