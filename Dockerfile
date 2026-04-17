FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

# ================================================================
#  ComfyUI + musubi-tuner (AkaneTendo25/ltx-2-dev)
#  Image Blackwell-compatible (CUDA 12.8 / PyTorch 2.8)
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
        jupyterlab

# Fix torchvision compatible cu128
RUN pip install torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu128 \
    --force-reinstall -q

# ================================================================
#  3. COMFYUI-MANAGER
# ================================================================
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git \
        /comfyui/custom_nodes/ComfyUI-Manager && \
    pip install -r /comfyui/custom_nodes/ComfyUI-Manager/requirements.txt

# ================================================================
#  4. MUSUBI-TUNER — clone seulement
#  Le venv est créé sur /workspace à l'entrypoint (persistant)
# ================================================================
RUN git clone --branch ltx-2-dev \
        https://github.com/AkaneTendo25/musubi-tuner.git \
        /musubi-tuner

# Config accelerate bf16 préconfigurée
RUN mkdir -p /root/.cache/huggingface/accelerate && \
    printf 'compute_environment: LOCAL_MACHINE\ndistributed_type: "NO"\ndowncast_bf16: "no"\nmachine_rank: 0\nmain_training_function: main\nmixed_precision: bf16\nnum_machines: 1\nnum_processes: 1\nrdzv_backend: static\nsame_network: true\ntpu_use_cluster: false\ntpu_use_sudo: false\nuse_cpu: false\n' \
    > /root/.cache/huggingface/accelerate/default_config.yaml

# ================================================================
#  5. DOSSIERS
# ================================================================
RUN mkdir -p \
    /comfyui/models/diffusion_models/ltxGGUF \
    /comfyui/models/text_encoders/gemma-3-12b-it-qat-q4_0-unquantized \
    /comfyui/models/vae \
    /comfyui/models/latent_upscale_models \
    /comfyui/models/loras \
    /musubi-tuner/models \
    /musubi-tuner/dataset

# ================================================================
#  6. SCRIPTS
# ================================================================
COPY entrypoint.sh /entrypoint.sh
COPY patch_vrgdg.sh /patch_vrgdg.sh
RUN chmod +x /entrypoint.sh /patch_vrgdg.sh

EXPOSE 8188 6006 8888

ENTRYPOINT ["/entrypoint.sh"]
