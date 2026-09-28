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

# Core management
clone_node "https://github.com/Comfy-Org/ComfyUI-Manager.git" "ComfyUI-Manager"

# Workflow / quality-of-life nodes
clone_node "https://github.com/rgthree/rgthree-comfy.git" "rgthree-comfy"
clone_node "https://github.com/kijai/ComfyUI-KJNodes.git" "ComfyUI-KJNodes"
clone_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "ComfyUI-VideoHelperSuite"

# MiniMax H3 helpers
clone_node "https://github.com/ethanfel/ComfyUI-MiniMax-H3-Guide.git" "ComfyUI-MiniMax-H3-Guide"
clone_node "https://github.com/huchukato/ComfyUI-QwenVL-Mod.git" "ComfyUI-QwenVL-Mod"

# Video post-processing
clone_node "https://github.com/huchukato/ComfyUI-RIFE-TensorRT-Auto.git" "ComfyUI-RIFE-TensorRT-Auto"
clone_node "https://github.com/huchukato/ComfyUI-Upscaler-TensorRT-Auto.git" "ComfyUI-Upscaler-TensorRT-Auto"

echo "==> Custom-node installation finished successfully"
