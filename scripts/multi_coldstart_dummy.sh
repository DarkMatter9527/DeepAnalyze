#!/usr/bin/env bash

# 遇到错误立即退出，未定义变量被引用时也报错，并保证管道中的任一失败都会退出
set -euo pipefail

# 阶段2：多能力冷启动 SFT（在阶段1单能力模型基础上继续训练）
# 输入：阶段1 best checkpoint（single_dummy.sh 产出）
# 数据集：DataScience-Instruct-500K 中多能力子集（各 1000 条）
# 使用 packing false，保证数据量不大时也有足够 step，否则打包后可能仅 1 步就结束且无 best

# 设置可见的 GPU，仅使用 0 号卡
export CUDA_VISIBLE_DEVICES=0
# 每节点进程数为 1
export NPROC_PER_NODE=1
# 分布式训练端口（与 single_dummy 的 MASTER_PORT 错开）
export MASTER_PORT=12346

# 阶段1 输出目录（需先成功跑完 single_dummy.sh，路径与 single_dummy.sh 一致）
MODEL_SINGLE_ABILITY_PATH="/workspace/models/Qwen3-0.6B-extend-sft-dummy"
# 阶段2 输出模型路径（多能力冷启动 SFT）
MODEL_MULTI_ABILITY_PATH="/workspace/models/Qwen3-0.6B-extend-multi-dummy"

# 数据集根目录（与 single_dummy.sh 一致）
DATA_DIR="/workspace/datasets/DataScience-Instruct-500K"

# 自动解析阶段1 的 Best Checkpoint 路径
RUN_DIR=$(ls -td "${MODEL_SINGLE_ABILITY_PATH}"/v*-* 2>/dev/null | head -1)
STAGE1_BEST_CKPT=""
if [[ -n "${RUN_DIR}" && -f "${RUN_DIR}/logging.jsonl" ]]; then
  STAGE1_BEST_CKPT=$(tail -1 "${RUN_DIR}/logging.jsonl" | sed -n 's/.*"best_model_checkpoint":"\([^"]*\)".*/\1/p')
fi
if [[ -z "${STAGE1_BEST_CKPT}" && -n "${RUN_DIR}" ]]; then
  STAGE1_BEST_CKPT=$(ls -d "${RUN_DIR}"/checkpoint-* 2>/dev/null | head -1)
fi
if [[ -z "${STAGE1_BEST_CKPT}" || ! -d "${STAGE1_BEST_CKPT}" ]]; then
  echo "[ERROR] 未找到阶段1的 Best Checkpoint，请先成功运行 scripts/single_dummy.sh"
  exit 1
fi
echo "[INFO] 阶段2 使用阶段1 Best Checkpoint: ${STAGE1_BEST_CKPT}"

# 使用 swift 工具运行 SFT（全量训练）。行尾续写只能用「\」且其后不能再有字符（含空格与行内 #），否则续行会断。
# 参数概要：从阶段1 best 起训；多数据集各 1000 条；bfloat16；1 epoch；batch 1；lr 5e-6；grad accum 8；
# packing false；验证集 5%；eval/save 每 10 步；按 loss 选 best；最多 2 个 ckpt；仅存模型；max_length 4096；
# 无 warmup；dataloader workers 0；tensorboard；deepspeed zero2；liger；flash_attn；model_type / template qwen3。
swift sft \
  --model "${STAGE1_BEST_CKPT}" \
  --train_type "full" \
  --dataset \
    "${DATA_DIR}/interation/data_pipeline_3601.json#1000" \
    "${DATA_DIR}/interation/data_preparation_3311.json#1000" \
  --torch_dtype "bfloat16" \
  --num_train_epochs 1 \
  --per_device_train_batch_size 1 \
  --per_device_eval_batch_size 1 \
  --learning_rate 5e-6 \
  --gradient_accumulation_steps 8 \
  --packing false \
  --split_dataset_ratio 0.05 \
  --eval_steps 10 \
  --save_steps 10 \
  --metric_for_best_model loss \
  --save_total_limit 2 \
  --save_only_model true \
  --logging_steps 1 \
  --max_length 4096 \
  --warmup_ratio 0.0 \
  --dataloader_num_workers 0 \
  --dataset_num_proc 1 \
  --response_prefix "" \
  --report_to tensorboard \
  --output_dir "${MODEL_MULTI_ABILITY_PATH}" \
  --deepspeed "zero2" \
  --use_liger_kernel true \
  --attn_impl "flash_attn" \
  --model_type "qwen3" \
  --template "qwen3"

# 仅保留 Best Checkpoint：删除同次运行中的其它 checkpoint
if [[ -d "${MODEL_MULTI_ABILITY_PATH}" ]]; then
  # 取最新一次训练 run 目录（如 v1-20240602-xxxxxx）
  RUN_DIR=$(ls -td "${MODEL_MULTI_ABILITY_PATH}"/v*-* 2>/dev/null | head -1)
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
#   tensorboard --logdir "${MODEL_MULTI_ABILITY_PATH}" --port 6006
# 远程访问需监听所有网卡:  tensorboard --logdir "${MODEL_MULTI_ABILITY_PATH}" --port 6006 --bind_all
# 然后浏览器打开 http://localhost:6006（或映射后的公网地址）
