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
must be synced first — it installs the `LiteLLMProxy`/`LiteLLMModel`/`LiteLLMTeam`/
`LiteLLMVirtualKey` CRDs this directory's manifests depend on. If it syncs
after this app, ArgoCD's `selfHeal` will retry until the CRDs land; no manual
ordering needed.

The `external-secrets` Argo app ([`../../applications/external-secrets.yaml`](../../applications/external-secrets.yaml))
must also be synced first. It installs the External Secrets CRDs and the
cluster-wide `openbao-labops` store used by this app.

The `database` Argo app syncs both `../../core/database/` and
`../../services/database/`. This keeps the shared CNPG `Cluster`, its managed
roles, and its snapshot policies under one GitOps application.

The `valkey-operator` Argo app ([`../../applications/valkey-operator.yaml`](../../applications/valkey-operator.yaml))
must be synced first — it installs the `ValkeyCluster` CRD `valkeycluster.yaml`
depends on.

## What's here

| File | Purpose |
|------|---------|
| `proxy.yaml` | `LiteLLMProxy` — owns the router's Deployment/Service/ConfigMap and its `HTTPRoute` (no `modelSelector`, so it adopts every `LiteLLMModel` in `aiml`); runs `applyMode: api` |
| `model-nvidia.yaml` | `LiteLLMModel` pointing at `nvidia-vllm-core.aiml.svc.cluster.local:8080`, reusing the existing `nvidia-llm-api-key` secret |
| `model-intel.yaml` | `LiteLLMModel` pointing at `intel-vllm-core.aiml.svc.cluster.local:8080`, reusing the existing `intel-llm-api-key` secret |
| `model-bonsai.yaml` | `LiteLLMModel` pointing at a bare-metal endpoint (`10.2.30.217:8080`), authenticated via `bonsai-llm-api-key` |
| `externalsecret.bonsai.yaml` | `ExternalSecret` that materializes `bonsai-llm-api-key` from OpenBao |
| `team.yaml` | `LiteLLMTeam` `scum` — shared team the virtual keys below belong to |
| `virtualkeys.yaml` | One `LiteLLMVirtualKey` per member of `scum` (dan, james, tyler) |
| `ui-credentials.yaml` | `ExternalSecret` that materializes the admin UI's `UI_PASSWORD` from OpenBao through the cluster-wide store |
| `db/` | `database`-namespace resources: the OpenBao-backed `ExternalSecret` for the `litellm` Postgres role and the native CNPG `Database` resource. The generated Secret is reflected into `aiml` for the proxy |
| `externalsecret.yaml` | `ExternalSecret` that materializes `LITELLM_MASTER_KEY` for the router as the `litellm-master-key` Secret, synced hourly from OpenBao |
| `valkeycluster.yaml` | `ValkeyCluster` (valkey-operator) — single-shard, cache-only (no persistence) cluster backing the response cache, virtual-key auth cache, and OIDC PKCE storage below |
| `servicemonitor.yaml` | Scrapes the router's `/metrics` (enabled via `spec.callbacks`) for the existing `monitoring` (kube-prometheus-stack) install |

Runs `applyMode: api`: models still get declared as `LiteLLMModel` resources
here and rendered by the operator, but they (and virtual keys/teams) push to
the proxy's DB-backed admin API live instead of a ConfigMap render + restart.
This is what makes the admin UI and `LiteLLMVirtualKey`/`LiteLLMTeam` work —
both need the proxy running against Postgres.

## Database

The proxy's Postgres database lives on the shared cluster (`db-rw.database.svc.cluster.local`,
owned by `../../core/database/`), not a dedicated one — same pattern as
`open-webui`/`artifact-keeper`/`forgejo`/`keycloak`. Unlike those, though, the
`litellm` role and database are provisioned declaratively via CNPG's own CRDs
instead of a `postgres-init` Job:

- `../../core/database/database.yaml` — `spec.managed.roles` on the shared
  `db` Cluster declares the `litellm` login role, pointing at a
  `passwordSecret` named `litellm-db-credentials` (must live in `database`,
  alongside the Cluster).
- `db/externalsecret.yaml` — materializes the OpenBao value at
  `homelab-dan/secret/dan/aiml/litellm-db-credentials` as a CNPG-compatible
  basic-auth Secret. Reflection annotations mirror it into `aiml`, where
  `proxy.yaml` uses it to compose `DATABASE_URL`.
- `db/database.yaml` — a CNPG `Database` CR that creates the `litellm`
  database itself, owned by that role.

## Response & auth caching (Valkey)

`valkeycluster.yaml` deploys a `ValkeyCluster` (via `valkey-operator`,
installed by the `valkey-operator` Argo app) that replaced
`ollama-open-webui-redis` as the Redis backend for everything litellm needs:
OIDC PKCE storage, the exact-match response cache, and the shared virtual-key
auth cache. It's dedicated to the router so cache traffic can't compete with
or evict open-webui's unrelated Redis usage.

**Why `shards: 1`:** valkey-operator only runs Cluster-mode Valkey (no
standalone/sentinel), and litellm's Redis client issues multi-key operations
(pipelines, batched MSET/MGET) that Cluster mode only permits when every key
in the batch hashes to the same slot — something we don't control on
litellm's side. A single shard puts all 16384 slots on one primary, so
cross-slot errors can't happen; `replicas: 1` still gives it a failover
target. `workloadType: Deployment` skips PVCs entirely: everything stored
here is either a cache or fine to lose on restart (a pod restart just means a
cold cache/re-login, not an outage), matching the operator's own guidance for
cache-only clusters.

**Wiring (`proxy.yaml`):** the operator's headless Service for a cluster
named `llm-router` is `valkey-llm-router.aiml.svc.cluster.local:6379`
(convention is `valkey-<clustername>`, not `<clustername>-valkey`). Because
it's Cluster mode, litellm needs `REDIS_CLUSTER_NODES` rather than plain
`REDIS_HOST`/`REDIS_PORT` — `litellm/_redis.py`'s `get_redis_client()`
branches on `REDIS_CLUSTER_NODES` for *every* Redis use in the app (not just
caching), so setting it once makes PKCE storage, the response cache, and the
auth cache all cluster-aware. One seed node is enough; the client discovers
the rest of the topology itself via `CLUSTER SLOTS`.

`litellmSettings` then wires two independent features on top of that
connection:

- `cache: true` / `cache_params` — exact-match response caching. Identical
  `/chat/completions` and `/embeddings` requests (same model, messages,
  params) are served from Valkey instead of re-hitting the backend
  `llama-server`. Keys live under the `litellm.cache` namespace with a 1h TTL
  (`cache_params.ttl`). Verify it's live with:
  ```bash
  curl -s https://llm.cloud.danmanners.com/cache/ping \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY"
  ```
- `enable_redis_auth_cache: true` — mirrors virtual-key (token) auth
  verification results into Valkey instead of each replica keeping its own
  in-memory-only copy. This is what actually improves "cache-hits on
  tokens": without it, every proxy pod/worker independently re-warms its key
  cache against Postgres after every deploy or restart, and budget/rate-limit
  lookups fall through to the DB more often. Tune
  `general_settings.user_api_key_cache_ttl` (default 60s) if key changes need
  to propagate faster, or `user_api_key_cache_max_size` if there are more
  than ~200 active keys/teams/users per worker.

Both are exact-match, hash-keyed caches — a single changed token/param in a
request is a miss. Neither needs credentials: the cluster is ClusterIP-only
within `aiml`.

**Caveat:** valkey-operator's `v1alpha1` API is explicitly marked "not ready
for production use" upstream. It's still the best fit here (no other
operator speaks both Valkey and Kubernetes natively), but keep an eye on
upstream API changes, and don't lean on it for anything beyond a
rebuildable cache.

## Admin UI

Setting `DATABASE_URL` turns on litellm's built-in admin UI automatically, at
`https://llm.cloud.danmanners.com/ui`. It gets its own login instead of
falling back to the master key: both username and password come from
`litellm-ui-credentials` — sourced from OpenBao (see Secret source: OpenBao
below). Fetch the credentials with:

```bash
kubectl get secret litellm-ui-credentials -n aiml \
  -o jsonpath='{.data.username}' | base64 -d
kubectl get secret litellm-ui-credentials -n aiml \
  -o jsonpath='{.data.password}' | base64 -d
```

## Teams & virtual keys

`team.yaml` defines a `scum` team (`tyler` as admin; `dan`/`james` as
members) and `virtualkeys.yaml` mints one `LiteLLMVirtualKey` per member,
scoped to that team. Each key lands in its own Secret
(`llm-router-key-<name>`, key `key`) minted live through the proxy's admin
API — that's why this only works under `applyMode: api`. Fetch a key with:

```bash
kubectl get secret llm-router-key-dan -n aiml \
  -o jsonpath='{.data.key}' | base64 -d
```

Add a new person by appending to both `spec.members` in `team.yaml` and a new
`LiteLLMVirtualKey` block in `virtualkeys.yaml` (`userID` matching the member,
`teamID: scum`). Neither key currently sets `maxBudget`/`tpmLimit`/`rpmLimit`
— add those per-key or at the team level if spend needs capping.

## Admin UI SSO (Authentik)

The admin UI uses SSO via Authentik as a Generic OIDC provider with PKCE
enabled for secure authorization. The proxy is configured with:

- `GENERIC_CLIENT_ID` / `GENERIC_CLIENT_SECRET` — from `litellm-sso-credentials`
  secret (sourced from OpenBao)
- `GENERIC_AUTHORIZATION_ENDPOINT` — `https://auth.goodmanners.services/application/o/authorize/`
- `GENERIC_TOKEN_ENDPOINT` — `https://auth.goodmanners.services/application/o/token/`
- `GENERIC_USERINFO_ENDPOINT` — `https://auth.goodmanners.services/application/o/userinfo/`
- `PROXY_BASE_URL` — `https://llm.cloud.danmanners.com`

Users click the SSO login button on the UI and are redirected to Authentik.

**First login:** After a user logs in via SSO for the first time, copy their
user ID from the UI (Internal Users page) and set it in OpenBao to make them
a proxy admin:

```bash
BAO_NAMESPACE=homelab-dan bao kv put secret/dan/aiml/litellm-proxy-admin \
  proxy-admin-id="<user-id-from-ui>"
```

Then add the environment variable to `proxy.yaml` and redeploy. This gives the
user full admin access to see all keys and spend.

**Fallback login:** Username/password login is still available at
`https://llm.cloud.danmanners.com/fallback/login`.

## Secret source: OpenBao

The master key, UI password, SSO credentials, and database credentials live in
the `homelab-dan` OpenBao namespace below `secret/dan/aiml/`. The shared
`openbao-labops` `ClusterSecretStore` authenticates as the External Secrets
controller through the `kubernetes-labops` mount and `labops-eso` role.

To rotate the UI password:

```bash
BAO_NAMESPACE=homelab-dan bao kv put secret/dan/aiml/litellm-ui-credentials \
  password="$(openssl rand -base64 24)"
```

To rotate the SSO client secret:

```bash
# Update the client secret in Authentik first, then in OpenBao
BAO_NAMESPACE=homelab-dan bao kv put secret/dan/aiml/litellm-sso-credentials \
  client-secret="$(openssl rand -hex 32)"
```

To rotate the master key:

```bash
BAO_NAMESPACE=homelab-dan bao kv put secret/dan/aiml/litellm-master-key \
  master-key="sk-$(openssl rand -hex 32)"
```

The ExternalSecrets pick up changes within one hour. Force an immediate resync
with:

```bash
kubectl annotate externalsecret litellm-master-key -n aiml \
  force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret litellm-ui-credentials -n aiml \
  force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret litellm-sso-credentials -n aiml \
  force-sync=$(date +%s) --overwrite
kubectl annotate externalsecret litellm-db-credentials -n database \
  force-sync=$(date +%s) --overwrite
```

## Endpoints

| Audience | URL |
|----------|-----|
| **In-cluster** | `http://router.aiml.svc.cluster.local:4000/v1` |
| **LAN / public** | `https://llm.cloud.danmanners.com/v1` |

DNS resolves directly to the Cilium Gateway's LB IP (`172.31.0.10`) via the
standard `gateway-httproute` external-dns source — no CNAME indirection.
(A previous version of this file routed through
`unifi-home.homelab.danmanners.com` — same trick `grafana`/`harbor`/`argocd`/
`argo-workflows` still use — to work around a site-to-site VPN routing bug on
the far end's `core-router`: reply traffic for the VTI tunnel's inner subnet
was falling through to a WAN default route instead of back into the tunnel.
Fixed on the router side; no longer needed here.)

### Auth

Clients send:

```http
Authorization: Bearer <LITELLM_MASTER_KEY>
```

A per-user virtual key (see Teams & virtual keys) works the same way and is
scoped to `scum`'s models/budget instead of having full admin access.

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
