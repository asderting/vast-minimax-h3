# Vast.ai template settings

Use these after your image has been built and published.

## Recommended settings

- **Template name:** MiniMax H3 - Custom Blackwell
- **Image:** `ghcr.io/YOUR_GITHUB_USERNAME/vast-minimax-h3:latest`
- **Launch mode:** `docker ENTRYPOINT`
- **Ports:** `8188/tcp`, `8888/tcp`
- **Container disk:** 35-50 GB
- **Recommended volume:** 180-250 GB
- **Volume mount/install path:** `/workspace`
- **Visibility:** Private while testing

Do not select Vast's "Jupyter + SSH" launch mode for this image. The image starts
ComfyUI and Jupyter itself. Vast's Jupyter/SSH modes replace the Docker entrypoint.

## Suggested environment variables

Non-secret template variables:
- `MINIMAX_PROFILE=full`
- `DOWNLOAD_MODELS=1`
- `MODEL_DOWNLOAD_WORKERS=2`
- `ENABLE_JUPYTER=1`
- `COMFY_PORT=8188`
- `JUPYTER_PORT=8888`

Put `HF_TOKEN` in Vast **Account Settings -> Environment Variables**, not in a
public/shared template.

## GPU filter

The requested diffusion/text-encoder set contains NVFP4 weights. Prefer Blackwell:
- RTX 5090
- RTX PRO Blackwell cards
- B200/GB-class systems when cost makes sense

For this exact image, favor at least ~64 GB host RAM for the 32B encoder and
large video workloads.
