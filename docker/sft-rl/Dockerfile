# ============================================
# DeepAnalyze SFT/RL Training Environment
# CUDA 12.4 + ms-swift + SkyRL + vLLM
# ============================================

FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_ENDPOINT=https://hf-mirror.com

# Optional: pass --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple to accelerate pip
ARG PIP_INDEX_URL=
ENV PIP_INDEX_URL=${PIP_INDEX_URL}

WORKDIR /workspace

# System dependencies
RUN apt-get update && apt-get install -y \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    git \
    curl \
    wget \
    vim \
    tmux \
    htop \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.12 1

# Upgrade pip
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# vLLM (brings PyTorch + CUDA as dependencies)
RUN pip3 install vllm

# ms-swift for SFT
RUN pip3 install 'ms-swift' modelscope transformers accelerate datasets peft wandb

# SkyRL for RL — clone and install unified skyrl package + skyrl-gym
RUN git clone https://github.com/NovaSky-AI/SkyRL.git /opt/SkyRL \
    && cd /opt/SkyRL/skyrl-gym && pip3 install -e . \
    && cd /opt/SkyRL && pip3 install -e '.[skyrl-train]'

# DeepSpeed (ZeRO / distributed) + Liger Kernel (fused ops for training)
RUN pip3 install deepspeed liger-kernel

# Common data science tools
RUN pip3 install pandas numpy scikit-learn matplotlib seaborn

# Flash attention — pre-built wheel matching vLLM's PyTorch 2.10 + CUDA 12 + Python 3.12
RUN wget -q https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.1/flash_attn-2.8.1%2Bcu12torch2.10cxx11abiTRUE-cp312-cp312-linux_x86_64.whl \
    && pip3 install flash_attn-2.8.1+cu12torch2.10cxx11abiTRUE-cp312-cp312-linux_x86_64.whl \
    && rm flash_attn-2.8.1+cu12torch2.10cxx11abiTRUE-cp312-cp312-linux_x86_64.whl

EXPOSE 8000

CMD ["/bin/bash"]
