# Meticulous namespace secrets (Sealed Secrets / External Secrets)

Do not commit cleartext credentials. Create secrets in-cluster (for example with [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)) using the keys below.

## 1. `meticulous-db-owner` (required before CNPG can bootstrap)

Referenced by the `Cluster` CR (`spec.bootstrap.initdb.secret`). Must exist **before** the `meticulous-db` cluster reconciles.

| Key        | Description                                              |
| ---------- | -------------------------------------------------------- |
| `username` | Must match `spec.bootstrap.initdb.owner` (`meticulous`). |
| `password` | Strong password for the application database owner.      |

## 2. `meticulous-db-app` (operator-managed)

CloudNative PG creates this secret when the cluster is ready. It includes a PostgreSQL URI with TLS/credentials appropriate for in-cluster use.

| Key   | Used by                                                                                                           |
| ----- | ----------------------------------------------------------------------------------------------------------------- |
| `uri` | `MET_DATABASE__URL` on `met-api` and `met-controller`; migrations use the same URL via `MET_API__RUN_MIGRATIONS`. |

You do not seal this secret yourself; wait for the operator. If pods fail before it exists, let the cluster finish reconciling or restart the deployment.

## 3. `meticulous-runtime` (required for app workloads)

| Key                     | Description                                                                                      |
| ----------------------- | ------------------------------------------------------------------------------------------------ |
| `jwt_api_secret`        | HS256 secret for the HTTP API (`MET_JWT__SECRET`). Use a long random string (32+ bytes).         |
| `jwt_controller_secret` | `MET_CONTROLLER_JWT_SECRET` (must be **32+ characters** per controller binary).                  |
| `s3_access_key`         | S3 access key for SeaweedFS / other S3 endpoint (must match how you configure the object store). |
| `s3_secret_key`         | Matching secret key.                                                                             |

Optional: add `builtin_secrets_master_key` and wire it through `MET_BUILTIN_SECRETS_MASTER_KEY` in `values.yaml` if you use built-in stored secret encryption.

## 4. NATS JWT / creds (optional)

The bundled NATS config allows anonymous clients (homelab default). For JWT-only NATS, add volumes and env from your `nsc` exports (`MET_NATS_CREDENTIALS_FILE` / controller `MET_NATS_CREDS_PATH`, `MET_NATS_ACCOUNT_SIGNING_SEED`, etc.) and tighten network policy accordingly.

## Migrations

Database schema is applied by **`met-api` when `MET_API__RUN_MIGRATIONS=true`** (see `values.yaml`), using embedded sqlx migrations from the `met-store` crate. That avoids a separate Job that must mount `meticulous-db-app` before the secret exists.

For manual one-off runs (break-glass), build and use the optional image from the Meticulous repo `Dockerfile.sqlx-migrate` with `DATABASE_URL` set to the same `uri` as the CNPG app secret.
