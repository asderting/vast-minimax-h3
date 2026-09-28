#!/usr/bin/env bash
set -Eeuo pipefail

DEST="${1:-/opt/ComfyUI/custom_nodes}"
mkdir -p "$DEST"

clone_node () {
  local url="$1"
  local name="$2"
  echo "==> Installing $name"
  if [[ ! -d "$DEST/$name/.git" ]]; then
    git clone --depth 1 "$url" "$DEST/$name"
  fi
  if [[ -f "$DEST/$name/requirements.txt" ]]; then
    python -m pip install -r "$DEST/$name/requirements.txt"
  fi
}

# Curated for MiniMax H3 + video work. Deliberately avoids giant "install everything"
# node packs to keep dependency conflicts down.
clone_node "https://github.com/Comfy-Org/ComfyUI-Manager.git" "ComfyUI-Manager"
clone_node "https://github.com/rgthree/rgthree-comfy.git" "rgthree-comfy"
clone_node "https://github.com/kijai/ComfyUI-KJNodes.git" "ComfyUI-KJNodes"
clone_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "ComfyUI-VideoHelperSuite"
clone_node "https://github.com/ethanfel/ComfyUI-MiniMax-H3-Guide.git" "ComfyUI-MiniMax-H3-Guide"
clone_node "https://github.com/Saganaki22/ComfyUI-sol-attn.git" "ComfyUI-sol-attn"
clone_node "https://github.com/huchukato/ComfyUI-QwenVL-Mod.git" "ComfyUI-QwenVL-Mod"

# Both of these current huchukato Auto nodes use the same CUDA 13 TensorRT
# family (10.15.1.x), avoiding the older RIFE/Upscaler version mismatch.
clone_node "https://github.com/huchukato/ComfyUI-RIFE-TensorRT-Auto.git" "ComfyUI-RIFE-TensorRT-Auto"
clone_node "https://github.com/huchukato/ComfyUI-Upscaler-TensorRT-Auto.git" "ComfyUI-Upscaler-TensorRT-Auto"

# Impact Pack can try to fetch extra detector models during setup; this marker keeps
# the image build lean. Models can still be installed later from Manager when needed.
touch "$DEST/skip_download_model" || true

echo "==> Custom-node seed installation finished"
