# Custom Vast.ai MiniMax H3 ComfyUI image

This is a clean-room Vast.ai setup. It does **not** use the RunPod image from the
README you supplied. That README was used only as the model/features target.

## Design goals

- Official PyTorch 2.10.0 + CUDA 13.0 base.
- Current ComfyUI source pinned to a known commit at image build time.
- ComfyUI core lives in the image; mutable user data lives in `/workspace`.
- Large models download directly into the persistent Vast volume and resume/skip.
- ComfyUI starts immediately while first-boot model downloads run in the background.
- Curated node set rather than "install everything".
- ComfyUI Manager is installed, and Manager-installed nodes persist.
- Power LoRA Loader is available through `rgthree-comfy`.
- MiniMax H3 native workflows, prompt/reference planning, Sol-Attn, QwenVL tools,
  TensorRT RIFE and TensorRT upscaling are pre-seeded.
- JupyterLab is built into our own image, so Vast can stay in `docker ENTRYPOINT` mode.

## Model profiles

Set `MINIMAX_PROFILE`:

| Profile | What it downloads |
|---|---|
| `full` | FL2VA + Ref2VA + both 8-step Turbo LoRAs + Heretic NVFP4 encoder + both VAEs + 10Eros-Max Turbo Hybrid skip-edges |
| `core` | Same, without 10Eros-Max |
| `fl2va` | Text/T2V/I2V/first-last-frame stack only |
| `ref2va` | Reference-to-video stack only |
| `none` | Nothing |

Default: `full`.

The exact requested `full` set is:

- `Comfy-Org/MiniMax-H3`
  - `vae/minimax_h3_video_vae_fp16.safetensors`
  - `vae/minimax_h3_audio_vae_fp32.safetensors`
- `lilcheaty/MiniMax-H3-NVFP4`
  - `minimax_h3_fl2va_pruned_nvfp4_convrot_int8.safetensors`
  - `minimax_h3_ref2va_pruned_nvfp4_convrot_int8.safetensors`
- `Momoking/Qwen3-VL-32B-Heretic-MiniMax-H3-NVFP4`
  - `qwen3vl_32b_heretic_minimax_h3_nvfp4.safetensors`
- `lightx2v/Minimax-h3-Turbo`
  - `minimax_h3_fl2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors`
  - `minimax_h3_ref2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors`
- `cicalooo/10Eros-Max-h3-int8-convrot`
  - `10Eros_Max_h3_TURBO-hybrid_beta3_int8_convrot_skip_edges.safetensors`

Set `DOWNLOAD_INT8_VIDEO_VAE=1` if you also want Comfy-Org's current INT8 ConvRot
video VAE alongside the requested FP16 one.

## Curated custom nodes

- ComfyUI-Manager
- rgthree-comfy (includes Power LoRA Loader)
- KJNodes
- VideoHelperSuite
- Impact Pack
- ComfyUI MiniMax H3 Guide
- ComfyUI Sol-Attn
- QwenVL-Mod
- RIFE TensorRT Auto
- Upscaler TensorRT Auto

The two TensorRT Auto repos are from the same maintainer and currently target the
same CUDA-13/TensorRT 10.15.1 family, which avoids the older RIFE/Upscaler
dependency mismatch.

## Persistence layout

`/opt/ComfyUI` is the image's core installation.

Persistent data:

```text
/workspace/
├── ComfyUI/
│   ├── models/
│   ├── custom_nodes/
│   ├── input/
│   ├── output/
│   └── user/
├── cache/
└── logs/
    ├── model-download.log
    ├── model-status.json
    └── jupyter.log
```

This means updating/installing nodes through Manager survives container recreation
as long as the Vast volume is attached.

## Build without knowing Docker

The included GitHub Actions workflow publishes the image for you.

1. Create a new GitHub repository.
2. Upload the contents of this folder to the repository root.
3. Make the repository public for the simplest Vast setup, or keep it private and
   configure GHCR credentials in Vast.
4. Open GitHub -> Actions -> "Build and publish Vast MiniMax image".
5. Run the workflow.
6. The resulting image is:
   `ghcr.io/YOUR_GITHUB_USERNAME/vast-minimax-h3:latest`
7. Create the Vast template using `VAST_TEMPLATE.md`.

If the repository is public but the GHCR package itself is private, open the package
settings on GitHub and change package visibility or configure Vast registry auth.

## First boot

ComfyUI starts before the ~large model set is finished.

Watch progress from Jupyter Terminal:

```bash
tail -f /workspace/logs/model-download.log
```

Quick status:

```bash
cat /workspace/logs/model-status.json
```

GPU:

```bash
nvidia-smi
```

ComfyUI process:

```bash
ps aux | grep -i '[m]ain.py'
```

## Updating ComfyUI intentionally

The Docker build pins ComfyUI to a known commit for reproducibility. To update it,
change the `COMFY_REF` build argument in the Dockerfile (or set it during a manual
build), rebuild the image, and launch a new container against the same volume.

Keeping the core in the image instead of letting Manager mutate it is intentional:
it makes a broken update reversible by switching image tags.

## Why no `--highvram`

The entrypoint deliberately starts with `--cuda-malloc --async-offload` and
`--fast fp16_accumulation`. Large H3 workloads can sit close to VRAM limits, so
forcing high-VRAM mode is less resilient. Add extra flags through
`COMFY_EXTRA_ARGS` only when you know you need them.

## Jupyter

Jupyter is started by our entrypoint on port 8888. If `JUPYTER_TOKEN` is not set,
a random token is generated once, stored at `/workspace/.jupyter_token`, and printed
to the instance logs.

Disable it with:

```text
ENABLE_JUPYTER=0
```
