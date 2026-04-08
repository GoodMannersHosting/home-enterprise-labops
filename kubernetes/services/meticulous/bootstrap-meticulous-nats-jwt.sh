#!/usr/bin/env bash
# LOCAL / ONE-TIME: generate NATS operator JWT material for this repo's Kustomize layout (or kubeseal).
#
# Run from a trusted machine with Docker or `nsc` — not from a cluster Pod. Met-api and
# met-controller use initContainers (`verify-nats-jwt`, `natsio/nats-box`) to wait for NATS and
# confirm JWT creds before app containers start.
#
# Writes operator JWT, nats-server.conf (memory resolver), controller.creds, api.creds, and
# account signing material for `MET_NATS_ACCOUNT_SIGNING_SEED` / `MET_NATS_ACCOUNT_ISSUER_PUBKEY`.
#
# Usage:
#   ./bootstrap-meticulous-nats-jwt.sh --write-kustomize [DIR]   # cleartext under nats/ (optional)
#   ./bootstrap-meticulous-nats-jwt.sh --write-sealed [DIR]      # secret.meticulous-nats.yaml (needs kubeseal)
#   ./bootstrap-meticulous-nats-jwt.sh --write-kustomize --write-sealed
#   ./bootstrap-meticulous-nats-jwt.sh | kubeseal ...             # legacy: combined Secret YAML on stdout
#   NATS_JWT_WORKDIR=./staging ./bootstrap-meticulous-nats-jwt.sh --write-sealed .
#
# Requires: Docker + natsio/nats-box, OR nsc on PATH; python3; kubectl + kubeseal for --write-sealed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=seal-lib.sh
source "${SCRIPT_DIR}/seal-lib.sh"

WRITE_KUSTOMIZE_TARGET=""
WRITE_SEALED_TARGET=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--write-kustomize)
		if [[ -n "${2:-}" && "${2}" != -* ]]; then
			WRITE_KUSTOMIZE_TARGET="$(cd "$2" && pwd)"
			shift 2
		else
			WRITE_KUSTOMIZE_TARGET="${SCRIPT_DIR}"
			shift
		fi
		;;
	--write-sealed)
		if [[ -n "${2:-}" && "${2}" != -* ]]; then
			WRITE_SEALED_TARGET="$(cd "$2" && pwd)"
			shift 2
		else
			WRITE_SEALED_TARGET="${SCRIPT_DIR}"
			shift
		fi
		;;
	*)
		echo "Unknown argument: $1 (expected --write-kustomize [DIR] and/or --write-sealed [DIR])" >&2
		exit 2
		;;
	esac
done

if [[ -n "${NATS_JWT_WORKDIR:-}" ]]; then
	mkdir -p "${NATS_JWT_WORKDIR}"
	WORKDIR="$(cd "${NATS_JWT_WORKDIR}" && pwd)"
	RM_WORKDIR=0
else
	WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/meticulous-nats-XXXXXX")"
	RM_WORKDIR=1
fi
NAT_BOX_IMAGE="${NAT_BOX_IMAGE:-natsio/nats-box:latest}"
NS="${SEALED_SECRET_NAMESPACE:-meticulous}"

cleanup() {
	if [[ "${RM_WORKDIR}" -eq 1 ]]; then
		rm -rf "${WORKDIR}"
	fi
}
trap cleanup EXIT

INNER="${WORKDIR}/_nsc_inner.sh"
cat >"${INNER}" <<'INNEREOF'
set -euo pipefail
ROOT="${1:?WORKDIR mount root (e.g. /work)}"
export NCS_HOME="${ROOT}/nsc.store"
mkdir -p "${NCS_HOME}"

nsc init -n MET --dir "${NCS_HOME}"
# nsc 2.8+ creates SYS during init; older nsc only creates the operator.
if ! nsc add account -n SYS; then
	nsc describe account SYS >/dev/null 2>&1 || {
		echo "nsc: could not add SYS account and it is not present after init" >&2
		exit 1
	}
fi
nsc add account -n APP
# Full account traffic (JetStream, met.*); tighten in production with scoped allow-lists.
nsc add user -n controller -a APP --allow-pubsub ">"
nsc add user -n api -a APP --allow-pubsub ">"

nsc describe operator -o "${ROOT}/operator.jwt" --raw
nsc describe account SYS -o "${ROOT}/sys-account.jwt" --raw
nsc describe account APP -o "${ROOT}/app-account.jwt" --raw

nsc generate creds -a APP -n controller -o "${ROOT}/controller.creds"
nsc generate creds -a APP -n api -o "${ROOT}/api.creds"

mkdir -p "${ROOT}/export"
nsc export keys --account APP --accounts --dir "${ROOT}/export" --force
INNEREOF
chmod +x "${INNER}"

if command -v nsc >/dev/null 2>&1; then
	bash "${INNER}" "${WORKDIR}"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	docker run --rm \
		-v "${WORKDIR}:/work" \
		-w /work \
		"${NAT_BOX_IMAGE}" \
		sh /work/_nsc_inner.sh /work
else
	echo "Need nsc on PATH, or Docker with permission to run ${NAT_BOX_IMAGE}" >&2
	exit 1
fi

python3 - "${WORKDIR}" <<'PY'
import json, base64, pathlib, sys

def b64url_decode(data: str) -> bytes:
    pad = (4 - len(data) % 4) % 4
    return base64.urlsafe_b64decode((data + "=" * pad).encode())

def jwt_sub(jwt: str) -> str:
    payload = json.loads(b64url_decode(jwt.split(".")[1]))
    return payload["sub"]

def nsc_compact_jwt(text: str, label: str) -> str:
    """nsc 2.x `describe ... --raw` writes PEM-wrapped JWTs; nats-server expects one-line JWT."""
    t = text.strip()
    if t.startswith("eyJ") and t.count(".") == 2:
        return t
    for line in t.splitlines():
        s = line.strip()
        if s.startswith("eyJ") and s.count(".") == 2:
            return s
    print(f"could not extract compact JWT from {label}", file=sys.stderr)
    sys.exit(1)

root = pathlib.Path(sys.argv[1])
for name in ("operator.jwt", "sys-account.jwt", "app-account.jwt"):
    path = root / name
    compact = nsc_compact_jwt(path.read_text(encoding="utf-8"), name)
    path.write_text(compact + "\n", encoding="ascii")

app_jwt = (root / "app-account.jwt").read_text().strip()
sys_jwt = (root / "sys-account.jwt").read_text().strip()
app_sub = jwt_sub(app_jwt)
sys_sub = jwt_sub(sys_jwt)

export = root / "export"
matches = list(export.rglob(f"{app_sub}.nk"))
if not matches:
    matches = list(export.rglob("*.nk"))
if not matches:
    print("nsc export keys did not produce .nk files under export/", file=sys.stderr)
    sys.exit(1)
raw = matches[0].read_text(encoding="utf-8", errors="replace").strip()
seed = raw.split()[0] if raw.split() else raw
(root / "account_signing_seed.txt").write_text(seed, encoding="utf-8")
(root / "account_issuer_pubkey.txt").write_text(app_sub, encoding="ascii")

operator_name = "operator.jwt"
# MEMORY resolver + resolver_preload (see NATS mem resolver docs). Quoted JWT strings
# confuse the server; match `nsc generate config --mem-resolver` (bare NKey: bare JWT).
lines = [
    "port: 4222",
    "http: 8222",
    "server_name: meticulous-nats",
    "",
    "jetstream: {",
    "  store_dir: /data",
    "}",
    "",
    f"operator: /etc/nats/jwt/{operator_name}",
    "",
    f"system_account: {sys_sub}",
    "",
    "resolver: MEMORY",
    "",
    "resolver_preload: {",
    f"  {sys_sub}: {sys_jwt}",
    f"  {app_sub}: {app_jwt}",
    "}",
    "",
]
(root / "nats-server.conf").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

ACCOUNT_SEED="$(tr -d '\n' <"${WORKDIR}/account_signing_seed.txt")"
ISSUER_PUB="$(tr -d '\n' <"${WORKDIR}/account_issuer_pubkey.txt")"

meticulous_nats_secret_kubectl_cmd() {
	kubectl create secret generic meticulous-nats \
		--namespace "${NS}" \
		--from-file=operator.jwt="${WORKDIR}/operator.jwt" \
		--from-file=sys-account.jwt="${WORKDIR}/sys-account.jwt" \
		--from-file=app-account.jwt="${WORKDIR}/app-account.jwt" \
		--from-file=nats-server.conf="${WORKDIR}/nats-server.conf" \
		--from-file=controller.creds="${WORKDIR}/controller.creds" \
		--from-file=api.creds="${WORKDIR}/api.creds" \
		--from-literal=account_signing_seed="${ACCOUNT_SEED}" \
		--from-literal=account_issuer_pubkey="${ISSUER_PUB}" \
		--dry-run=client -o yaml
}

if [[ -n "${WRITE_KUSTOMIZE_TARGET}" ]]; then
	NATS_DIR="${WRITE_KUSTOMIZE_TARGET}/nats"
	mkdir -p "${NATS_DIR}/keys"
	cp -f "${WORKDIR}/nats-server.conf" "${NATS_DIR}/nats-server.conf"
	cp -f "${WORKDIR}/operator.jwt" "${NATS_DIR}/operator.jwt"
	cp -f "${WORKDIR}/api.creds" "${NATS_DIR}/keys/api.creds"
	cp -f "${WORKDIR}/controller.creds" "${NATS_DIR}/keys/controller.creds"
	cp -f "${WORKDIR}/account_signing_seed.txt" "${NATS_DIR}/keys/account_signing_seed"
	cp -f "${WORKDIR}/account_issuer_pubkey.txt" "${NATS_DIR}/keys/account_issuer_pubkey"
	echo "Wrote Kustomize file inputs under ${NATS_DIR}/"
fi

if [[ -n "${WRITE_SEALED_TARGET}" ]]; then
	command -v kubeseal >/dev/null 2>&1 || {
		echo "kubeseal not on PATH (required for --write-sealed)" >&2
		exit 1
	}
	meticulous_seal_kubeseal_args_fill
	out="${WRITE_SEALED_TARGET}/secret.meticulous-nats.yaml"
	meticulous_nats_secret_kubectl_cmd | meticulous_seal_annotate_wave -4 | kubeseal "${METICULOUS_SEAL_KUBESEAL_ARGS[@]}" >"${out}"
	echo "Wrote sealed manifest ${out}"
fi

if [[ -n "${WRITE_KUSTOMIZE_TARGET}" || -n "${WRITE_SEALED_TARGET}" ]]; then
	if [[ -n "${WRITE_KUSTOMIZE_TARGET}" ]]; then
		echo "Cleartext nats/: optional local copies — for GitOps use --write-sealed and commit secret.meticulous-nats.yaml (see SECRETS.md)."
	fi
	if [[ -n "${WRITE_SEALED_TARGET}" ]]; then
		echo "Commit ${WRITE_SEALED_TARGET}/secret.meticulous-nats.yaml (already listed in kustomization.yaml)."
	fi
	exit 0
fi

meticulous_nats_secret_kubectl_cmd | meticulous_seal_annotate_wave -4
