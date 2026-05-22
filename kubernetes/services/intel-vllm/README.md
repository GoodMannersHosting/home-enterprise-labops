# intel-vllm (llama-server on Intel Arc B70)

OpenAI-compatible **llama-server** on `intellectual` using `gpu.intel.com/xe`.

## Why “intel-vllm”?

The Argo app / Helm release is named **`intel-vllm`** from the homelab plan (directory kept for a possible later **Intel vLLM XPU** deployment). **This workload is llama.cpp**, not vLLM. Public DNS is **`intel-llm.cloud.danmanners.com`** (no “vllm” in the hostname).

## Model

| Item | Value |
|------|--------|
| Hugging Face repo | `unsloth/Qwen3.6-27B-GGUF` |
| GGUF file | `Qwen3.6-27B-Q6_K.gguf` |
| Context | `32768` (raise after stable) |
| Image | `ghcr.io/ggml-org/llama.cpp:server-vulkan` |

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

## Troubleshooting

- **Scheduling:** Pod must land on node `intellectual` (`kubernetes.io/hostname=intellectual`, not the Talos FQDN) with `gpu.intel.com/xe` allocatable.
- **CDI / GPU:** Values start without `privileged` or host `/dev/dri` mounts; if the pod fails to use the GPU, add privileged + `/dev/dri` hostPath per cluster notes.
- **SYCL image:** Prefer `server-vulkan` on Arc; `server-intel` (SYCL) has known regressions on some Arc iGPUs.
- **`llama-server: not found`:** The server image sets `ENTRYPOINT` to `/app/llama-server`. Do not wrap with `/bin/sh` unless you call `/app/llama-server` explicitly.
- **`libllama-common.so.0: cannot open shared object file`:** Vulkan/server images ship `.so` files in `/app`; set `LD_LIBRARY_PATH=/app` (the Dockerfile `WORKDIR` alone is not enough for the dynamic linker).
