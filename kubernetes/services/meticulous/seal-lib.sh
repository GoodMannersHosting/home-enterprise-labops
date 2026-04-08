#!/usr/bin/env bash
# Shared kubeseal helpers for Meticulous (source from other scripts; do not run directly).
# shellcheck shell=bash
#
# Env (optional overrides):
#   SEALED_SECRETS_CERT_FILE       If set, kubeseal uses --cert (offline / air-gapped).
#   SEALED_SECRETS_CONTROLLER_NAME  Default: sealed-secrets
#   SEALED_SECRETS_CONTROLLER_NAMESPACE  Default: sealed-secrets

meticulous_seal_annotate_wave() {
	local wave="$1"
	kubectl annotate -f - --local "argocd.argoproj.io/sync-wave=${wave}" -o yaml
}

meticulous_seal_kubeseal_args_fill() {
	METICULOUS_SEAL_KUBESEAL_ARGS=()
	if [[ -n "${SEALED_SECRETS_CERT_FILE:-}" ]]; then
		METICULOUS_SEAL_KUBESEAL_ARGS=(--cert "${SEALED_SECRETS_CERT_FILE}" --format yaml)
	else
		METICULOUS_SEAL_KUBESEAL_ARGS=(
			--format yaml
			--controller-name "${SEALED_SECRETS_CONTROLLER_NAME:-sealed-secrets}"
			--controller-namespace "${SEALED_SECRETS_CONTROLLER_NAMESPACE:-sealed-secrets}"
		)
	fi
}
