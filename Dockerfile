FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

# ================================================================
#  ComfyUI + musubi-tuner (AkaneTendo25/ltx-2-dev)
#  LTX-Video 2.3 LoRA Trainer — RunPod Linux
#  Les modèles sont sur le Network Volume /workspace
# ================================================================

ENV DEBIAN_FRONTEND=noninteractive
ENV GIT_TERMINAL_PROMPT=0
ENV PYTHONUNBUFFERED=1

# ================================================================
#  1. DÉPENDANCES SYSTÈME
# ================================================================
RUN apt-get update -qq && apt-get install -y -qq \
    git git-lfs curl wget ffmpeg \
    libgl1 libglib2.0-0 \
    tmux htop nvtop \
    build-essential cmake \
    && git lfs install --skip-repo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ================================================================
#  2. COMFYUI
# ================================================================
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui

WORKDIR /comfyui

RUN pip install -r requirements.txt && \
    pip install \
        sqlalchemy alembic aiohttp \
        safetensors blake3 comfy_aimdo \
        librosa scikit-image gguf \
        imageio-ffmpeg piexif \
        segment_anything \
        sentencepiece protobuf \
        opencv-python \
        huggingface_hub \
        torchaudio

# ================================================================
#  3. COMFYUI-MANAGER
# ================================================================
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git \
        /comfyui/custom_nodes/ComfyUI-Manager && \
    pip install -r /comfyui/custom_nodes/ComfyUI-Manager/requirements.txt

# ================================================================
#  4. MUSUBI-TUNER (fork AkaneTendo25, branche ltx-2-dev)
# ================================================================
RUN git clone --branch ltx-2-dev \
        https://github.com/AkaneTendo25/musubi-tuner.git \
        /musubi-tuner

# Venv dédié musubi dans .venv (chemin attendu par le node VRGDG)
RUN python3 -m venv /musubi-tuner/.venv && \
    /musubi-tuner/.venv/bin/pip install --upgrade pip && \
    /musubi-tuner/.venv/bin/pip install \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu124 && \
    /musubi-tuner/.venv/bin/pip install -e /musubi-tuner && \
    /musubi-tuner/.venv/bin/pip install accelerate

# Config accelerate non-interactive (single GPU, bf16)
RUN mkdir -p /root/.cache/huggingface/accelerate && \
    cat > /root/.cache/huggingface/accelerate/default_config.yaml << 'EOF'
compute_environment: LOCAL_MACHINE
distributed_type: 'NO'
downcast_bf16: 'no'
machine_rank: 0
main_training_function: main
mixed_precision: bf16
num_machines: 1
num_processes: 1
rdzv_backend: static
same_network: true
tpu_use_cluster: false
tpu_use_sudo: false
use_cpu: false
EOF

# ================================================================
#  5. PATCH LINUX sur le node VRGDG
#  Appliqué après installation via entrypoint (node pas encore là)
#  Le script patch.sh sera appelé par entrypoint.sh
# ================================================================
COPY patch_vrgdg.sh /patch_vrgdg.sh
RUN chmod +x /patch_vrgdg.sh

# ================================================================
#  6. STRUCTURE DE DOSSIERS (modèles sur /workspace au runtime)
# ================================================================
RUN mkdir -p \
    /comfyui/models/diffusion_models/ltxGGUF \
    /comfyui/models/text_encoders/gemma-3-12b-it-qat-q4_0-unquantized \
    /comfyui/models/vae \
    /comfyui/models/latent_upscale_models \
    /comfyui/models/loras \
    /musubi-tuner/models/gemma3 \
    /musubi-tuner/dataset/videos

# ================================================================
#  7. ENTRYPOINT
# ================================================================
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8188 6006 8888

ENTRYPOINT ["/entrypoint.sh"]
