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
| `proxy.yaml` | `LiteLLMProxy` — owns the router's Deployment/Service/ConfigMap (no `modelSelector`, so it adopts every `LiteLLMModel` in `aiml`). No `spec.route` — see "DNS: the CNAME workaround" below |
| `model-nvidia.yaml` | `LiteLLMModel` pointing at `nvidia-vllm-core.aiml.svc.cluster.local:8080`, reusing the existing `nvidia-llm-api-key` secret |
| `model-intel.yaml` | `LiteLLMModel` pointing at `intel-vllm-core.aiml.svc.cluster.local:8080`, reusing the existing `intel-llm-api-key` secret |
| `serviceaccount.yaml` | `vault-litellm-reader` — the identity OpenBao's `kubernetes-labops` auth role trusts for reading the master key |
| `secretstore.yaml` | `SecretStore` named `openbao-litellm`, pointing at `https://keeper.goodmanners.services` (OpenBao), authenticating via Kubernetes auth as `vault-litellm-reader` |
| `externalsecret.yaml` | `ExternalSecret` that materializes `LITELLM_MASTER_KEY` for the router as the `litellm-master-key` Secret, synced hourly from OpenBao |
| `servicemonitor.yaml` | Scrapes the router's `/metrics` (enabled via `spec.callbacks`) for the existing `monitoring` (kube-prometheus-stack) install |
| `httproute.yaml` | Hand-authored `HTTPRoute` (not operator-owned) fronting the `router` Service on `gwapi`'s `https-cloud` listener — needed so it can carry the `external-dns.alpha.kubernetes.io/controller: "false"` and `gatus.home-operations.com/*` annotations the operator's own route type doesn't expose |
| `external-name.yaml` | `ExternalName` Service that gives `llm.cloud.danmanners.com` a CNAME to `unifi-home.homelab.danmanners.com` instead of a direct record to the Gateway's LB IP |

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

## DNS: the CNAME workaround

`llm.cloud.danmanners.com` is a CNAME to `unifi-home.homelab.danmanners.com`,
not a direct record to the Cilium Gateway's LB IP (`172.31.0.10`) — same
pattern as `grafana`, `harbor`, `argocd`, and `argo-workflows`
(`kubernetes/core/monitoring/external.svc.yaml`,
`kubernetes/core/harbor/networking/external-name.yaml`,
`kubernetes/core/argocd/external-dns.yaml`,
`kubernetes/core/argo-workflows/external-dns.yaml`).

Why: the site-to-site VPN between this cluster's network and clients outside
the homelab LAN is IPsec ("Dan's Site to Site" in UniFi). Its local routed-
networks list includes `172.31.0.0/23`, but `Established` only reflects the
Phase 1 (IKE) SA — Phase 2 negotiates traffic selectors per subnet pair, and
both ends have to agree on them. If the far end's tunnel config was never
updated to include the full `/23`, traffic to an IP like `172.31.0.10` inside
it can silently fail (TCP SYN sent, no reply, eventual client-side timeout)
even though the tunnel itself shows connected and the subnet shows routed.
`mtr` from outside the LAN confirms this: the local gateway hop replies
instantly, the next hop never does. `unifi-home.homelab.danmanners.com`
apparently already falls inside whatever *was* negotiated, which is
presumably why the other four services route through it instead. Fixing this
for real means confirming the Phase 2 selectors on both ends of the tunnel
include `172.31.0.0/23` — outside what this repo can express.

Practical effect: `httproute.yaml` still exists and still matters — once
traffic reaches the Gateway (via the CNAME's target, LAN, or a fixed tunnel),
Envoy still needs the route to send it to the `router` Service. Only the DNS
mechanism changed.

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
- **Uptime**: `httproute.yaml` carries the standard `gatus.home-operations.com/*`
  annotations, same as every other service's route.
