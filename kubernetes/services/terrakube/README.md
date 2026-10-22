# terrakube

Self-hosted [Terrakube](https://terrakube.io/) — the open source Terraform /
OpenTofu run platform (workspaces, runs, state, private module registry,
RBAC, CLI/API). Deployed from the
[official Helm chart](https://charts.terrakube.io) (version-pinned in
[`../../applications/terrakube.yaml`](../../applications/terrakube.yaml)).

The chart pins the app image via `appVersion` (currently 2.33.1); the
component images are overridden to the latest stable release (2.33.3) with
the `version:` keys in `values.yaml` — remove those once the chart ships
with the new app version.

## What gets deployed

| Component | Notes |
|-----------|-------|
| `terrakube-api` | REST API + job queue, talks to PostgreSQL, Valkey, MinIO, DEX |
| `terrakube-ui` | Web UI (nginx serving the static build) |
| `terrakube-executor` | Runs the terraform/tofu jobs (1 pod = 1 concurrent run) |
| `terrakube-registry` | Private module/provider registry (`terrakube-reg.cloud.danmanners.com`) |
| `terrakube-dex` | DEX OIDC provider in front of **Authentik** (the app's SSO layer) |
| `terrakube-minio` | S3 storage for terraform state + job outputs (20Gi `ceph-block-retain`) |
| `terrakube-valkey` | Job queue / cache (no auth, cluster-internal only) |
| `terrakube-db-init` | Job that creates the `terrakube` role + database on shared `db-rw.database.svc` |

Auth flow: UI → DEX (`https://terrakube-api.cloud.danmanners.com/dex`) →
Authentik app `terrakube` → token with `groups` claim → Terrakube API
(validates against DEX). Users in the `terrakube-admins` group are admins.

Public endpoints (certs from the `*.cloud.danmanners.com` wildcard, DNS via
external-dns, health via Gatus on the UI route):

- UI: `https://terrakube-ui.cloud.danmanners.com`
- API (+ DEX under `/dex`): `https://terrakube-api.cloud.danmanners.com`
- Registry: `https://terrakube-reg.cloud.danmanners.com`

## Secrets

All secrets live in OpenBao (`keeper.goodmanners.services`, `homelab-dan`
namespace, `secret/` mount) under `dan/terrakube/` and are synced into the
`terrakube` namespace by the `ExternalSecret` resources in this directory
(`openbao-labops` ClusterSecretStore).

| OpenBao path | K8s secret it produces | Keys |
|--------------|------------------------|------|
| `dan/terrakube/api` | `terrakube-api-secrets` | `PatSecret`*, `InternalSecret`*, `DexClientId`, `TerrakubeRedisPassword`, `DatasourcePassword`, `AwsStorageAccessKey`, `AwsStorageSecretKey` |
| `dan/terrakube/executor` | `terrakube-executor-secrets` | `InternalSecret`*, `TerrakubeRedisPassword`, `AwsTerraformStateAccessKey`, `AwsTerraformStateSecretKey`, `AwsTerraformOutputAccessKey`, `AwsTerraformOutputSecretKey` |
| `dan/terrakube/registry` | `terrakube-registry-secrets` | `PatSecret`*, `InternalSecret`*, `AppClientId`, `AwsStorageAccessKey`, `AwsStorageSecretKey` |
| `dan/terrakube/minio` | `terrakube-minio-auth` | `rootUser`, `rootPassword` |
| `dan/terrakube/dex` | `terrakube-dex-secrets` | `client-id`, `client-secret` (Authentik app) |
| `dan/terrakube/postgres` | `terrakube-db-creds` | `POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASS` |

\* **Stored base64-encoded on purpose.** The chart b64-encodes `patSecret` /
`internalSecret` when generating these secrets and the API b64-decodes them
at runtime, so the values you store in OpenBao must already be base64.
Generate one with `openssl rand -base64 24` and store the output verbatim —
do **not** base64-encode it a second time.

## One-time setup (before first sync)

### 1. Authentik app

In `https://auth.goodmanners.services` (same provider as the `argo-cd` /
`argo-workflows` apps):

1. Create application **`terrakube`**
   - Client type: **Confidential**
   - Redirect URIs: `https://terrakube-api.cloud.danmanners.com/dex/callback`
   - Scopes: enable **`groups`** (keep `openid`, `profile`, `email`,
     `offline_access`)
2. Create a group **`terrakube-admins`** and add your user to it (this group
   name is what `security.adminGroup` in `values.yaml` checks).
3. Copy the app's **Client ID** and **Client Secret** (see below).

### 2. OpenBao secrets

```bash
export VAULT_ADDR=https://keeper.goodmanners.services
bao login -method=oidc role=keeper-admin

# Random values (generate once, reuse across the secrets below)
PAT=$(openssl rand -base64 24)            # store verbatim (already base64)
INTERNAL=$(openssl rand -base64 24)       # store verbatim (already base64)
MINIO_USER="terrakube"
MINIO_PASS=$(openssl rand -base64 18)
DB_PASS=$(openssl rand -base64 18)

bao write secret/dan/terrakube/api \
  "PatSecret=${PAT}" \
  "InternalSecret=${INTERNAL}" \
  "DexClientId=terrakube" \
  "TerrakubeRedisPassword=" \
  "DatasourcePassword=${DB_PASS}" \
  "AwsStorageAccessKey=${MINIO_USER}" \
  "AwsStorageSecretKey=${MINIO_PASS}"

bao write secret/dan/terrakube/executor \
  "InternalSecret=${INTERNAL}" \
  "TerrakubeRedisPassword=" \
  "AwsTerraformStateAccessKey=${MINIO_USER}" \
  "AwsTerraformStateSecretKey=${MINIO_PASS}" \
  "AwsTerraformOutputAccessKey=${MINIO_USER}" \
  "AwsTerraformOutputSecretKey=${MINIO_PASS}"

bao write secret/dan/terrakube/registry \
  "PatSecret=${PAT}" \
  "InternalSecret=${INTERNAL}" \
  "AppClientId=terrakube" \
  "AwsStorageAccessKey=${MINIO_USER}" \
  "AwsStorageSecretKey=${MINIO_PASS}"

bao write secret/dan/terrakube/minio \
  "rootUser=${MINIO_USER}" \
  "rootPassword=${MINIO_PASS}"

bao write secret/dan/terrakube/dex \
  "client-id=<AUTHENTIK_CLIENT_ID>" \
  "client-secret=<AUTHENTIK_CLIENT_SECRET>"

bao write secret/dan/terrakube/postgres \
  "POSTGRES_HOST=db-rw.database.svc" \
  "POSTGRES_USER=terrakube" \
  "POSTGRES_PASS=${DB_PASS}"
```

(You can also create these through the OpenBao web UI; the key names above
must match the `property:` fields in the `externalsecret-*.yaml` files.)

### 3. Deploy

Push to `main`; ArgoCD picks up the `terrakube` app, applies the
ExternalSecrets (secrets materialise within seconds) and the chart. First
sync order looks like:

1. namespace + ExternalSecrets + db-init job
2. minio/valkey/dex start, `terrakube-db-init` completes
3. api/executor/registry come up (API waits for the DB via init container)
4. external-dns creates the three DNS records, Gatus starts probing the UI

## Verify

```bash
kubectl get pods -n terrakube
kubectl logs -n terrakube -l app=terrakube-api --tail=50   # look for "Started ApplicationServer"
kubectl get externalsecret -n terrakube                    # all Ready
curl -fsS https://terrakube-api.cloud.danmanners.com/.well-known/openid-configuration
# UI: https://terrakube-ui.cloud.danmanners.com -> "Sign in with GMH (Authentik)"
```

## Operations

- **Rotate the Authentik client**: change `client-secret` (and
  `client-id` if needed) in OpenBao under `dan/terrakube/dex`; ESO refreshes
  the secret within an hour (or `kubectl delete secret terrakube-dex-secrets
  -n terrakube` to force it immediately). DEX restarts on the config
  checksum change only when `configSecret.create` is true — with the env-var
  approach a dex pod restart (`kubectl rollout restart deploy terrakube-dex -n terrakube`)
  picks the new value up.
- **More concurrent runs**: bump `executor.replicaCount` in `values.yaml`.
- **State backups**: the terraform state is in MinIO (bucket `terrakube`);
  back it up alongside the `database` namespace's PostgreSQL (the
  `terrakube` schema).
- **Admin access**: add users to the `terrakube-admins` group in Authentik.
  Personal/team API tokens are managed inside Terrakube itself.
