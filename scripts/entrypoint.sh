#!/usr/bin/env bash
set -Eeuo pipefail

COMFYUI_ROOT="${COMFYUI_ROOT:-/opt/ComfyUI}"
WORKSPACE="${WORKSPACE:-/workspace}"
DATA_ROOT="${DATA_ROOT:-$WORKSPACE/ComfyUI}"
COMFY_PORT="${COMFY_PORT:-8188}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"

mkdir -p \
  "$DATA_ROOT/models" \
  "$DATA_ROOT/custom_nodes" \
  "$DATA_ROOT/input" \
  "$DATA_ROOT/output" \
  "$DATA_ROOT/user/default/workflows" \
  "$WORKSPACE/cache/huggingface" \
  "$WORKSPACE/cache/torch" \
  "$WORKSPACE/cache/triton" \
  "$WORKSPACE/logs"

# Seed curated nodes, but never overwrite anything the user/Manager already changed.
rsync -a --ignore-existing /opt/seed/custom_nodes/ "$DATA_ROOT/custom_nodes/" || true

# Seed starter workflows without overwriting user's versions.
rsync -a --ignore-existing /opt/seed/workflows/ "$DATA_ROOT/user/default/workflows/" || true

# Make ComfyUI's mutable areas persistent. Core code remains immutable in /opt.
for d in models custom_nodes input output user; do
  if [[ -e "$COMFYUI_ROOT/$d" && ! -L "$COMFYUI_ROOT/$d" ]]; then
    rm -rf "$COMFYUI_ROOT/$d"
  fi
  ln -sfn "$DATA_ROOT/$d" "$COMFYUI_ROOT/$d"
done

echo
echo "=============================================================="
echo " MiniMax H3 Vast.ai container"
echo " ComfyUI:      http://0.0.0.0:${COMFY_PORT}"
echo " Persistent:   ${DATA_ROOT}"
echo " Model profile: ${MINIMAX_PROFILE:-full}"
echo "=============================================================="
echo

nvidia-smi || true
python - <<'PY' || true
import torch
print("Torch:", torch.__version__)
print("CUDA runtime:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
    print("Capability:", torch.cuda.get_device_capability(0))
PY

# Download the heavy model set in the background so ComfyUI itself comes up immediately.
if [[ "${DOWNLOAD_MODELS:-1}" =~ ^(1|true|yes|on)$ ]]; then
  echo "[boot] Starting resumable background model download..."
  nohup python /usr/local/bin/download_minimax_models.py \
    >"$WORKSPACE/logs/model-download.log" 2>&1 &
  echo $! > "$WORKSPACE/logs/model-download.pid"
else
  echo "[boot] DOWNLOAD_MODELS is disabled."
fi

# Optional JupyterLab included in our own image, so Vast does NOT need Jupyter launch mode.
if [[ "${ENABLE_JUPYTER:-1}" =~ ^(1|true|yes|on)$ ]]; then
  if [[ -z "${JUPYTER_TOKEN:-}" ]]; then
    if [[ -f "$WORKSPACE/.jupyter_token" ]]; then
      JUPYTER_TOKEN="$(cat "$WORKSPACE/.jupyter_token")"
    else
      JUPYTER_TOKEN="$(python - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
)"
      printf '%s' "$JUPYTER_TOKEN" > "$WORKSPACE/.jupyter_token"
      chmod 600 "$WORKSPACE/.jupyter_token"
    fi
  fi
  echo "[boot] JupyterLab: http://0.0.0.0:${JUPYTER_PORT}"
  echo "[boot] Jupyter token: ${JUPYTER_TOKEN}"
  nohup jupyter lab \
    --ip=0.0.0.0 \
    --port="$JUPYTER_PORT" \
    --no-browser \
    --allow-root \
    --ServerApp.token="$JUPYTER_TOKEN" \
    --ServerApp.password='' \
    --ServerApp.root_dir="$WORKSPACE" \
    >"$WORKSPACE/logs/jupyter.log" 2>&1 &
fi

cd "$COMFYUI_ROOT"

# Safe defaults for large H3 workloads on 32-50+ GB Blackwell cards. Do not force
# --highvram; async offload is more resilient. Extra flags remain user-configurable.
DEFAULT_ARGS=(
  --listen 0.0.0.0
  --port "$COMFY_PORT"
  --disable-auto-launch
  --cuda-malloc
  --async-offload
  --fast fp16_accumulation
)

if [[ "${USE_CK_ATTENTION:-0}" =~ ^(1|true|yes|on)$ ]]; then
  DEFAULT_ARGS+=(--use-ck-attention)
fi

echo "[boot] Launching ComfyUI..."
# shellcheck disable=SC2086
exec python main.py "${DEFAULT_ARGS[@]}" ${COMFY_EXTRA_ARGS:-}
