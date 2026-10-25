# intel-vllm (intel/llm-scaler-vllm on Intel Arc B70 PRO)

OpenAI-compatible inference on `intellectual` using `gpu.intel.com/xe` and
Intel's optimized vLLM fork (`intel/llm-scaler-vllm`). Flags follow the
single-GPU Arc reference commands in the [intel/llm-scaler README](https://github.com/intel/llm-scaler/blob/main/vllm/README.md)
(`--enforce-eager`, `--block-size 64`, `--tensor-parallel-size 1`).

> **Parked (2026-10-24).** This deployment runs at `replicas: 0` — the ARC
> B70 PRO now serves
> [RecursiveSI/flint](https://huggingface.co/RecursiveSI/flint) via llama.cpp
> in [`../intel-llama`](../intel-llama) (same API key, new endpoint). Set
> `replicas: 1` here (and scale `intel-llama` to 0) to roll back; the Qwen3.6
> cache is untouched on the PVC.

## Model

| Item | Value |
|------|--------|
| Hugging Face repo | `Qwen/Qwen3.6-35B-A3B` (official BF16, ~72 GB, 26 shards) |
| Architecture | `Qwen3_5MoeForConditionalGeneration` (35B MoE, ~3B active; hybrid Gated DeltaNet + full attention, 1 full layer per 4) |
| Quantization | Online symmetric INT4 (`--quantization sym_int4`) |
| Context | `131072` (`--max-model-len`; native 262144 also fits) |
| Speculative decoding | MTP — `{"method":"qwen3_5_mtp","num_speculative_tokens":4}` |
| Image | `intel/llm-scaler-vllm:0.26.0-b2` (latest tag as of 2026-09) |

### Why online sym_int4

The B70 PRO has 32 GiB. The official BF16 checkpoint is ~72 GB and the
official FP8 checkpoint is ~36 GB — neither fits a single card, so 4-bit is
required. llm-scaler documents online symmetric INT4 (`sym_int4`) for exactly
this model (§2.2 / §3.2): the BF16 checkpoint is cached on the PVC and
quantized at load time. It needs the `VLLM_QUANTIZE_Q40_LIB` env var pointing
at the INT4 kernel library (`/opt/venv/lib/python3.12/site-packages/vllm_int4_for_multi_arc.so`
in this image).

Trade-off: every startup reloads and requantizes the 72 GB checkpoint
(slower than a pre-quantized ~19 GB community AWQ checkpoint). The official
base + Intel's quantizer is the better-validated path on this hardware, and
the 200 GiB PVC has room to hold the full cache.

### Context sizing

Only the 10 full-attention layers keep KV cache:
2 (K+V) × 10 layers × 2 KV heads × head_dim 256 × 2 bytes =
**20 KiB/token**. The 30 DeltaNet layers keep a small per-sequence state
(~30 MB/seq in FP16) instead. At `--gpu-memory-util 0.95` the KV pool is
~9–10 GiB (~500K tokens), so the 131072 cap still allows ~3 concurrent
full-length sequences — and the native 262144 would also fit (~1–2
concurrent) if needed.

### Thinking mode

Qwen3.6-35B-A3B's chat template has thinking **on by default** (it emits a
`thinking` block before the answer). It is a per-request toggle — no server
flag — via `chat_template_kwargs`:

```json
{"enable_thinking": false}
```

For VSCode autocomplete through Continue, use:

```yaml
models:
  openai:
    - name: Qwen3.6-35B Autocomplete
      model: intel-qwen36
      api_base: http://intel-llm.cloud.danmanners.com/v1
      api_key: ${INTEL_LLM_API_KEY}
      temperature: 0
      max_tokens_to_sample: 300
      chat_template_kwargs:
        enable_thinking: false
```

Chat / agentic coding clients can leave thinking on (the model's
SWE-bench-class strength depends on it). If Continue does not forward
`chat_template_kwargs`, verify with a direct curl (below) and pass the flag
via the llm-router layer instead.

## Endpoints

| Audience | URL | Notes |
|----------|-----|--------|
| **In-cluster** | `http://intel-vllm-core.aiml.svc.cluster.local:8080/v1` | ClusterIP (`service.core`); use from pods in `aiml`, future n8n, etc. |
| **LAN / laptop / Mac** | `http://intel-llm.cloud.danmanners.com/v1` | Cilium BGP LoadBalancer `172.31.0.35` (`service.public`) |
| **LAN (IP)** | `http://172.31.0.35:8080/v1` | Same backend if DNS is unavailable |

Do **not** use `*.svc.cluster.local` from laptops or the Mac Mini.

### Auth

vLLM reads the API key from the `VLLM_API_KEY` environment variable, which is
set via Secret `intel-llm-api-key` (key `api-key`). `llm-router` already
authenticates with this same secret (see
[`llm-router/models/model-intel.yaml`](../llm-router/models/model-intel.yaml)).
Clients send:

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

# Verify the model responds (thinking OFF)
curl -s http://intel-llm.cloud.danmanners.com/v1/chat/completions \
  -H "Authorization: Bearer $INTEL_LLM_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model": "intel-qwen36",
       "messages": [{"role": "user", "content": "Reply with the single word: pong"}],
       "max_tokens": 20,
       "chat_template_kwargs": {"enable_thinking": false}}'
```

First sync can take a long time while the model downloads from Hugging Face
(~72 GB for the BF16 checkpoint), and every restart re-quantizes it to INT4
on load (expect a slow startup).

> **Note:** `HF_TOKEN` (from `hf-secret` in OpenBao) keeps the download
> authenticated and out of the anonymous rate limit:
> ```bash
> bao login -method=oidc role=keeper-admin
> bao kv put dan/aiml/hf-token token=hf_xxxxxxxxxxxx
> ```

## Storage

The Hugging Face model cache lives on a 200 GiB PVC
(`persistence.cache`, storage class `ceph-block-retain`). The Qwen3.6-35B-A3B
BF16 checkpoint is ~72 GB and is loaded and quantized online at every
startup, so the full-size cache is kept on the volume.

The RBD is ext4. Rook-Ceph CSI **does** grow the filesystem when the PVC is
resized (verified 2026-10-11: 100 Gi → 200 Gi needed no manual steps).
After a `persistence.cache.size` change is synced, confirm with:

```bash
kubectl exec -n aiml deploy/intel-vllm -- df -hT /cache/huggingface
```

If the filesystem did not grow (e.g. an older rook-ceph release), run
`resize2fs` from a privileged pod on the node that has access to the RBD
device.

## Argo CD

Application: [`kubernetes/applications/intel-vllm.yaml`](../../applications/intel-vllm.yaml)
(namespace `aiml`). `automated.selfHeal: true` — pushes to `main` roll out
automatically, no manual sync needed.

## Performance

- vLLM uses continuous batching for efficient multi-request handling.
- `--enable-prefix-caching` reuses KV cache across requests sharing a prefix
  (e.g. a common system prompt) — particularly useful for autocomplete
  workloads with repeated file/system-prompt context.
- MTP speculative decoding (`--speculative-config`, 4 draft tokens from the
  model's 1-layer MTP head) speeds up decode; llm-scaler verified it on this
  exact model. Roll back by removing the flag if speculative decoding ever
  misbehaves on XPU.
- `--max-num-batched-tokens 8192` and `--max-num-seqs 8` follow the
  llm-scaler reference values; the KV pool, not the seq cap, is the real
  concurrency limit.

## Troubleshooting

- **Scheduling:** Pod must land on node `intellectual`
  (`kubernetes.io/hostname=intellectual`) with `gpu.intel.com/xe` allocatable.
- **GPU not detected:** Ensure the Intel GPU plugin and CDI are configured
  correctly on the node. Check logs for OpenVINO device discovery.
- **Model download slow:** First startup downloads the full model from HF.
  Subsequent restarts use the cached copy on the PVC.
- **OOM errors:** Reduce `--max-model-len` or `--max-num-batched-tokens` if VRAM
  pressure is observed.
- **`The model 'X' does not exist` (404):** clients must send
  `model: "intel-qwen36"`. The Hugging Face repo name and any previous
  model names (e.g. `intel-qwen3-coder`, `intel-gemma-4-12b-fp8`) are not
  served.