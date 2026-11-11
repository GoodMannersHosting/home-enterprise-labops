# intel-vl (llama.cpp SYCL, Qwen3-VL-8B-Instruct on Intel Arc B70 PRO)

Vision-capable sibling of [`../intel-llama`](../intel-llama), on the same
`gpu.intel.com/xe` device and the same API key. **This owns the device:** the
commit that added it also parked `../intel-llama` at `replicas: 0`, because only
one deployment may hold it on `intellectual`. Flint's GGUF stays cached on its
PVC and its `model-llama` router entry is untouched, so rolling back is the same
two lines reversed — this to 0 and `../intel-llama` to 1 together, never both 1.

## Why this fills a gap

The router's only vision model is `media-analysis`, which is
`openrouter/google/gemini-3.8-flash` — a cloud call. Every other locally served
model declares `supportsVision: false`. This gives the lab a local option for
"does this image contain a document", which is the one thing a receipt/photo
pipeline actually needs.

## Model

| Item | Value |
|------|-------|
| Hugging Face repo | `Qwen/Qwen3-VL-8B-Instruct-GGUF` (official) |
| Quant | `Q4_K_M` (~5 GB) |
| Vision projector | `mmproj-Qwen3VL-8B-Instruct-F16.gguf` (~1.3 GB) |
| Context | `32768` (plenty for one image plus a short prompt) |
| Image | same pin as `../intel-llama` (`llama.cpp b11849`) |

## Caveats worth a look before merging

- **`--mmproj-url`** is the flag in current llama.cpp for fetching a projector
  alongside `--hf-repo`. If this build wants a local `--mmproj` path instead,
  point it at the file in `/cache/huggingface` after the first pull.
- **`172.31.0.62`** is a guess at the next free address in the 172.31.0.60-69
  pool.
- **The vLLM alternative is better supported for vision**: llm-scaler's README
  lists Qwen3-VL-4B/8B and Qwen3-VL-30B-A3B as verified on Arc, and §2.4 covers
  multi-modal serving. If you would rather keep one engine, `../intel-vllm` can
  serve vision by swapping its model and dropping `--language-model-only`
  (that flag is what skips the ~2GB vision tower on its current Qwen3.6-35B-A3B).
