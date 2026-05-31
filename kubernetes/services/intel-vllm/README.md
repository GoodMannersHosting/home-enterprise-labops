# intel-vllm (llama-server on Intel Arc B70)

OpenAI-compatible **llama-server** on `intellectual` using `gpu.intel.com/xe`.

## Why “intel-vllm”?

The Argo app / Helm release is named **`intel-vllm`** from the homelab plan (directory kept for a possible later **Intel vLLM XPU** deployment). **This workload is llama.cpp**, not vLLM. Public DNS is **`intel-llm.cloud.danmanners.com`** (no “vllm” in the hostname).

## Model

| Item | Value |
|------|--------|
| Hugging Face repo | `unsloth/gemma-4-26B-A4B-it-GGUF` |
| GGUF file | `gemma-4-26B-A4B-it-UD-Q4_K_M.gguf` (Transformer, ~26B params; Unsloth Dynamic Q4) |
| Context | `32768` (q8_0 KV ≈ 1.6 GiB; model ≈ 15–20 GiB; comfortably fits on 32 GiB B70) |
| Image | `ghcr.io/ggml-org/llama.cpp:server-vulkan` (Vulkan; SYCL blocked by upstream bug — see §4b) |
| Tunables | Flash attention on, KV cache `q8_0`, `GGML_VK_MMVQ_SHMEM_STAGING=1` |

Weights are pulled on first start into the `cache` PVC (`HF_HOME=/cache/huggingface`).

### Why this model

Gemma-4-26B-A4B IT is a **standard transformer dense** (no GDN/SSM blocks), so it dodges the SYCL Qwen3.6 warmup crash and benefits from full 26B active params per token. On Arc B70 + Vulkan + Q4_K_M this should sit well above the 13–15 t/s ceiling we hit with the dense Qwen3.6-27B model, and it's purpose-built for coding/agent workflows. If you later want a multimodal model on this box, run it as a **second** Deployment rather than swapping this one out.

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

### Multimodal (mmproj) — N/A for current model

Gemma-4-26B-A4B IT is text-only; the GGUF repo ships no `mmproj-*.gguf`, so there is nothing for `-hf` to auto-load. If you later switch back to a multimodal model (Qwen3.6, Qwen-VL, etc.), re-add `--no-mmproj` unless you actually want vision.

If generation feels slow, work through these in order.

### 1. Confirm the GPU is actually doing inference

From the pod logs after a request, you should see Vulkan offload (not CPU-only). On the node:

```bash
kubectl logs -n aiml deploy/intel-vllm-main -c core --tail=100
# Look for vulkan / GPU layer offload lines, not "BLAS" CPU fallback for most layers.
```

If layers run on CPU, fix CDI/`/dev/dri` (see Troubleshooting) before tuning flags.

### 2. Context length (largest lever in this deployment)

KV cache scales linearly with `--ctx-size` × `--parallel`. With Gemma-4-26B-A4B IT's GQA layout (8 KV heads, head_dim 256, 44 layers) and `--cache-type-k/v q8_0`, KV is roughly **~80 KiB per token**, so:

| `--ctx-size` | KV @ q8_0, parallel=1 |
|--------------|------------------------|
| 8 192 | ~0.6 GiB |
| 32 768 | ~2.5 GiB |
| 65 536 | ~5.0 GiB |
| 131 072 | ~10.0 GiB |

Default is **`32768`**, comfortably under the ~12 GiB headroom we have after Q4_K_M weights (~15–20 GiB). If you need very long context (codebase RAG, large patches) bump to 65 536 or 131 072 — but keep `--parallel 1` unless you actually need concurrent slots.

### 3. Parallel slots

Default `n_parallel=4` creates **four** slots each with full `n_ctx` KV — heavy on 32GB VRAM. Values use `--parallel 1` for Open WebUI.

### 4. Quantization (weights)

**Policy:** stay at **Q4_K_M** or higher for weight files. KV cache types (`q8_0`) are separate and may still be tuned.

| GGUF | Tradeoff |
|------|----------|
| `gemma-4-26B-A4B-it-UD-Q4_K_M.gguf` (default) | Unsloth Dynamic Q4 — balanced quality and size; ~15–20 GiB weights |
| `gemma-4-26B-A4B-it-Q6_K.gguf` | Higher quality; ~25 GiB weights, tight on 32 GiB VRAM |
| `gemma-4-26B-A4B-it-Q8_0.gguf` | Heaviest (~32 GiB), tightest quality but nearly fills all VRAM |

When switching `--hf-file`, remove the old snapshot under the cache PVC or use a fresh path so the pod does not keep loading the previous quant from disk.

### 4b. SYCL vs Vulkan (backend A/B)

Current image: **`server-vulkan`**. SYCL (`server-intel`) is **temporarily blocked** by an upstream bug:

> [ggml-org/llama.cpp#21474](https://github.com/ggml-org/llama.cpp/issues/21474) — `server-intel:latest` crashes silently during warmup on hybrid SSM/GDN architectures (e.g. Qwen3.6). The pod dies right after `warming up the model with an empty run` with no error.

Qwen3-Coder-30B-A3B is **not** hybrid (standard transformer MoE), so the warmup itself succeeds, but the underlying SYCL kernel regressions in `latest` still apply broadly. Workaround tags like `server-intel-b8477` predate Qwen3 family support, so they're not useful for us. We'll revisit SYCL when upstream cuts a fixed build; until then, Vulkan is the production backend.

| If you re-test SYCL later… | Action |
|----------------------------|--------|
| Works + higher `tg` | Switch back to `tag: server-intel`, **remove `LD_LIBRARY_PATH=/app` env**, add SYCL env (`ONEAPI_DEVICE_SELECTOR=level_zero:0`, etc.) |
| Crashes on warmup | Stay on `server-vulkan`, watch issue #21474 |

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

### Breaking ~40 t/s

We swapped models specifically because dense Qwen3.6-27B was capped at ~13–15 t/s on B70 + Vulkan + Q6_K. **Gemma-4-26B-A4B IT is dense with ~26B params per token**, which should provide strong quality and reasonable speed on Arc B70 + Vulkan + Q4_K_M — expected ballpark is roughly **20–40 t/s** depending on context length and prefill mix.

If TG is still under ~15 t/s after warm-up, check in order:

1. **Vulkan offload** — logs should show 49/49 layers on `Vulkan0`. Any CPU fallback = CDI / `/dev/dri` regression.
2. **Active experts** — MoE perf depends on expert dispatch hitting cache. Run a warm-up prompt (8–16 tokens) before benchmarking; first request includes JIT compile.
3. **Context length re-check** — `--ctx-size 32768` is fine; do not let Open WebUI send 65k+ unless you raise it server-side.
4. **Host Mesa 26+** on `intellectual` — Vulkan BF16/integer-dot paths matter most for MoE gating ops.
5. **Newer llama.cpp** — `pullPolicy: Always` already gets the latest `server-vulkan`; restart the pod to refresh shaders.
6. **Intel vLLM XPU (phase 2)** — for many concurrent agents, vLLM XPU with continuous batching beats `llama-server`. Run as a separate Deployment.

### Quick benchmark (from LAN)

```bash
time curl -s http://intel-llm.cloud.danmanners.com/v1/chat/completions \
  -H "Authorization: Bearer $INTEL_LLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-4-26B-A4B-it-UD-Q4_K_M.gguf","messages":[{"role":"user","content":"Write a Python function that reverses a linked list."}],"max_tokens":256,"stream":false}'
```

Compare before/after each change; aim for stable tok/s in logs or wall time for 128 tokens.

## Troubleshooting

- **Scheduling:** Pod must land on node `intellectual` (`kubernetes.io/hostname=intellectual`, not the Talos FQDN) with `gpu.intel.com/xe` allocatable.
- **CDI / GPU:** Values start without `privileged` or host `/dev/dri` mounts; if the pod fails to use the GPU, add privileged + `/dev/dri` hostPath per cluster notes.
- **SYCL warmup crash (silent exit after `warming up the model with an empty run`):** Upstream regression ([ggml-org/llama.cpp#21474](https://github.com/ggml-org/llama.cpp/issues/21474)) in `server-intel:latest`. Stay on `server-vulkan` until a fixed SYCL build lands; pre-Qwen3 tags (`server-intel-b8477`) are too old to load this family.
- **SYCL vs Vulkan:** Measure `tg` in logs after restart; current production backend is Vulkan (see §4b).
- **`llama-server: not found`:** The server image sets `ENTRYPOINT` to `/app/llama-server`. Do not wrap with `/bin/sh` unless you call `/app/llama-server` explicitly.
- **`libllama-common.so.0: cannot open shared object file`** (Vulkan image): Vulkan `server` ships `.so` files in `/app`; set `LD_LIBRARY_PATH=/app` (the Dockerfile `WORKDIR` alone is not enough for the dynamic linker).
- **`libsvml.so: cannot open shared object file`** (SYCL image): caused by setting `LD_LIBRARY_PATH=/app`. The SYCL base image (`intel/deep-learning-essentials`) defines `LD_LIBRARY_PATH` with the oneAPI compiler runtime; overriding it removes those paths. **Do not set `LD_LIBRARY_PATH` on the SYCL image** — the `llama-server` binary finds `/app/lib*.so` via its baked-in `RPATH=$ORIGIN`.
