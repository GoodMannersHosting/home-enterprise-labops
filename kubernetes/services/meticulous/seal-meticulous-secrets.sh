#!/usr/bin/env bash
# Generate Bitnami SealedSecret manifests for Meticulous (see SECRETS.md).
# Intended to run **locally** (or a secure admin host), not as a cluster Job. In-cluster NATS JWT
# checks run in **initContainers** on met-api / met-controller (see `values.yaml`).
#
# Prerequisites: kubectl configured for the target cluster, kubeseal installed,
# Sealed Secrets controller reachable (or use SEALED_SECRETS_CERT_FILE — see seal-lib.sh / SECRETS.md).
#
# Usage:
#   ./seal-meticulous-secrets.sh
#
# Outputs (in this directory):
#   secret.meticulous-db-owner.yaml
#   secret.meticulous-runtime.yaml
#
# NATS: ./bootstrap-meticulous-nats-jwt.sh --write-sealed (see SECRETS.md).
#
# Add resources to kustomization.yaml BEFORE cnpg-cluster.yaml, in sync-wave order:
#   secret.meticulous-nats.yaml (-4) → db-owner (-3) → runtime (-2) → CNPG cluster → ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
# shellcheck source=seal-lib.sh
source "${SCRIPT_DIR}/seal-lib.sh"

NS="${SEALED_SECRET_NAMESPACE:-meticulous}"

meticulous_seal_kubeseal_args_fill

# If the CNPG cluster already exists, set METICULOUS_DB_OWNER_PASSWORD to the current owner password so you do not
# rotate the DB user while re-sealing (e.g. when adding the `uri` key for the first time).
db_pass="${METICULOUS_DB_OWNER_PASSWORD:-$(openssl rand -base64 32)}"
# CNPG does not create `<cluster>-app` when `bootstrap.initdb.secret.name` is set; apps read `uri` from this secret.
db_uri="$(
	DB_PASS="${db_pass}" python3 -c \
		'import os, urllib.parse; p=os.environ["DB_PASS"]; q=urllib.parse.quote(p, safe=""); print(f"postgres://meticulous:{q}@meticulous-db-rw:5432/meticulous")'
)"
jwt_api="$(openssl rand -base64 48)"
jwt_ctrl="$(openssl rand -base64 40)"
# Hex keys are easy to paste into Seaweed / IAM configs if you enable auth later.
s3_access="$(openssl rand -hex 16)"
s3_secret="$(openssl rand -base64 40)"

kubectl create secret generic meticulous-db-owner \
	--namespace "${NS}" \
	--from-literal=username=meticulous \
	--from-literal=password="${db_pass}" \
	--from-literal=uri="${db_uri}" \
	--dry-run=client -o yaml | meticulous_seal_annotate_wave -3 | kubeseal "${METICULOUS_SEAL_KUBESEAL_ARGS[@]}" \
	>secret.meticulous-db-owner.yaml

runtime_from=(
	--from-literal=jwt_api_secret="${jwt_api}"
	--from-literal=jwt_controller_secret="${jwt_ctrl}"
	--from-literal=s3_access_key="${s3_access}"
	--from-literal=s3_secret_key="${s3_secret}"
)
if [[ -n "${INCLUDE_BUILTIN_MASTER:-}" ]]; then
	builtin_key="$(openssl rand -base64 32)"
	runtime_from+=(--from-literal=builtin_secrets_master_key="${builtin_key}")
fi

kubectl create secret generic meticulous-runtime \
	--namespace "${NS}" \
	"${runtime_from[@]}" \
	--dry-run=client -o yaml | meticulous_seal_annotate_wave -2 | kubeseal "${METICULOUS_SEAL_KUBESEAL_ARGS[@]}" \
	>secret.meticulous-runtime.yaml

echo "Wrote:"
echo "  ${SCRIPT_DIR}/secret.meticulous-db-owner.yaml"
echo "  ${SCRIPT_DIR}/secret.meticulous-runtime.yaml"
echo ""
echo "Values used for this run are ONLY in the SealedSecret ciphertext above."
echo "If you need to record passwords for break-glass DB access, fetch them from"
echo "the generated Kubernetes Secret after apply, or re-run with a known DB password"
echo "by editing this script temporarily (not recommended)."
echo ""
echo "Next: ensure kustomization.yaml lists db-owner and runtime before cnpg-cluster.yaml."
echo "NATS: run ./bootstrap-meticulous-nats-jwt.sh --write-sealed (see SECRETS.md), then commit."
echo "Then commit the sealed YAML files. Do not commit cleartext database/runtime secrets."
