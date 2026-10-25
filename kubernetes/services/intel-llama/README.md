# intel-llama (llama.cpp SYCL on Intel Arc B70 PRO)

OpenAI-compatible inference on `intellectual` serving
[RecursiveSI/flint](https://huggingface.co/RecursiveSI/flint) (39.8B MoE,
~2.5B active per token, native 262144 context) through
[llama.cpp](https://github.com/ggml-org/llama.cpp) with the SYCL/Level-Zero
backend.

This is a **separate deployment** from
[`../intel-vllm`](../intel-vllm) (vLLM + Qwen3.6, currently **parked** at
`replicas: 0`): same GPU, same API key, but its own Argo application,
services, LoadBalancer IP, and hostname. The two deployments compete for the
single `gpu.intel.com/xe` device — only one may run at a time.

## Model & image

| Item | Value |
|------|--------|
| Model | `RecursiveSI/flint` — 39.8B MoE (~2.5B active), 49 layers (2 dense + 47 MoE, 256 routed experts top-6 + shared), 35 sliding-window (513-token) + 14 full-attention layers, Apache-2.0 |
| Artifact | `unsloth/flint-GGUF:UD-Q3_K_XL` (18.5 GB) |
| Context | full native 262144, single slot (`--parallel 1`) |
| KV cache | q8_0 (K and V) |
| Image | `ghcr.io/snailium/llama.cpp-sycl-intel-b70/llama-sycl-b70:server-dev-b11849-c26.35.39758.10-20261024-0252` |
| llama.cpp | b11849 — first build to include Flint support ([PR #30928](https://github.com/ggml-org/llama.cpp/pull/30928), merged 2026-10-21) |
| Served name | `llama` (`--alias`) |

### Why this image

Flint support only landed in llama.cpp master on 2026-10-21, and the only
viable engine on a 32GB Arc card is llama.cpp's SYCL backend (vLLM has no
Flint architecture support; Recursive's official SGLang kit is NVIDIA-only at
>=141GB). The [snailium B70 image](https://github.com/snailium/llama.cpp-sycl-intel-b70)
is the right base because it is built **for this exact GPU**:

- oneAPI 2026 stack with the compute-runtime/IGC/Level-Zero pairing Intel
  documents for Battlemage (26.35.39758.10 / v2.41.5 / 1.32.0), plus the
  "version-triangle" `libigc` fix that the official
  `ghcr.io/ggml-org/llama.cpp:*-intel` images get wrong (they lag on Intel
  deps and skip the `bmg-g31` AOT arch).
- AOT-compiled kernels for the `bmg-g31` device arch — low cold-start JIT
  cost and lower SIGSEGV risk.
- oneDNN/XMX flash-attention build (`GGML_SYCL_DNN=ON`): the XMX SDPA path
  makes deep-context prefill 2–5× faster on B70.
- A maintainer who runs 4-hourly CI (stable) + weekly (dev) on real B70
  hardware and publishes each build as a GitHub issue with pins and digests.

The tag we run is the **dev** build `b11849` (2026-10-24): the first build
whose llama.cpp tree postdates the Flint merge. The `:stable` tag is still
v0.5.0 (2026-09), and the v0.7.0 stable candidate (2026-10-16) predates
Flint — so no Flint-capable stable exists yet. The B70-relevant Intel stack
in that dev build is identical to the maintainer's B70-verified builds (see
[issue #32](https://github.com/snailium/llama.cpp-sycl-intel-b70/issues/32));
only the llama.cpp source moved (b11706 → b11849).

**Upgrade path:** watch the repo's issues for "B70 Stable Image Ready"
announcements once a Flint-capable llama.cpp release ships, then bump
`image.tag` here.

### Runtime env (do not change)

Per the maintainer's golden config:

| Var | Value | Why |
|-----|-------|-----|
| `ONEAPI_DEVICE_SELECTOR` | `level_zero:0` | select the dGPU via Level Zero |
| `SYCL_CACHE_PERSISTENT` | `0` | `=1` SIGSEGVs on Xe2 during first JIT |
| `ZES_ENABLE_SYSMAN` | `1` | Level Zero SYSMAN (device memory queries) |

### Memory budget (262144, single slot, q8_0 KV)

| Item | Size |
|------|------|
| weights (UD-Q3_K_XL) | ~18.5 GB |
| KV, full-attention (14 layers × 262144 tokens, q8_0) | ~3.7 GiB |
| KV, sliding-window (35 layers keep only the last 513 tokens/slot) | ~20 MiB |
| runtime/compute buffers (batch 2048 / ubatch 1024) | a few GiB |
| **total** | **~25–26 GB of 32 GB** |

q8_0 KV is deliberate: community measurement shows q4_0 KV raises KLD by
~67% on code for this model, q8_0 by ~6% — at half the f16 memory.

`--parallel 1` is required: a second full-262k sequence would exceed the
card. More concurrency means shorter contexts (drop `--ctx-size`).

## Endpoints

| Audience | URL |
|----------|-----|
| In-cluster | `http://intel-llama-core.aiml.svc.cluster.local:8080/v1` |
| LAN / laptop / Mac | `http://llama.cloud.danmanners.com/v1` — Cilium BGP LoadBalancer `172.31.0.61` (`service.public`) |
| LAN (IP) | `http://172.31.0.61:8080/v1` — same backend if DNS is unavailable |

### Auth

Same secret as `intel-vllm`: `intel-llm-api-key` (key `api-key`), sealed in
[`../intel-vllm/secret.intel-llm-api-key.yaml`](../intel-vllm/secret.intel-llm-api-key.yaml)
and rotated via its `seal-intel-llm-api-key.sh`. This pod only *references*
that secret — the Argo app for `intel-vllm` keeps owning it.

### Router

[`../llm-router/models/model-llama.yaml`](../llm-router/models/model-llama.yaml)
exposes this backend as `intel-llama` on the shared router
(`llm.cloud.danmanners.com`), so clients keep one endpoint + one key. (The
parked vLLM entry was renamed `intel-qwen36` to free the `intel-llama` name.)

### Smoke test

```bash
export FLINT_KEY="$(kubectl -n aiml get secret intel-llm-api-key \
  -o jsonpath='{.data.api-key}' | base64 -d)"

# /health returns 503 ("Loading model") until load finishes — model load +
# first request takes a few minutes, so poll /v1/models instead:
curl -s http://llama.cloud.danmanners.com/v1/models \
  -H "Authorization: Bearer $FLINT_KEY"

# one token:
curl -s http://llama.cloud.danmanners.com/v1/chat/completions \
  -H "Authorization: Bearer $FLINT_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"llama","messages":[{"role":"user","content":"Say hi"}],"max_tokens":16}'
```

Through the router: use `model: intel-llama`.

## Server flags (`values.yaml`)

| Flag | Value | Notes |
|------|-------|-------|
| `--hf-repo` | `unsloth/flint-GGUF:UD-Q3_K_XL` | downloaded to the PVC (`HF_HOME`) on first boot, reused on restart |
| `--jinja` | | use the GGUF's embedded chat template (unsloth's is llama.cpp-compatible; the original template's `replace("\x00","")` filter needed an adjusted template) |
| `--alias` | `llama` | served model name |
| `--ctx-size` | `262144` | full native context (the point of this deployment) |
| `--n-gpu-layers` | `999` | full GPU offload |
| `--parallel` | `1` | single slot — see memory budget |
| `--batch-size` / `--ubatch-size` | `2048` / `1024` | prefill batching per the community B70 reference (b11849 renamed the old `--batch` / `--ubatch`) |
| `--flash-attn` | `on` | SYCL flash attention; q8_0 KV still reaches the oneDNN/XMX SDPA path via dequantize→f16 (upstream #25874) |
| `--cache-type-k/v` | `q8_0` | see memory budget |
| `--temp` / `--top-p` / `--top-k` | `1` / `0.95` / `20` | Recursive's recommended sampling |

## Expected performance (B70, llama.cpp SYCL)

Reference numbers from the image maintainer's B70 benchmarks (Qwen3.8-27B
Q4_K_M, 128k context, same stack): prefill ~440–530 tok/s, decode ~40–45
tok/s at short context, ~21 tok/s deep-context. Flint's ~2.5B active
parameters are in the same class, so per-token decode should be comparable;
XMX matmul support is still an upstream TODO, so decode stays
memory-latency-bound. The unsloth quant is UD-Q3_K_XL (vs the reference
Q4_K_M), so expect somewhat less headroom. Benchmark the exact model before
treating these as ours.

## Rollback / swap-back

- **Back to vLLM (Qwen3.6):** set `replicas: 0` in *this* values.yaml and
  `replicas: 1` in `../intel-vllm/values.yaml` (the old 72GB Qwen cache is
  still on its PVC). Both apps must never be at `replicas: 1` at once — only
  one pod can hold `gpu.intel.com/xe`. In the router, `intel-llama` points
  here; the vLLM backend is reachable as `intel-qwen36` while parked — to
  flip clients back wholesale, re-point the `intel-llama`
  `apiBase`/`model` at `intel-vllm-core` / `intel-qwen36`.
- **Forward to a new image:** bump `image.tag` here; ArgoCD rolls the
  deployment on the next sync.
- **Remove entirely:** `kubectl -n argocd delete application intel-llama`,
  then drop `kubernetes/applications/intel-llama.yaml` and this directory
  (its PVCs are `retain: true` — delete the PVCs manually if the space
  should be reclaimed).

## Storage

- `cache`: 100 GiB `ceph-block-retain` at `/cache/huggingface` (18.5GB GGUF
  + headroom for other quants, e.g. UD-Q4_K_XL at 25GB).
- `shm`: 16 GiB emptyDir (Memory) for SYCL/USM.
- The parked `intel-vllm` keeps its own 200 GiB PVC (Qwen3.6 cache) until
  the rollback window is over.

## Troubleshooting

- **Crash loop, log reads `error: invalid argument: bash`** (the incident
  this service hit on its first deploy): the image's ENTRYPOINT is the
  `llama-server` binary, so any bare `args` are received by the server *as
  its CLI arguments* — our `bash -c` startup script became
  `llama-server bash -c <script>` and the parser rejected the positional
  `bash` (exit 1, instantly, every restart). Fix, kept in `values.yaml`:
  `command: [/bin/bash]` overrides the entrypoint, and the script execs
  `/app/llama-server` by absolute path — the binary is **not** on the
  image's PATH. (A quick test that reveals the entrypoint: run the image
  with `args: [echo, hello, world]`; you get
  `error: invalid argument: echo`.)
- **`error: invalid argument: --batch` / `--ubatch`**: b11849 renamed the
  flags to `--batch-size` / `--ubatch-size`; the startup script uses the new
  names.
- **`/health` returns 503**: expected while the 18.5GB GGUF downloads
  (first boot) and the model loads; poll `/v1/models` instead (see
  [Smoke test](#smoke-test)).
