#!/usr/bin/env bash

# 遇到错误立即退出，未定义变量被引用时也报错，并保证管道中的任一失败都会退出
set -euo pipefail

# 设置可见的 GPU，仅使用 0 号卡
export CUDA_VISIBLE_DEVICES=0
# 每节点进程数为 1
export NPROC_PER_NODE=1
# 分布式训练端口
export MASTER_PORT=12345

# 基础模型路径（Qwen3-0.6B 扩展版本）
BASE_MODEL="/workspace/models/Qwen3-0.6B-extend"
# 本次训练输出模型路径（单能力 SFT）
MODEL_SINGLE_ABILITY_PATH="/workspace/models/Qwen3-0.6B-extend-sft-dummy"

# 数据集根目录
DATA_DIR="/workspace/datasets/DataScience-Instruct-500K"

# 使用 swift 工具运行 SFT（全量训练）。行尾续写只能用「\」且其后不能再有字符（含空格与行内 #），否则续行会断。
# 参数概要：全量训练；数据集取 math_20000.json 前 2000 条；bfloat16；1 epoch；batch 1；lr 5e-5；grad accum 8；
# packing；验证集 5%；eval/save 每 10 步；按 loss 选 best；最多 2 个 ckpt；仅存模型；max_length 2048；
# 无 warmup；dataloader workers 0；tensorboard；deepspeed zero2；liger；flash_attn；model_type qwen3。
swift sft \
  --model "${BASE_MODEL}" \
  --train_type "full" \
  --dataset "${DATA_DIR}/reasoning/math_20000.json#2000" \
  --torch_dtype "bfloat16" \
  --num_train_epochs 1 \
  --per_device_train_batch_size 1 \
  --per_device_eval_batch_size 1 \
  --learning_rate 5e-5 \
  --gradient_accumulation_steps 8 \
  --packing true \
  --split_dataset_ratio 0.05 \
  --eval_steps 10 \
  --save_steps 10 \
  --metric_for_best_model loss \
  --save_total_limit 2 \
  --save_only_model true \
  --logging_steps 1 \
  --max_length 2048 \
  --warmup_ratio 0.0 \
  --dataloader_num_workers 0 \
  --dataset_num_proc 1 \
  --response_prefix "" \
  --report_to tensorboard \
  --output_dir "${MODEL_SINGLE_ABILITY_PATH}" \
  --deepspeed "zero2" \
  --use_liger_kernel true \
  --attn_impl "flash_attn" \
  --model_type "qwen3" \
  --template "qwen3"

# 仅保留 Best Checkpoint：删除同次运行中的其它 checkpoint
if [[ -d "${MODEL_SINGLE_ABILITY_PATH}" ]]; then
  # 取最新一次训练 run 目录（如 v1-20240602-xxxxxx）
  RUN_DIR=$(ls -td "${MODEL_SINGLE_ABILITY_PATH}"/v*-* 2>/dev/null | head -1)
  if [[ -n "${RUN_DIR}" && -f "${RUN_DIR}/logging.jsonl" ]]; then
    # 从日志中获取 best checkpoint 的路径
    BEST_PATH=$(tail -1 "${RUN_DIR}/logging.jsonl" | sed -n 's/.*"best_model_checkpoint":"\([^"]*\)".*/\1/p')
    if [[ -n "${BEST_PATH}" ]]; then
      BEST_NAME=$(basename "${BEST_PATH}")
      # 删除所有非 best 的 checkpoint 目录
      for d in "${RUN_DIR}"/checkpoint-*; do
        if [[ -d "${d}" && "$(basename "${d}")" != "${BEST_NAME}" ]]; then
          echo "[INFO] 仅保留 Best Checkpoint，删除: ${d}"
          rm -rf "${d}"
        fi
      done
    fi
  fi
fi

# 训练结束后用 TensorBoard 查看曲线（在项目根目录或任意终端执行）:
#   tensorboard --logdir "${MODEL_SINGLE_ABILITY_PATH}" --port 6006
# 然后浏览器打开 http://localhost:6006
