#!/usr/bin/env python3
"""
Idempotent MiniMax H3 model downloader for the Vast.ai template.

Profiles:
  full   - everything requested: FL2VA + Ref2VA + both Turbo LoRAs + 10Eros.
  core   - FL2VA + Ref2VA + both Turbo LoRAs, without 10Eros.
  fl2va  - text/image/first-last-frame stack only.
  ref2va - reference-to-video stack only.
  none   - download nothing.

All files go directly into the persistent /workspace/ComfyUI/models tree.
huggingface_hub uses temporary files, so interrupted downloads do not masquerade
as completed .safetensors files.
"""
from __future__ import annotations

import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from huggingface_hub import hf_hub_download

MODELS_ROOT = Path(os.getenv("MODELS_ROOT", "/workspace/ComfyUI/models"))
LOG_DIR = Path(os.getenv("LOG_DIR", "/workspace/logs"))
STATUS_FILE = LOG_DIR / "model-status.json"
PROFILE = os.getenv("MINIMAX_PROFILE", "full").strip().lower()
WORKERS = max(1, min(int(os.getenv("MODEL_DOWNLOAD_WORKERS", "2")), 4))
HF_TOKEN = os.getenv("HF_TOKEN") or os.getenv("HUGGING_FACE_HUB_TOKEN")

VALID_PROFILES = {"full", "core", "fl2va", "ref2va", "none"}
if PROFILE not in VALID_PROFILES:
    print(f"[models] Unknown MINIMAX_PROFILE={PROFILE!r}; using 'full'.", flush=True)
    PROFILE = "full"

# remote_path is the exact filename inside the Hugging Face repository.
# local_dir is relative to ComfyUI/models and is chosen so the downloaded file
# lands in the correct ComfyUI model category.
MODELS = [
    {
        "name": "MiniMax H3 video VAE FP16",
        "repo": "Comfy-Org/MiniMax-H3",
        "remote_path": "vae/minimax_h3_video_vae_fp16.safetensors",
        "local_dir": ".",
        "profiles": ["full", "core", "fl2va", "ref2va"],
    },
    {
        "name": "MiniMax H3 audio VAE FP32",
        "repo": "Comfy-Org/MiniMax-H3",
        "remote_path": "vae/minimax_h3_audio_vae_fp32.safetensors",
        "local_dir": ".",
        "profiles": ["full", "core", "fl2va", "ref2va"],
    },
    {
        "name": "FL2VA NVFP4 + ConvRot INT8",
        "repo": "lilcheaty/MiniMax-H3-NVFP4",
        "remote_path": "minimax_h3_fl2va_pruned_nvfp4_convrot_int8.safetensors",
        "local_dir": "diffusion_models",
        "profiles": ["full", "core", "fl2va"],
    },
    {
        "name": "Ref2VA NVFP4 + ConvRot INT8",
        "repo": "lilcheaty/MiniMax-H3-NVFP4",
        "remote_path": "minimax_h3_ref2va_pruned_nvfp4_convrot_int8.safetensors",
        "local_dir": "diffusion_models",
        "profiles": ["full", "core", "ref2va"],
    },
    {
        "name": "Qwen3-VL 32B Heretic MiniMax H3 NVFP4",
        "repo": "Momoking/Qwen3-VL-32B-Heretic-MiniMax-H3-NVFP4",
        "remote_path": "qwen3vl_32b_heretic_minimax_h3_nvfp4.safetensors",
        "local_dir": "text_encoders",
        "profiles": ["full", "core", "fl2va", "ref2va"],
    },
    {
        "name": "FL2V Turbo 8-step 768p LoRA",
        "repo": "lightx2v/Minimax-h3-Turbo",
        "remote_path": "minimax_h3_fl2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors",
        "local_dir": "loras",
        "profiles": ["full", "core", "fl2va"],
    },
    {
        "name": "Ref2V Turbo 8-step 768p LoRA",
        "repo": "lightx2v/Minimax-h3-Turbo",
        "remote_path": "minimax_h3_ref2v_turbo_8step_v1.0_768p_comfyui_bf16.safetensors",
        "local_dir": "loras",
        "profiles": ["full", "core", "ref2va"],
    },
    {
        "name": "10Eros-Max H3 TURBO Hybrid Beta3 INT8 ConvRot Skip-Edges",
        "repo": "cicalooo/10Eros-Max-h3-int8-convrot",
        "remote_path": "10Eros_Max_h3_TURBO-hybrid_beta3_int8_convrot_skip_edges.safetensors",
        "local_dir": "diffusion_models",
        "profiles": ["full"],
    },
]

# Optional current official INT8 video VAE. The requested FP16 VAE remains the default.
if os.getenv("DOWNLOAD_INT8_VIDEO_VAE", "0").lower() in {"1", "true", "yes", "on"}:
    MODELS.append(
        {
            "name": "MiniMax H3 video VAE INT8 ConvRot (optional)",
            "repo": "Comfy-Org/MiniMax-H3",
            "remote_path": "vae/minimax_h3_video_vae_int8_convrot.safetensors",
            "local_dir": ".",
            "profiles": ["full", "core", "fl2va", "ref2va"],
        }
    )

def expected_target(m: dict) -> Path:
    local_base = MODELS_ROOT / m["local_dir"]
    # If downloading a nested remote path (the VAE files), local_dir "." preserves
    # the remote "vae/" subfolder. Root files simply use their basename.
    if "/" in m["remote_path"] and m["local_dir"] == ".":
        return local_base / m["remote_path"]
    return local_base / Path(m["remote_path"]).name

def write_status(rows: list[dict]) -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATUS_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps({"profile": PROFILE, "models": rows}, indent=2), encoding="utf-8")
    tmp.replace(STATUS_FILE)

def download_one(m: dict) -> dict:
    target = expected_target(m)
    target.parent.mkdir(parents=True, exist_ok=True)

    # hf_hub_download only publishes the final filename when complete. A real final
    # file larger than 1 MiB is therefore safe to treat as done.
    if target.exists() and target.stat().st_size > 1024 * 1024:
        print(f"[models] SKIP  {m['name']} -> {target}", flush=True)
        return {"name": m["name"], "status": "present", "path": str(target)}

    print(f"[models] GET   {m['name']} ({m['repo']} :: {m['remote_path']})", flush=True)
    local_dir = MODELS_ROOT / m["local_dir"]
    local_dir.mkdir(parents=True, exist_ok=True)

    downloaded = hf_hub_download(
        repo_id=m["repo"],
        filename=m["remote_path"],
        local_dir=str(local_dir),
        token=HF_TOKEN,
    )

    if not target.exists():
        # Defensive fallback for future huggingface_hub layout changes.
        got = Path(downloaded)
        if got.exists() and got != target:
            target.parent.mkdir(parents=True, exist_ok=True)
            got.replace(target)

    print(f"[models] DONE  {m['name']} -> {target}", flush=True)
    return {"name": m["name"], "status": "downloaded", "path": str(target)}

def main() -> int:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    MODELS_ROOT.mkdir(parents=True, exist_ok=True)

    if PROFILE == "none":
        write_status([])
        print("[models] MINIMAX_PROFILE=none; nothing to download.", flush=True)
        return 0

    selected = [m for m in MODELS if PROFILE in m["profiles"]]
    rows = [{"name": m["name"], "status": "queued", "path": str(expected_target(m))} for m in selected]
    write_status(rows)

    failures = []
    results = []
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(download_one, m): m for m in selected}
        for fut in as_completed(futures):
            m = futures[fut]
            try:
                results.append(fut.result())
            except Exception as exc:
                print(f"[models] ERROR {m['name']}: {exc}", file=sys.stderr, flush=True)
                failures.append({"name": m["name"], "status": "error", "error": str(exc)})

            current = results + failures
            write_status(current)

    write_status(results + failures)
    if failures:
        print(f"[models] Finished with {len(failures)} failure(s). Re-running the script resumes.", flush=True)
        return 2

    print(f"[models] All {len(results)} selected models are ready.", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
