#!/usr/bin/env bash
# Regenerate kubernetes/services/llm-router/secret.litellm-master-key.yaml (see README).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${ROOT}/secret.litellm-master-key.yaml"

if [[ -z "${LITELLM_MASTER_KEY:-}" ]]; then
  LITELLM_MASTER_KEY="sk-$(openssl rand -hex 32)"
  echo "Generated LITELLM_MASTER_KEY (store in your password manager): ${LITELLM_MASTER_KEY}" >&2
fi

kubectl create secret generic litellm-master-key \
  --namespace=aiml \
  --from-literal=master-key="${LITELLM_MASTER_KEY}" \
  --dry-run=client -o yaml \
  | kubeseal \
    --format yaml \
    --controller-name "${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets}" \
    --controller-namespace "${SEALED_SECRETS_CONTROLLER_NAMESPACE:-sealed-secrets}" \
  > "${OUT}"

echo "Wrote ${OUT}"
