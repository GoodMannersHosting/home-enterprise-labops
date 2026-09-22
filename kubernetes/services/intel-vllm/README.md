# intel-vllm (intel/llm-scaler-vllm on Intel Arc B70 PRO)

OpenAI-compatible inference on `intellectual` using `gpu.intel.com/xe` and
Intel's optimized vLLM fork (`intel/llm-scaler-vllm`). Flags are taken
directly from the [intel/llm-scaler README §3.3](https://github.com/intel/llm-scaler/blob/main/vllm/README.md/#33-reference-commands-for-running-gemma-4-models-and-diffusiongemma).

## Model

| Item | Value |
|------|--------|
| Hugging Face repo | `google/gemma-4-12B-it` |
| Quantization | FP8 online (`--quantization fp8`) |
| Context | `90000` (`--max-model-len`) |
| Image | `intel/llm-scaler-vllm:0.26.0-b2` |

## Endpoints

| Audience | URL | Notes |
|----------|-----|--------|
| **In-cluster** | `http://intel-vllm-core.aiml.svc.cluster.local:8080/v1` | ClusterIP (`service.core`); use from pods in `aiml`, future n8n, etc. |
| **LAN / laptop / Mac** | `http://intel-llm.cloud.danmanners.com/v1` | Cilium BGP LoadBalancer `172.31.0.35` (`service.public`) |
| **LAN (IP)** | `http://172.31.0.35:8080/v1` | Same backend if DNS is unavailable |

Do **not** use `*.svc.cluster.local` from laptops or the Mac Mini.

### Auth

vLLM reads the API key from the `VLLM_API_KEY` environment variable, which is
set via Secret `intel-llm-api-key` (key `api-key`). Clients send:

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
(~12 GB for Gemma 4 12B-it).

## Argo CD

Application: [`kubernetes/applications/intel-vllm.yaml`](../../applications/intel-vllm.yaml)
(namespace `aiml`). `automated.selfHeal: true` — pushes to `main` roll out
automatically, no manual sync needed.

## Performance

- vLLM OpenVINO uses continuous batching for efficient multi-request handling.
- `--enable-chunked-prefill` improves throughput for concurrent requests.
- Model length and batch size are tuned for the Arc B70 PRO's 16GB VRAM.

## Troubleshooting

- **Scheduling:** Pod must land on node `intellectual`
  (`kubernetes.io/hostname=intellectual`) with `gpu.intel.com/xe` allocatable.
- **GPU not detected:** Ensure the Intel GPU plugin and CDI are configured
  correctly on the node. Check logs for OpenVINO device discovery.
- **Model download slow:** First startup downloads the full model from HF.
  Subsequent restarts use the cached copy on the PVC.
- **OOM errors:** Reduce `--max-model-len` or `--max-num-batched-tokens` if VRAM
  pressure is observed.