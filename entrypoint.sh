#!/bin/bash
# ================================================================
#  ENTRYPOINT — Lance au démarrage de chaque pod RunPod
#  - Symlinks modèles depuis /workspace (Network Volume)
#  - Patch Linux sur node VRGDG si installé
#  - Démarre ComfyUI
# ================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${CYAN}${BOLD}══ $1 ══${NC}"; }

# ================================================================
#  1. SYMLINKS — relie /comfyui et /musubi-tuner vers /workspace
#  Les modèles lourds restent sur le Network Volume
# ================================================================
section "Symlinks Network Volume"

# Modèles ComfyUI → /workspace/ComfyUI/models
if [ -d "/workspace/ComfyUI/models" ]; then
    # Remplace chaque sous-dossier modèles par un symlink
    for dir in diffusion_models text_encoders vae latent_upscale_models loras; do
        src="/workspace/ComfyUI/models/$dir"
        dst="/comfyui/models/$dir"
        mkdir -p "$src"
        if [ ! -L "$dst" ]; then
            rm -rf "$dst"
            ln -s "$src" "$dst"
            info "Symlink : $dst → $src"
        fi
    done
else
    warn "/workspace/ComfyUI/models absent — modèles non liés."
    warn "Lance /workspace/download_models.sh pour télécharger les modèles."
fi

# Output ComfyUI → /workspace/ComfyUI/output
mkdir -p /workspace/ComfyUI/output
if [ ! -L "/comfyui/output" ]; then
    rm -rf /comfyui/output
    ln -s /workspace/ComfyUI/output /comfyui/output
    info "Symlink output → /workspace/ComfyUI/output"
fi

# Workflows sauvegardés → /workspace/ComfyUI/workflows
mkdir -p /workspace/ComfyUI/user/default/workflows
if [ ! -L "/comfyui/user" ]; then
    rm -rf /comfyui/user
    ln -s /workspace/ComfyUI/user /comfyui/user
    info "Symlink user → /workspace/ComfyUI/user"
fi

# musubi models → /workspace/musubi-tuner/models
if [ -d "/workspace/musubi-tuner/models" ]; then
    if [ ! -L "/musubi-tuner/models" ]; then
        rm -rf /musubi-tuner/models
        ln -s /workspace/musubi-tuner/models /musubi-tuner/models
        info "Symlink musubi models → /workspace/musubi-tuner/models"
    fi
else
    mkdir -p /workspace/musubi-tuner/models/gemma3
    if [ ! -L "/musubi-tuner/models" ]; then
        rm -rf /musubi-tuner/models
        ln -s /workspace/musubi-tuner/models /musubi-tuner/models
    fi
    warn "Modèles musubi absents — télécharge-les dans /workspace/musubi-tuner/models/"
fi

# musubi dataset → /workspace/musubi-tuner/dataset
mkdir -p /workspace/musubi-tuner/dataset/videos
if [ ! -L "/musubi-tuner/dataset" ]; then
    rm -rf /musubi-tuner/dataset
    ln -s /workspace/musubi-tuner/dataset /musubi-tuner/dataset
    info "Symlink musubi dataset → /workspace/musubi-tuner/dataset"
fi

# ================================================================
#  2. PATCH LINUX SUR NODE VRGDG
#  Appliqué à chaque démarrage (idempotent)
# ================================================================
section "Patch Linux VRGDG"

VRGDG_FILE="/comfyui/custom_nodes/comfyui-vrgamedevgirl/LTXLoraTrain.py"
if [ -f "$VRGDG_FILE" ]; then
    sed -i 's|Scripts/python\.exe|bin/python|g' "$VRGDG_FILE"
    sed -i 's|Scripts", "python\.exe"|bin", "python"|g' "$VRGDG_FILE"
    sed -i 's|"Scripts"|"bin"|g' "$VRGDG_FILE"
    sed -i 's|python\.exe|python|g' "$VRGDG_FILE"
    sed -i 's|accelerate\.exe|accelerate|g' "$VRGDG_FILE"
    info "Patch VRGDG appliqué."
else
    warn "Node VRGDG absent — installe-le via ComfyUI Manager."
    warn "Puis redémarre le pod pour appliquer le patch automatiquement."
fi

# ================================================================
#  3. VÉRIFICATION VENV MUSUBI
# ================================================================
section "Venv musubi-tuner"

if [ ! -f "/musubi-tuner/.venv/bin/python" ]; then
    warn "Venv musubi absent — recréation..."
    python3 -m venv /musubi-tuner/.venv
    /musubi-tuner/.venv/bin/pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu124 -q
    /musubi-tuner/.venv/bin/pip install -e /musubi-tuner -q
    /musubi-tuner/.venv/bin/pip install accelerate -q
    info "Venv musubi recréé."
else
    # Vérifie que musubi_tuner est bien installé
    if ! /musubi-tuner/.venv/bin/python -c "import musubi_tuner" 2>/dev/null; then
        warn "musubi_tuner non installé dans .venv — réinstallation..."
        /musubi-tuner/.venv/bin/pip install -e /musubi-tuner -q
        info "musubi_tuner réinstallé."
    else
        info "Venv musubi OK."
    fi
fi

# ================================================================
#  4. JUPYTER (optionnel — port 8888)
# ================================================================
section "Jupyter"

if command -v jupyter &>/dev/null; then
    jupyter notebook \
        --ip=0.0.0.0 \
        --port=8888 \
        --no-browser \
        --allow-root \
        --NotebookApp.token='' \
        --NotebookApp.password='' \
        --notebook-dir=/workspace \
        &>/workspace/jupyter.log &
    info "Jupyter lancé sur port 8888."
else
    pip install jupyter -q
    jupyter notebook \
        --ip=0.0.0.0 \
        --port=8888 \
        --no-browser \
        --allow-root \
        --NotebookApp.token='' \
        --NotebookApp.password='' \
        --notebook-dir=/workspace \
        &>/workspace/jupyter.log &
    info "Jupyter installé et lancé."
fi

# ================================================================
#  5. DÉMARRAGE COMFYUI
# ================================================================
section "ComfyUI"

info "Démarrage sur port 8188..."
cd /comfyui
exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header \
    2>&1 | tee /workspace/comfyui.log
