#!/bin/bash
# ================================================================
#  TÉLÉCHARGEMENT DES MODÈLES LTX-2.3
#  À lancer UNE SEULE FOIS sur le Network Volume /workspace
#  Usage : bash /workspace/download_models.sh
#  Requis : export HF_TOKEN=hf_xxx  (pour Gemma-3)
# ================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

pip install huggingface_hub -q

python3 - << PYEOF
import os
from huggingface_hub import hf_hub_download, snapshot_download

TOKEN = os.environ.get("HF_TOKEN")

def dl(repo, filename, dest):
    out = os.path.join(dest, os.path.basename(filename))
    if os.path.exists(out):
        print(f"  → Déjà présent : {os.path.basename(filename)}")
        return
    print(f"  ↓ {os.path.basename(filename)} ...")
    try:
        hf_hub_download(repo_id=repo, filename=filename,
                        local_dir=dest, token=TOKEN)
        print(f"  ✓ OK")
    except Exception as e:
        print(f"  ✗ {e}")

# Dossiers
os.makedirs("/workspace/ComfyUI/models/diffusion_models/ltxGGUF", exist_ok=True)
os.makedirs("/workspace/ComfyUI/models/text_encoders/gemma-3-12b-it-qat-q4_0-unquantized", exist_ok=True)
os.makedirs("/workspace/ComfyUI/models/vae", exist_ok=True)
os.makedirs("/workspace/ComfyUI/models/latent_upscale_models", exist_ok=True)
os.makedirs("/workspace/musubi-tuner/models/gemma3", exist_ok=True)

# 1. LTX-2.3 checkpoint entraînement
print("\n[1/6] ltx-2.3-22b-dev.safetensors (train)...")
dl("Lightricks/LTX-2.3", "ltx-2.3-22b-dev.safetensors",
   "/workspace/musubi-tuner/models")

# 2. LTX-2.3 distilled GGUF Q6_K (inférence)
print("\n[2/6] LTX-2.3-distilled-Q6_K.gguf (inference)...")
dl("QuantStack/LTX-2.3-GGUF",
   "LTX-2.3-distilled/LTX-2.3-distilled-Q6_K.gguf",
   "/workspace/ComfyUI/models/diffusion_models/ltxGGUF")

# 3. VAE
print("\n[3/6] VAE video + audio...")
dl("Kijai/LTX2.3_comfy", "vae/LTX23_video_vae_bf16.safetensors",
   "/workspace/ComfyUI/models/vae")
dl("Kijai/LTX2.3_comfy", "vae/LTX23_audio_vae_bf16.safetensors",
   "/workspace/ComfyUI/models/vae")

# 4. Text projection
print("\n[4/6] ltx-2.3_text_projection_bf16.safetensors...")
dl("Kijai/LTX2.3_comfy",
   "text_encoders/ltx-2.3_text_projection_bf16.safetensors",
   "/workspace/ComfyUI/models/text_encoders")

# 5. Spatial upscaler
print("\n[5/6] ltx-2.3-spatial-upscaler-x2-1.0.safetensors...")
dl("Lightricks/LTX-2.3",
   "ltx-2.3-spatial-upscaler-x2-1.0.safetensors",
   "/workspace/ComfyUI/models/latent_upscale_models")

# 6. Gemma-3 12B it (musubi text encoder — nécessite token + licence)
print("\n[6/6] Gemma-3 12B it (musubi)...")
if not TOKEN:
    print("  ✗ HF_TOKEN absent.")
    print("  → export HF_TOKEN=hf_xxx && bash /workspace/download_models.sh")
    print("  → Accepte la licence : https://huggingface.co/google/gemma-3-12b-it")
else:
    try:
        snapshot_download(
            repo_id="google/gemma-3-12b-it",
            local_dir="/workspace/musubi-tuner/models/gemma3",
            token=TOKEN
        )
        print("  ✓ Gemma-3 OK")
    except Exception as e:
        print(f"  ✗ {e}")
        print("  → hf download google/gemma-3-12b-it --local-dir /workspace/musubi-tuner/models/gemma3 --token $HF_TOKEN")

# Gemma GGUF Q4 (ComfyUI text encoder)
print("\n[+] gemma-3-12b-it-q4_0.gguf (ComfyUI)...")
if TOKEN:
    dl("google/gemma-3-12b-it-qat-q4_0-gguf",
       "gemma-3-12b-it-q4_0.gguf",
       "/workspace/ComfyUI/models/text_encoders/gemma-3-12b-it-qat-q4_0-unquantized")
else:
    print("  → HF_TOKEN requis.")

print("\n✅ Téléchargements terminés.")
PYEOF
