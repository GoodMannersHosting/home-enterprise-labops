# intel-vllm (intel/llm-scaler-vllm on Intel Arc B70 PRO)

OpenAI-compatible inference on `intellectual` using `gpu.intel.com/xe` and
Intel's optimized vLLM fork (`intel/llm-scaler-vllm`). Flags follow the
single-GPU Arc reference commands in the [intel/llm-scaler README](https://github.com/intel/llm-scaler/blob/main/vllm/README.md)
(`--enforce-eager`, `--block-size 64`, `--tensor-parallel-size 1`).

## Model

| Item | Value |
|------|--------|
| Hugging Face repo | `cyankiwi/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit` |
| Architecture | `Qwen3MoeForCausalLM` (30B MoE, ~3B active) |
| Quantization | AWQ 4-bit, auto-detected from the checkpoint (`compressed-tensors` WNA16) |
| Context | `32768` (`--max-model-len`, native; 256K only via YaRN) |
| Image | `intel/llm-scaler-vllm:0.26.0-b2` (latest tag as of 2026-09) |

### Why AWQ 4-bit

The B70 PRO has 32 GiB. BF16 weights for this model are ~60 GB and even
online FP8 (~30 GB) leaves no KV-cache headroom, so the AWQ 4-bit checkpoint
(~17 GB weights) is used. vLLM reads the quantization from the checkpoint's
config — there is deliberately **no** `--quantization` flag (Intel documents
this for pre-quantized AWQ/GPTQ models).

### Context sizing

Qwen3-30B-A3B KV cache is 96 KiB/token (48 layers × 4 KV heads × 128 dim,
FP16). At `--gpu-memory-util 0.95` the KV pool is ~12 GiB (~124K tokens), so
the 32K cap allows ~3 concurrent full-length requests. Raising
`--max-model-len` toward the 256K YaRN maximum is possible but drops
concurrency to 1 at 100K+; if that is ever needed, pair it with
`--kv-cache-dtype fp8_e4m3` (llm-scaler §3.5) to double KV capacity.

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
```

First sync can take a long time while the model downloads from Hugging Face
(~17 GB for the AWQ checkpoint).

> **Note:** `HF_TOKEN` (from `hf-secret` in OpenBao) keeps the download
> authenticated and out of the anonymous rate limit:
> ```bash
> bao login -method=oidc role=keeper-admin
> bao kv put dan/aiml/hf-token token=hf_xxxxxxxxxxxx
> ```

## Argo CD

Application: [`kubernetes/applications/intel-vllm.yaml`](../../applications/intel-vllm.yaml)
(namespace `aiml`). `automated.selfHeal: true` — pushes to `main` roll out
automatically, no manual sync needed.

## Performance

- vLLM uses continuous batching for efficient multi-request handling.
- `--enable-prefix-caching` reuses KV cache across requests sharing a prefix
  (e.g. a common system prompt).
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
  `model: "intel-qwen3-coder"`. The Hugging Face repo name and any previous
  model names (e.g. `intel-gemma-4-12b-fp8`) are not served.