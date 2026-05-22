#!/usr/bin/env bash
# Regenerate kubernetes/services/intel-vllm/secret.intel-llm-api-key.yaml (see README).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${ROOT}/secret.intel-llm-api-key.yaml"

if [[ -z "${INTEL_LLM_API_KEY:-}" ]]; then
  INTEL_LLM_API_KEY="$(openssl rand -hex 32)"
  echo "Generated INTEL_LLM_API_KEY (store in your password manager): ${INTEL_LLM_API_KEY}" >&2
fi

kubectl create secret generic intel-llm-api-key \
  --namespace=aiml \
  --from-literal=api-key="${INTEL_LLM_API_KEY}" \
  --dry-run=client -o yaml \
  | kubeseal \
    --format yaml \
    --controller-name "${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets}" \
    --controller-namespace "${SEALED_SECRETS_CONTROLLER_NAMESPACE:-sealed-secrets}" \
  > "${OUT}"

echo "Wrote ${OUT}"
