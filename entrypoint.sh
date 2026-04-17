#!/bin/bash
# ================================================================
#  ENTRYPOINT — Lance au démarrage de chaque pod RunPod
# ================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${CYAN}${BOLD}══ $1 ══${NC}"; }

# ================================================================
#  1. VENV MUSUBI — sur /workspace (Network Volume, persistant)
# ================================================================
section "Venv musubi-tuner"

MUSUBI_VENV="/workspace/musubi-venv"

if [ ! -f "$MUSUBI_VENV/bin/python" ]; then
    info "Premier démarrage — création du venv musubi..."
    python3 -m venv "$MUSUBI_VENV"
    "$MUSUBI_VENV/bin/pip" install --upgrade pip -q
    # cu128 pour compatibilité Blackwell
    "$MUSUBI_VENV/bin/pip" install \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu128 -q
    "$MUSUBI_VENV/bin/pip" install -e /musubi-tuner -q
    "$MUSUBI_VENV/bin/pip" install accelerate -q
    info "Venv musubi créé."
else
    if ! "$MUSUBI_VENV/bin/python" -c "import musubi_tuner" 2>/dev/null; then
        warn "musubi_tuner absent — réinstallation..."
        "$MUSUBI_VENV/bin/pip" install -e /musubi-tuner -q
    fi
    info "Venv musubi OK."
fi

# Symlink .venv → /workspace/musubi-venv (chemin attendu par VRGDG)
ln -sf "$MUSUBI_VENV" /musubi-tuner/.venv

# ================================================================
#  2. SYMLINKS MODÈLES
# ================================================================
section "Symlinks modèles"

for dir in diffusion_models text_encoders vae latent_upscale_models loras; do
    src="/workspace/ComfyUI/models/$dir"
    dst="/comfyui/models/$dir"
    mkdir -p "$src"
    rm -rf "$dst"
    ln -sf "$src" "$dst"
done
info "ComfyUI models OK."

mkdir -p /workspace/ComfyUI/output
rm -rf /comfyui/output
ln -sf /workspace/ComfyUI/output /comfyui/output

mkdir -p /workspace/ComfyUI/user/default/workflows
rm -rf /comfyui/user
ln -sf /workspace/ComfyUI/user /comfyui/user

mkdir -p /workspace/musubi-tuner/models/gemma-3-12b-it
rm -rf /musubi-tuner/models
ln -sf /workspace/musubi-tuner/models /musubi-tuner/models

mkdir -p /workspace/musubi-tuner/dataset
rm -rf /musubi-tuner/dataset
ln -sf /workspace/musubi-tuner/dataset /musubi-tuner/dataset

info "Symlinks OK."

# ================================================================
#  3. PATCH LINUX VRGDG (idempotent)
# ================================================================
section "Patch Linux VRGDG"

bash /patch_vrgdg.sh

# ================================================================
#  4. JUPYTER LAB (port 8888)
# ================================================================
section "Jupyter Lab"

pkill -f jupyter 2>/dev/null || true
sleep 1

jupyter lab \
    --ip=0.0.0.0 --port=8888 \
    --no-browser --allow-root \
    --ServerApp.token='' \
    --ServerApp.password='' \
    --ServerApp.allow_origin='*' \
    --notebook-dir=/workspace \
    &>/workspace/jupyter.log &

info "Jupyter Lab lancé sur port 8888."

# ================================================================
#  5. COMFYUI
# ================================================================
section "ComfyUI"

info "Démarrage sur port 8188..."
cd /comfyui
exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header \
    2>&1 | tee /workspace/comfyui.log
