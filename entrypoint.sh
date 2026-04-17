#!/bin/bash
# ================================================================
#  ENTRYPOINT — Lance au démarrage de chaque pod RunPod
# ================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${CYAN}${BOLD}══ $1 ══${NC}"; }

# ================================================================
#  1. VENV MUSUBI — installé sur /workspace (Network Volume)
#  Persistant entre les pods, installé une seule fois
# ================================================================
section "Venv musubi-tuner"

MUSUBI_VENV="/workspace/musubi-venv"

if [ ! -f "$MUSUBI_VENV/bin/python" ]; then
    info "Premier démarrage — création du venv musubi sur /workspace..."
    python3 -m venv "$MUSUBI_VENV"
    "$MUSUBI_VENV/bin/pip" install --upgrade pip -q
    "$MUSUBI_VENV/bin/pip" install \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu124 -q
    "$MUSUBI_VENV/bin/pip" install -e /musubi-tuner -q
    "$MUSUBI_VENV/bin/pip" install accelerate -q
    info "Venv musubi créé dans $MUSUBI_VENV"
else
    # Vérifie que musubi_tuner est bien installé
    if ! "$MUSUBI_VENV/bin/python" -c "import musubi_tuner" 2>/dev/null; then
        warn "musubi_tuner absent du venv — réinstallation..."
        "$MUSUBI_VENV/bin/pip" install -e /musubi-tuner -q
    fi
    info "Venv musubi OK — $($MUSUBI_VENV/bin/python --version)"
fi

# Symlink .venv dans musubi-tuner (chemin attendu par le node VRGDG)
if [ ! -L "/musubi-tuner/.venv" ]; then
    ln -sf "$MUSUBI_VENV" /musubi-tuner/.venv
    info "Symlink .venv → $MUSUBI_VENV"
fi

# ================================================================
#  2. SYMLINKS MODÈLES — Network Volume → /comfyui/models
# ================================================================
section "Symlinks modèles"

for dir in diffusion_models text_encoders vae latent_upscale_models loras; do
    src="/workspace/ComfyUI/models/$dir"
    dst="/comfyui/models/$dir"
    mkdir -p "$src"
    if [ ! -L "$dst" ]; then
        rm -rf "$dst"
        ln -s "$src" "$dst"
        info "Symlink : $dir"
    fi
done

# Output
mkdir -p /workspace/ComfyUI/output
[ ! -L "/comfyui/output" ] && rm -rf /comfyui/output && \
    ln -s /workspace/ComfyUI/output /comfyui/output && info "Symlink : output"

# User/workflows
mkdir -p /workspace/ComfyUI/user/default/workflows
[ ! -L "/comfyui/user" ] && rm -rf /comfyui/user && \
    ln -s /workspace/ComfyUI/user /comfyui/user && info "Symlink : user"

# Musubi models
mkdir -p /workspace/musubi-tuner/models/gemma3
[ ! -L "/musubi-tuner/models" ] && rm -rf /musubi-tuner/models && \
    ln -s /workspace/musubi-tuner/models /musubi-tuner/models && \
    info "Symlink : musubi models"

# Musubi dataset
mkdir -p /workspace/musubi-tuner/dataset/videos
[ ! -L "/musubi-tuner/dataset" ] && rm -rf /musubi-tuner/dataset && \
    ln -s /workspace/musubi-tuner/dataset /musubi-tuner/dataset && \
    info "Symlink : musubi dataset"

# ================================================================
#  3. PATCH LINUX SUR NODE VRGDG (idempotent)
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
    warn "Node VRGDG absent — installe via ComfyUI Manager puis redémarre."
fi

# ================================================================
#  4. JUPYTER (port 8888)
# ================================================================
section "Jupyter"

if ! command -v jupyter &>/dev/null; then
    pip install jupyter -q
fi

jupyter notebook \
    --ip=0.0.0.0 --port=8888 \
    --no-browser --allow-root \
    --NotebookApp.token='' \
    --NotebookApp.password='' \
    --notebook-dir=/workspace \
    &>/workspace/jupyter.log &
info "Jupyter lancé sur port 8888."

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
