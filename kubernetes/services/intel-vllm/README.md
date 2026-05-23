# intel-vllm (llama-server on Intel Arc B70)

OpenAI-compatible **llama-server** on `intellectual` using `gpu.intel.com/xe`.

## Why “intel-vllm”?

The Argo app / Helm release is named **`intel-vllm`** from the homelab plan (directory kept for a possible later **Intel vLLM XPU** deployment). **This workload is llama.cpp**, not vLLM. Public DNS is **`intel-llm.cloud.danmanners.com`** (no “vllm” in the hostname).

## Model

| Item | Value |
|------|--------|
| Hugging Face repo | `unsloth/Qwen3.6-27B-GGUF` |
| GGUF file | `Qwen3.6-27B-Q6_K.gguf` (text-only; `--no-mmproj`; min weight quant Q6_K) |
| Context | `8192` default (was `32768` — that reserved enormous KV and slowed generation) |
| Image | `ghcr.io/ggml-org/llama.cpp:server-intel` (SYCL / Level Zero) |
| Tunables | Flash attention on, KV cache `q8_0`, SYCL env vars in values |

Weights are pulled on first start into the `cache` PVC (`HF_HOME=/cache/huggingface`).

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

First sync can take a long time while the GGUF downloads to Ceph.

## Argo CD

Application: [`kubernetes/applications/intel-vllm.yaml`](../../applications/intel-vllm.yaml) (namespace `aiml`).

## Performance

### “8192 MB” in logs is not your GPU cap

Two different `8192` values show up in logs:

| Log text | Meaning |
|----------|---------|
| `n_ctx = 8192` / `8192 tokens` | **Context length** (`--ctx-size`) — tokens per slot |
| `prompt cache is enabled, size limit: 8192 MiB` | **Host RAM** for llama-server’s prompt cache (`--cache-ram`, default 8192 MiB). Not VRAM, not the Kubernetes `28Gi` limit |

We set `--cache-ram 0` to disable that cache. Kubernetes still gives the pod **28Gi**; the GPU reports **~32GiB** (`Vulkan0: Intel BMG G31`).

### Multimodal (mmproj) was likely your biggest bug

If logs show `loaded multimodal model, ... mmproj-BF16.gguf`, the server auto-pulled the **vision projector** (~1.2GiB+) even for text-only chat. That steals VRAM and slows token generation. Use **`--no-mmproj`** (now in values). You must **restart** after sync; confirm logs say **no** mmproj load.

If generation feels slow, work through these in order.

### 1. Confirm the GPU is actually doing inference

From the pod logs after a request, you should see Vulkan offload (not CPU-only). On the node:

```bash
kubectl logs -n aiml deploy/intel-vllm-main -c core --tail=100
# Look for vulkan / GPU layer offload lines, not "BLAS" CPU fallback for most layers.
```

If layers run on CPU, fix CDI/`/dev/dri` (see Troubleshooting) before tuning flags.

### 2. Context length (largest lever in this deployment)

`--ctx-size 32768` on a **27B** model pre-allocates a very large KV cache on **32GB** VRAM and destroys token/s even when chats are short.

Current default: **`8192`**. In **Open WebUI**, cap the model/context (Advanced parameters) to match — do not send 32k if the server is at 8k.

Need long documents? Raise `--ctx-size` in [`values.yaml`](values.yaml) gradually (e.g. 16384) and watch VRAM; prefer `--cache-type-k q4_0 --cache-type-v q4_0` for extreme context.

### 3. Parallel slots

Default `n_parallel=4` creates **four** slots each with full `n_ctx` KV — heavy on 32GB VRAM. Values use `--parallel 1` for Open WebUI.

### 4. Quantization (weights)

**Policy:** stay at **Q6_K** or higher for weight files (no Q4_K_M / Q4_0 class for now). KV cache types (`q8_0`) are separate and may still be tuned.

| GGUF | Tradeoff |
|------|----------|
| `Qwen3.6-27B-Q6_K.gguf` (default) | Quality floor; ~22.5GB weights |
| `Qwen3.6-27B-Q8_0.gguf` | Heavier, slightly higher quality |

When switching `--hf-file`, remove the old snapshot under the cache PVC or use a fresh path so the pod does not keep loading the previous quant from disk.

### 4b. SYCL vs Vulkan (backend A/B)

Current image: **`server-intel`** (SYCL). Previous: **`server-vulkan`**.

After sync, confirm startup logs show **SYCL0** (not only `Vulkan0`), e.g. layers offloaded `on SYCL0`.

| If SYCL… | Action |
|----------|--------|
| **Works + higher `tg`** | Keep `server-intel` |
| **Crashes on warmup** | Pin `server-intel-b8477` or revert `tag: server-vulkan` and restore `GGML_VK_MMVQ_SHMEM_STAGING=1` |
| **Slower than Vulkan** | Revert to Vulkan; SYCL wins on some B70 dense models, not all |

SYCL env in values: `ONEAPI_DEVICE_SELECTOR=level_zero:0`, `GGML_SYCL_DEVICE=0`, `ZES_ENABLE_SYSMAN=1`, `SYCL_CACHE_PERSISTENT=1`.

### 5. llama.cpp backends (already in values)

- `--flash-attn on`
- `--cache-type-k q8_0 --cache-type-v q8_0`
- **Vulkan only:** `GGML_VK_MMVQ_SHMEM_STAGING=1` when using `server-vulkan`

Restart the pod after changing the image tag or env so the binary and shaders refresh.

### 6. Host stack (Talos + Arc)

The container uses the node’s **Mesa / Vulkan** stack via the Intel GPU plugin. On Arc **Battlemage (B70)**, community benchmarks show a large gap between older Mesa (25.x) and **Mesa 26+** (BF16 / integer dot / coopmat paths). If flags and quant changes barely help, the bottleneck may be **node drivers**, not Kubernetes — check Intel/Talos extension versions on `intellectual` and Arc-focused tuning guides (e.g. Mesa 26+, recent `llama.cpp`).

### 7. When llama.cpp is not enough: Intel vLLM (phase 2)

For **many concurrent** OpenAI clients or higher batch throughput, `llama-server` is the wrong tool. Intel’s **`intel/vllm:*-xpu`** images target Arc B-Series with continuous batching (separate Deployment, same `gpu.intel.com/xe`). Qwen3.6 on vLLM XPU may lag llama.cpp until validated — check [intel/ai-containers](https://github.com/intel/ai-containers) release notes.

### 8. Open WebUI-specific

- One connection to `intel-vllm-core`; avoid loading the same model via Ollama simultaneously on the 5090 for the same chat unless intentional.
- Disable unnecessarily large **context window** / **full chat history** features for the Intel model.
- RAG embeddings are separate; slow **chat** is almost always inference flags/ctx/GPU, not Postgres.

### You're at ~14 t/s — what about ~40 t/s?

**Token generation (`tg` in logs)** and **chat responsiveness** are different problems.

| Metric | Your logs | Notes |
|--------|-----------|--------|
| **TG (decode)** | ~13.5 t/s | Already ~2.4× up from ~5.6 t/s after `--no-mmproj` + Q4_K_M |
| **Prefill** | ~396 t/s | Good; not the bottleneck for “feels slow” |
| **Multi-turn** | `forcing full prompt re-processing` | Qwen3.6 **hybrid** architecture + broken context checkpoints in current `server-vulkan` |

**Realistic TG targets on Arc B70 + Vulkan for Qwen3.6-27B Q4_K_M:** roughly **15–25 t/s** on a well-tuned stack. **~40 t/s** on the same 27B dense model usually needs one or more of:

1. **Smaller model on the same GPU** — e.g. Qwen3.5-9B / 14B MLX-class GGUF often lands **30–50+ t/s** on Arc.
2. **More aggressive quant** — `Q4_K_S`, `IQ4_XS`, or MXFP4 where supported (quality tradeoff).
3. **`server-intel` (SYCL)** — some B70 setups beat Vulkan on dense Q4; worth an A/B Deployment (separate release).
4. **Host Mesa 26+** on `intellectual` — Vulkan BF16/integer-dot paths; Talos extension age matters.
5. **Newer llama.cpp** — upstream fixes for hybrid checkpoint restore ([PR #22929](https://github.com/ggml-org/llama.cpp/pull/22929) area) improve **turn-to-turn** latency, not always peak TG.
6. **Intel vLLM XPU** — throughput-oriented; different ops profile than llama-server.

**Values just added for another TG bump:**

- `--ctx-checkpoints 0` — stops mid-generation “checkpoint 1 of 32” work (~150 MiB each in your logs).
- `--swa-full` — hybrid-model KV behavior per [llama.cpp #13194](https://github.com/ggml-org/llama.cpp/pull/13194#issuecomment-2868343055).
- KV cache `q4_0` (was `q8_0`).
- `LLAMA_ARG_THREADS=16` (logs showed `n_threads = 8` on a 28-thread host).

**Open WebUI:** shorten chat history / context limit so turns do not re-send 700–1000 tokens every message until checkpoint fix is in your image.

### Quick benchmark (from LAN)

```bash
time curl -s http://intel-llm.cloud.danmanners.com/v1/chat/completions \
  -H "Authorization: Bearer $INTEL_LLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen3.6-27B-Q6_K.gguf","messages":[{"role":"user","content":"Count from 1 to 20."}],"max_tokens":128,"stream":false}'
```

Compare before/after each change; aim for stable tok/s in logs or wall time for 128 tokens.

## Troubleshooting

- **Scheduling:** Pod must land on node `intellectual` (`kubernetes.io/hostname=intellectual`, not the Talos FQDN) with `gpu.intel.com/xe` allocatable.
- **CDI / GPU:** Values start without `privileged` or host `/dev/dri` mounts; if the pod fails to use the GPU, add privileged + `/dev/dri` hostPath per cluster notes.
- **SYCL warmup crash:** Try `server-intel-b8477` or revert to `server-vulkan` (see §4b).
- **SYCL vs Vulkan:** Dense Q6_K on B70 may be faster on either backend — measure `tg` in logs after restart.
- **`llama-server: not found`:** The server image sets `ENTRYPOINT` to `/app/llama-server`. Do not wrap with `/bin/sh` unless you call `/app/llama-server` explicitly.
- **`libllama-common.so.0: cannot open shared object file`:** Vulkan/server images ship `.so` files in `/app`; set `LD_LIBRARY_PATH=/app` (the Dockerfile `WORKDIR` alone is not enough for the dynamic linker).
