# DeepAnalyze Docker 环境

DeepAnalyze 提供两个 Docker 镜像，分别用于推理部署和模型训练。

## 镜像一览

| 镜像 | Dockerfile | 用途 | CUDA | Python | 大小 |
|------|-----------|------|------|--------|------|
| `deepanalyze-env` | `docker/inference/Dockerfile` | vLLM 推理 + 数据科学分析 | 12.4 | 3.10 | ~17 GB |
| `deepanalyze-sft-rl` | `docker/sft-rl/Dockerfile` | SFT 微调 + RL 强化学习训练 | 12.4 | 3.12 | ~20-25 GB |

## 快速开始

### 前置要求

- Docker >= 24.0
- NVIDIA GPU + NVIDIA Container Toolkit
- 磁盘空间 >= 50 GB

### 推理镜像（deepanalyze-env）

面向 DeepAnalyze 的推理部署场景，内置 vLLM 和丰富的数据科学工具包。

```bash
# 拉取
docker pull facdbe/deepanalyze-env:latest

# 运行
docker run --gpus all -it --rm \
  -p 8000:8000 \
  facdbe/deepanalyze-env:latest

# 或从源码构建
docker build -t deepanalyze-env:latest -f docker/inference/Dockerfile .
```

启动 vLLM 服务：

```bash
docker run --gpus all -d \
  -p 8000:8000 \
  -v /path/to/models:/models \
  --name deepanalyze-vllm \
  deepanalyze-env:latest \
  python3 -m vllm.entrypoints.openai.api_server \
    --model /models/your-model-name \
    --host 0.0.0.0 --port 8000
```

API 端点：

| 端点 | URL |
|------|-----|
| Chat Completions | `http://localhost:8000/v1/chat/completions` |
| Completions | `http://localhost:8000/v1/completions` |
| Models | `http://localhost:8000/v1/models` |

### 训练镜像（deepanalyze-sft-rl）

面向 SFT/RL 教学实战场景，内置 ms-swift（SFT）+ SkyRL（RL）+ vLLM（推理验证）。

```bash
# 拉取（由讲师提供具体地址）
docker pull <registry>/deepanalyze-sft-rl:latest

# 运行
docker run --gpus all -it --rm \
  -v $(pwd)/workspace:/workspace \
  -p 8000:8000 \
  --shm-size=16g \
  deepanalyze-sft-rl:latest

# 或从源码构建（需在项目根目录执行）
docker build -t deepanalyze-sft-rl:latest -f docker/sft-rl/Dockerfile .
```

详细使用方法请参考：
- 学员指南：[`docs/sft-rl-docker-guide.md`](../docs/sft-rl-docker-guide.md)
- 讲师构建指南：[`docs/instructor-docker-build-guide.md`](../docs/instructor-docker-build-guide.md)

## Docker Compose

使用 `docker-compose.yml` 可以一键管理两个服务：

```bash
cd docker

# 仅启动推理服务
docker compose up -d inference

# 仅启动训练服务
docker compose up -d sft-rl

# 启动全部
docker compose up -d

# 查看状态
docker compose ps

# 进入训练容器
docker compose exec sft-rl bash

# 停止
docker compose down
```

## 目录结构

```
docker/
├── docker-compose.yml          # 统一编排两个服务
├── README.md                   # 本文件
├── inference/
│   └── Dockerfile              # 推理镜像（CUDA 12.1 + vLLM + 数据科学工具）
└── sft-rl/
    └── Dockerfile              # 训练镜像（CUDA 12.4 + ms-swift + SkyRL）
```

项目根目录的 `.dockerignore` 对两个镜像构建均生效。
