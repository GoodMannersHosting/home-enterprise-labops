# intel-vllm (llama-server on Intel Arc B70)

OpenAI-compatible **llama-server** on `intellectual` using `gpu.intel.com/xe`.

## Why “intel-vllm”?

The Argo app / Helm release is named **`intel-vllm`** from the homelab plan (directory kept for a possible later **Intel vLLM XPU** deployment). **This workload is llama.cpp**, not vLLM. Public DNS is **`intel-llm.cloud.danmanners.com`** (no “vllm” in the hostname).

## Model

| Item | Value |
|------|--------|
| Hugging Face repo | `HauhauCS/Gemma4-26B-A4B-QAT-Uncensored-HauhauCS-Balanced-MTP` |
| Main GGUF | `Gemma4-26B-A4B-QAT-Uncensored-HauhauCS-Balanced-Q4_K_M.gguf` (26B-A4B MoE, 128 experts / 8 active, QAT Q4_K_M — 16.8 GB) |
| Vision | `mmproj-Gemma4-26B-A4B-QAT-Uncensored-HauhauCS-Balanced-BF16.gguf` (1.2 GB, image input) |
| Speculative draft | `mtp-gemma-4-26B-A4B-it.gguf` (252 MB, MTP draft head, ~35% faster generation at identical output quality) |
| Context | `204800` (`--ctx-size`), KV cache `q5_0` k/v, `--fit on --fit-ctx 32768` as a safety net if the full context doesn't fit |
| Image | `ghcr.io/ggml-org/llama.cpp:server-vulkan` (Vulkan; SYCL untested for this model — see §4b) |

Weights are pulled by an **initContainer** (`curlimages/curl`) directly from the HF `resolve` URLs into the `cache` PVC at `/root/.cache/huggingface/hauhaucs-gemma4/`, skipping re-download if the file is already present. We do **not** use `--hf-repo`/`--hf-file` here because there's no reliable flag to select the draft-model file out of a multi-GGUF repo — direct URL downloads to fixed paths are deterministic instead.

### Why this model

Gemma4-26B-A4B is a standard MoE transformer (128 experts, 8 active per token) — **not** a hybrid SSM/GDN architecture, so it doesn't hit the SYCL warmup crash documented in §4b for Qwen3.6. HauhauCS's "Balanced" uncensoring build ships an MTP speculative-decoding draft head tuned specifically for this checkpoint (~35% faster generation, verified output — not a quality tradeoff). Vision input works via the bundled mmproj.

### VRAM tradeoff: mmproj offload disabled

With `--ctx-size 204800`, KV cache at `q5_0` plus ~18 GB of model/mmproj/draft weights leaves limited headroom on a 32 GB card. We pass `--no-mmproj-offload` to keep the vision projector on CPU, reserving VRAM for the text context. Image-input requests will be slower than a fully GPU-offloaded mmproj, but this deployment is tuned for large-context text/agentic workflows first.

## Endpoints

| Audience | URL | Notes |
|----------|-----|--------|
| **In-cluster** | `http://intel-vllm-core.aiml.svc.cluster.local:8080/v1` | ClusterIP (`service.core`); use from pods in `aiml`, future n8n, etc. |
| **LAN / laptop / Mac** | `http://intel-llm.cloud.danmanners.com/v1` | Cilium BGP LoadBalancer `172.31.0.35` (`service.public`) |
| **LAN (IP)** | `http://172.31.0.35:8080/v1` | Same backend if DNS is unavailable |

Do **not** use `*.svc.cluster.local` from laptops or the Mac Mini.

### Auth

`llama-server` reads **`LLAMA_API_KEY`** from Secret `intel-llm-api-key` (key `api-key`). Clients send:

```http
Authorization: Bearer <api-key>
```

To rotate the key:

```bash
INTEL_LLM_API_KEY="$(openssl rand -hex 32)" ./seal-intel-llm-api-key.sh
# commit secret.intel-llm-api-key.yaml, sync Argo, restart the deployment
```

## Smoke tests

```bash
# In-cluster (from any pod with curl)
curl -s http://intel-vllm-core.aiml.svc.cluster.local:8080/v1/models

# LAN / public
curl -s http://intel-llm.cloud.danmanners.com/v1/models \
  -H "Authorization: Bearer $INTEL_LLM_API_KEY"
```

First sync can take a long time while the three GGUFs download to Ceph (~18.3 GB total).

## Argo CD

Application: [`kubernetes/applications/intel-vllm.yaml`](../../applications/intel-vllm.yaml) (namespace `aiml`). `automated.selfHeal: true` — pushes to `main` roll out automatically, no manual sync needed.

## Performance

If generation feels slow, work through these in order.

### 1. Confirm the GPU is actually doing inference

From the pod logs after a request, you should see Vulkan offload (not CPU-only):

```bash
kubectl logs -n aiml deploy/intel-vllm -c core --tail=100
# Look for vulkan / GPU layer offload lines, not "BLAS" CPU fallback for most layers.
```

If layers run on CPU, fix CDI/`/dev/dri` (see Troubleshooting) before tuning flags.

### 2. Context length (largest lever in this deployment)

KV cache scales linearly with `--ctx-size` × `--parallel`. Current config runs `--ctx-size 204800` with `--parallel 1` at `q5_0` k/v — chosen to match the KV precision already proven stable at high context on this exact 32 GB card (see the sibling Qwen deployment history in git blame). `--fit on --fit-ctx 32768` means the server will automatically negotiate down to a smaller context instead of crash-looping if 204800 doesn't fit given current VRAM pressure — check startup logs for the negotiated value.

### 3. Parallel slots

`--parallel 1` — single-user chat. Raising this multiplies KV cache usage by the same factor; do not raise without also lowering `--ctx-size`.

### 4. Quantization (weights)

Q4_K_M is the only quant HauhauCS ships for this checkpoint — Gemma 4 is QAT'd (quantization-aware trained) for ~4-bit, so higher-precision quants add size with no real quality gain per the model card.

### 4b. SYCL vs Vulkan (backend A/B)

Current image: **`server-vulkan`**. This model is **not** the hybrid SSM/GDN architecture that causes the known SYCL warmup crash ([ggml-org/llama.cpp#21474](https://github.com/ggml-org/llama.cpp/issues/21474) — affects Qwen3.6 and similar hybrid archs), so SYCL is plausible here, but it has **not been tested** on this exact model/build. Treat any SYCL attempt as a separate experiment (different image tag + `ONEAPI_DEVICE_SELECTOR`/`GGML_SYCL_ENABLE_LEVEL_ZERO` env, ideally on a scratch Deployment) rather than flipping this production one live.

### 5. llama.cpp backends (already in values)

- `--flash-attn on`
- `--cache-type-k q5_0 --cache-type-v q5_0`
- **Vulkan only:** `GGML_VK_MMVQ_SHMEM_STAGING=1`
- Speculative decoding via MTP draft head: `--spec-draft-model ... --spec-type draft-mtp`

Restart the pod after changing the image tag or env so the binary and shaders refresh.

### 6. Host stack (Talos + Arc)

The container uses the node's **Mesa / Vulkan** stack via the Intel GPU plugin. On Arc **Battlemage (B70)**, community benchmarks show a large gap between older Mesa (25.x) and **Mesa 26+** (BF16 / integer dot / coopmat paths). If flags and quant changes barely help, the bottleneck may be **node drivers**, not Kubernetes — check Intel/Talos extension versions on `intellectual` and Arc-focused tuning guides.

### 7. When llama.cpp is not enough: Intel vLLM (phase 2)

For **many concurrent** OpenAI clients or higher batch throughput, `llama-server` is the wrong tool. Intel's **`intel/vllm:*-xpu`** images target Arc B-Series with continuous batching (separate Deployment, same `gpu.intel.com/xe`).

### 8. Open WebUI-specific

- One connection to `intel-vllm-core`; avoid loading the same model via Ollama simultaneously on the 5090 for the same chat unless intentional.
- Disable unnecessarily large **context window** / **full chat history** features for the Intel model unless you actually want to exercise the 204800 context.
- RAG embeddings are separate; slow **chat** is almost always inference flags/ctx/GPU, not Postgres.

### Quick benchmark (from LAN)

```bash
time curl -s http://intel-llm.cloud.danmanners.com/v1/chat/completions \
  -H "Authorization: Bearer $INTEL_LLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma4-26b-a4b","messages":[{"role":"user","content":"Write a Python function that reverses a linked list."}],"max_tokens":256,"stream":false}'
```

Compare before/after each change; aim for stable tok/s in logs or wall time for 128 tokens.

## Troubleshooting

- **Scheduling:** Pod must land on node `intellectual` (`kubernetes.io/hostname=intellectual`, not the Talos FQDN) with `gpu.intel.com/xe` allocatable.
- **CDI / GPU:** Values start without `privileged` or host `/dev/dri` mounts; if the pod fails to use the GPU, add privileged + `/dev/dri` hostPath per cluster notes.
- **Init container stuck downloading:** `kubectl logs -n aiml deploy/intel-vllm -c download-model` — HF `resolve` URLs can be slow on first pull for the 16.8 GB main GGUF; the curl retries automatically on transient failures but won't retry a truncated/interrupted file across restarts on its own (the `.part` suffix should prevent a truncated file being treated as complete, but verify size in the PVC if you suspect corruption).
- **SYCL warmup crash (silent exit after `warming up the model with an empty run`):** Upstream regression ([ggml-org/llama.cpp#21474](https://github.com/ggml-org/llama.cpp/issues/21474)) in `server-intel:latest`, confirmed for hybrid SSM/GDN archs (Qwen3.6). Not confirmed either way for Gemma4 — test on a scratch deployment first.
- **`llama-server: not found`:** The server image sets `ENTRYPOINT` to `/app/llama-server`. Do not wrap with `/bin/sh` unless you call `/app/llama-server` explicitly.
- **`libllama-common.so.0: cannot open shared object file`** (Vulkan image): Vulkan `server` ships `.so` files in `/app`; set `LD_LIBRARY_PATH=/app` (the Dockerfile `WORKDIR` alone is not enough for the dynamic linker) — only needed if you see this error; not required with the current image build.
