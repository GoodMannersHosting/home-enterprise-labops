# intel-vllm (intel/llm-scaler-vllm on Intel Arc B70 PRO)

OpenAI-compatible inference on `intellectual` using `gpu.intel.com/xe` and
Intel's optimized vLLM fork (`intel/llm-scaler-vllm`). Flags are taken
directly from the [intel/llm-scaler README §3.3](https://github.com/intel/llm-scaler/blob/main/vllm/README.md/#33-reference-commands-for-running-gemma-4-models-and-diffusiongemma).

## Model

| Item | Value |
|------|--------|
| Hugging Face repo | `google/gemma-4-12B-it` |
| Architecture | `gemma4_unified` / `Gemma4UnifiedForConditionalGeneration` |
| Quantization | FP8 online (`--quantization fp8`) |
| Context | `90000` (`--max-model-len`) |
| Image | `intel/llm-scaler-vllm:0.26.0-b2` (latest tag as of 2026-09) |

### transformers overlay (upstream bug workaround)

`google/gemma-4-12B-it` is the *encoder-free* Gemma 4 variant: its `model_type`
is `gemma4_unified`, not `gemma4`, and HF only registered that config in
**transformers 5.10**. The `0.26.0-b2` image already implements
`Gemma4UnifiedForConditionalGeneration` in its vLLM fork, but ships
**transformers 5.8.0**, so `AutoConfig.from_pretrained()` rejects the checkpoint
before vLLM is reached:

```
ValueError: The checkpoint you are trying to load has model type `gemma4_unified`
but Transformers does not recognize this architecture.
```

Tracked upstream as [intel/llm-scaler#705](https://github.com/intel/llm-scaler/issues/705).

The `transformers-overlay` init container works around this by installing
`transformers==5.10.2` into an `emptyDir` that is prepended to `PYTHONPATH`.
`--no-deps` is deliberate: it leaves the image's pinned `huggingface-hub`,
`tokenizers` and `numpy` in place, which torch and the vLLM fork are built
against. Installing *with* deps breaks the runtime.

> `--hf-overrides '{"model_type":"gemma4"}'` does **not** work and was removed.
> vLLM applies `hf_overrides` *after* `AutoConfig.from_pretrained()`, so it
> cannot rescue a `model_type` the installed transformers cannot resolve.
> It is also semantically wrong — `gemma4` is a different architecture with
> vision/audio encoder towers that this checkpoint does not have.

Drop the init container once Intel ships an image with transformers ≥ 5.10.

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
(~12 GB for Gemma 4 12B-it).

> **Note:** `google/gemma-4-12B-it` is a gated model. You must accept Google's
> license on HuggingFace and store the token in OpenBao before deploying:
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
- Flags follow Intel's reference command for this model, which pins
  `--max-model-len 90000`, `--block-size 64` and `--tensor-parallel-size 1`.

## Troubleshooting

- **Scheduling:** Pod must land on node `intellectual`
  (`kubernetes.io/hostname=intellectual`) with `gpu.intel.com/xe` allocatable.
- **GPU not detected:** Ensure the Intel GPU plugin and CDI are configured
  correctly on the node. Check logs for OpenVINO device discovery.
- **Model download slow:** First startup downloads the full model from HF.
  Subsequent restarts use the cached copy on the PVC.
- **OOM errors:** Reduce `--max-model-len` or `--max-num-batched-tokens` if VRAM
  pressure is observed.
- **`model type gemma4_unified` not recognized:** the `transformers-overlay`
  init container did not run or `PYTHONPATH` is unset. Confirm with:
  ```bash
  kubectl exec -n aiml deploy/intel-vllm -- \
    python3 -c "import transformers; print(transformers.__version__)"
  # expect 5.10.2, not 5.8.0
  ```