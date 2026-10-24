# ============================================
# DeepAnalyze Docker Environment
# High-performance LLM inference with vLLM and CUDA 12.4
# ============================================

FROM nvidia/cuda:12.4.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Optional: pass --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple to accelerate pip
ARG PIP_INDEX_URL=
ENV PIP_INDEX_URL=${PIP_INDEX_URL}

WORKDIR /workspace

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    git \
    curl \
    wget \
    vim \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3 /usr/bin/python

# Node.js 20 LTS（demo/chat 前端；需已安装 curl）
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 预装 chat 前端依赖（build context 须为仓库根目录，见 docker-compose.yml context: ..）
COPY demo/chat/frontend /workspace/demo/chat/frontend
WORKDIR /workspace/demo/chat/frontend
RUN npm install
WORKDIR /workspace

# Upgrade pip
RUN pip3 install --upgrade pip

# vLLM (brings PyTorch + CUDA as dependencies)
RUN pip3 install vllm transformers accelerate fastapi uvicorn pypandoc

# Data science and analysis tools
RUN pip3 install \
    pandasql pyjanitor feature-engine missingno \
    plotly bokeh squarify matplotlib-venn wordcloud folium contextily \
    mlxtend imbalanced-learn optuna shap lime \
    prophet pmdarima tslearn lifelines \
    pymc pystan cmdstanpy pyro-ppl \
    dowhy econml causalml CausalInference zepid \
    geopandas shapely rasterio rasterstats fiona rtree \
    pysal libpysal esda giddy segregation spopt spreg spglm splot spaghetti tobler

# Expose port for API service
EXPOSE 8000

# Default command
CMD ["/bin/bash"]
