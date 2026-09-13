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

## What's here

| File | Purpose |
|------|---------|
| `proxy.yaml` | `LiteLLMProxy` — owns the router's Deployment/Service/ConfigMap and its `HTTPRoute` (no `modelSelector`, so it adopts every `LiteLLMModel` in `aiml`) |
| `model-nvidia.yaml` | `LiteLLMModel` pointing at `nvidia-vllm-core.aiml.svc.cluster.local:8080`, reusing the existing `nvidia-llm-api-key` secret |
| `model-intel.yaml` | `LiteLLMModel` pointing at `intel-vllm-core.aiml.svc.cluster.local:8080`, reusing the existing `intel-llm-api-key` secret |
| `secret.litellm-master-key.yaml` | Sealed `LITELLM_MASTER_KEY` for the router itself (generate with `seal-litellm-master-key.sh`) |
| `servicemonitor.yaml` | Scrapes the router's `/metrics` (enabled via `spec.callbacks`) for the existing `monitoring` (kube-prometheus-stack) install |

Runs in `applyMode: file` (the CRD default) — no Postgres/Redis dependency,
config renders into a ConfigMap and the proxy rolls on change. Good enough for
a small number of static backends; if per-app virtual keys or a live admin UI
become worth it later, switch to `applyMode: api` (needs a Postgres-backed
proxy, see `cnpg`/`database`) and add `LiteLLMVirtualKey` resources.

## First-time setup

This secret can't be generated in CI/without cluster access — `kubeseal`
encrypts against the live sealed-secrets controller's public cert. Run once,
from a machine with `kubectl`/`kubeseal` pointed at the cluster:

```bash
./seal-litellm-master-key.sh
# commit secret.litellm-master-key.yaml, sync Argo
```

Until `secret.litellm-master-key.yaml` exists, this Kustomization won't build
and the `llm-router` Argo app will fail to sync.

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
