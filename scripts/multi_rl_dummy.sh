#!/usr/bin/env bash

# Bash 安全模式：
# -e：任意命令返回非 0 时立即退出，避免错误被吞掉后继续训练。
# -u：引用未定义变量时报错，避免路径或参数拼错后变成空字符串。
# -o pipefail：管道中任一命令失败都算失败，避免只看最后一个命令的退出码。
set -euo pipefail

# 根据脚本位置定位仓库根目录，避免依赖当前 shell 必须 cd 到 /workspace/DeepAnalyze。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ==============================================================================
# 阶段3：RL 强化学习（GRPO）dummy 试跑脚本
# ==============================================================================
# 用途：
#   在阶段2多能力冷启动 SFT 模型的基础上，启动 SkyRL 的 GRPO 训练。
#   这个 dummy 脚本使用更小的数据、batch 和序列长度，目的是快速验证 RL 全链路：
#   数据读取 -> vLLM 生成 -> DeepAnalyze 环境交互 -> policy 训练 -> checkpoint/export。
#
# 输入：
#   阶段2 best checkpoint，由 scripts/multi_coldstart_dummy.sh 产出。
#
# 输出：
#   FINAL_MODEL_PATH 下的 RL checkpoint 和导出模型。
#
# 资源：
#   默认使用 2 张 GPU。正式脚本 multi_rl.sh 通常按 8 卡配置；这里缩小规模便于本地/容器试跑。

# 指定本次训练能看到哪些 GPU。dummy 默认使用 0、1 两张卡。
export CUDA_VISIBLE_DEVICES=0,1
# 单机使用的 GPU 数。通常应等于 CUDA_VISIBLE_DEVICES 里的 GPU 个数。
# policy、ref 和 vLLM 推理引擎数量都会复用这个值。
export NPROC_PER_NODE=2
# 分布式训练通信端口。和阶段2 dummy 脚本错开，减少端口冲突。
export MASTER_PORT=12347
# 启用 vLLM V1 推理后端。本项目已适配对应的权重同步逻辑。
export VLLM_USE_V1=1

# 阶段2 SFT 输出目录。需先跑完 scripts/multi_coldstart_dummy.sh。
# 目录里通常包含 v*-时间戳/checkpoint-*；如果 /workspace 不存在，会自动回退到 /root。
DEFAULT_MODEL_MULTI_ABILITY_PATH="/workspace/models/Qwen3-0.6B-extend-multi-dummy"
if [[ ! -d "${DEFAULT_MODEL_MULTI_ABILITY_PATH}" && -d "/root/models/Qwen3-0.6B-extend-multi-dummy" ]]; then
  DEFAULT_MODEL_MULTI_ABILITY_PATH="/root/models/Qwen3-0.6B-extend-multi-dummy"
fi
MODEL_MULTI_ABILITY_PATH="${MODEL_MULTI_ABILITY_PATH:-${DEFAULT_MODEL_MULTI_ABILITY_PATH}}"

# 阶段3 RL 输出目录。主要包含：
#   ckpt/        SkyRL checkpoint，可用于续训或恢复。
#   export/      HuggingFace 格式模型，可用于后续推理和评测。
#   tensorboard/ 训练曲线日志，例如 loss、reward、KL。
DEFAULT_FINAL_MODEL_PATH="/workspace/models/Qwen3-0.6B-extend-rl-dummy"
if [[ ! -d "/workspace/models" && -d "/root/models" ]]; then
  DEFAULT_FINAL_MODEL_PATH="/root/models/Qwen3-0.6B-extend-rl-dummy"
fi
FINAL_MODEL_PATH="${FINAL_MODEL_PATH:-${DEFAULT_FINAL_MODEL_PATH}}"

# 保存频率。dummy 默认只保留最终结果，避免频繁写大模型占满磁盘。
# interval 设得远大于 dummy 总 step 数时，中途基本不保存，只在结束时保存一次。
# 如需更频繁保存，可在启动前覆盖，例如：
#   RL_CKPT_INTERVAL=10 RL_HF_SAVE_INTERVAL=10 bash scripts/multi_rl_dummy.sh
RL_CKPT_INTERVAL="${RL_CKPT_INTERVAL:-100000}"
RL_HF_SAVE_INTERVAL="${RL_HF_SAVE_INTERVAL:-100000}"
RL_MAX_CKPTS_TO_KEEP="${RL_MAX_CKPTS_TO_KEEP:-1}"

# 训练和生成规模。下面的默认值适合 2 张 48GB 级别显卡的 dummy 试跑。
# 遇到 OOM 时，优先调小：
#   1. RL_MICRO_TRAIN_BATCH_SIZE_PER_GPU，例如从 4 降到 2。
#   2. RL_GENERATOR_GPU_MEMORY_UTILIZATION，例如从 0.72 降到 0.65。
# 参数含义：
#   RL_TRAIN_BATCH_SIZE                  全局训练 batch size。
#   RL_POLICY_MINI_BATCH_SIZE            GRPO/PPO 更新时的 mini-batch size。
#   RL_MICRO_FORWARD_BATCH_SIZE_PER_GPU  每张 GPU 做 logprob/前向时的 micro batch。
#   RL_MICRO_TRAIN_BATCH_SIZE_PER_GPU    每张 GPU 反向训练时的 micro batch。
#   RL_GENERATOR_GPU_MEMORY_UTILIZATION  vLLM 可使用的显存比例，越大吞吐越高但越容易 OOM。
#   RL_GENERATOR_MAX_NUM_SEQS            vLLM 同时处理的最大序列数。
#   RL_GENERATOR_MAX_INPUT_LENGTH        vLLM 输入上下文最大长度。
#   RL_MAX_GENERATE_LENGTH               每次 rollout 最多生成多少 token。
#   RL_MAX_TURNS                         环境交互最多轮数。
#   RL_GENERATOR_STOP_STRINGS            生成遇到这些字符串时提前停止。
RL_TRAIN_BATCH_SIZE="${RL_TRAIN_BATCH_SIZE:-32}"
RL_POLICY_MINI_BATCH_SIZE="${RL_POLICY_MINI_BATCH_SIZE:-32}"
RL_MICRO_FORWARD_BATCH_SIZE_PER_GPU="${RL_MICRO_FORWARD_BATCH_SIZE_PER_GPU:-8}"
RL_MICRO_TRAIN_BATCH_SIZE_PER_GPU="${RL_MICRO_TRAIN_BATCH_SIZE_PER_GPU:-4}"
RL_GENERATOR_GPU_MEMORY_UTILIZATION="${RL_GENERATOR_GPU_MEMORY_UTILIZATION:-0.72}"
RL_GENERATOR_MAX_NUM_SEQS="${RL_GENERATOR_MAX_NUM_SEQS:-64}"
RL_GENERATOR_MAX_INPUT_LENGTH="${RL_GENERATOR_MAX_INPUT_LENGTH:-4096}"
RL_MAX_GENERATE_LENGTH="${RL_MAX_GENERATE_LENGTH:-4096}"
RL_MAX_TURNS="${RL_MAX_TURNS:-4}"
RL_GENERATOR_STOP_STRINGS="${RL_GENERATOR_STOP_STRINGS:-[\"</Answer>\",\"</Code>\"]}"

# dummy 数据量。默认只取前 64 条生成临时 parquet，足够跑通：
# rollout -> 环境交互 -> logprob -> policy update -> checkpoint/export。
# 设为 0 表示使用全量数据；
# RL_FORCE_DEEPANALYZE_FORMAT=true 时，会给 prompt 追加 <Analyze>/<Answer> 格式要求，
# 这样更容易满足 DeepAnalyze reward 的输出格式。
RL_DUMMY_NUM_SAMPLES="${RL_DUMMY_NUM_SAMPLES:-64}"
RL_FORCE_DEEPANALYZE_FORMAT="${RL_FORCE_DEEPANALYZE_FORMAT:-true}"

# 最小剩余磁盘空间。保存 FSDP checkpoint 和 HF export 通常需要数 GB。
# 如果空间不足，torch.save 可能报 basic_ios 或 unexpected pos 之类的写入错误。
RL_MIN_FREE_GB="${RL_MIN_FREE_GB:-8}"

# TensorBoard 日志目录。固定写到 RL 输出目录下，便于后续查看训练曲线。
export TENSORBOARD_DIR="${FINAL_MODEL_PATH}/tensorboard"

# 数据集根目录，需要包含：
#   RL/qa.parquet       本 dummy 脚本使用的 RL 训练数据。
#   RL/data/            DeepAnalyze 环境运行所需的 workspace 数据。
DEFAULT_DATA_DIR="/workspace/datasets/DataScience-Instruct-500K"
if [[ ! -d "${DEFAULT_DATA_DIR}" && -d "/root/datasets/DataScience-Instruct-500K" ]]; then
  DEFAULT_DATA_DIR="/root/datasets/DataScience-Instruct-500K"
fi
DATA_DIR="${DATA_DIR:-${DEFAULT_DATA_DIR}}"

# ==============================================================================
# 自动解析阶段2的 Best Checkpoint
# ==============================================================================
# multi_coldstart_dummy.sh 使用 swift sft 训练后，会在 MODEL_MULTI_ABILITY_PATH 下生成
# v*-时间戳 形式的 run 目录，例如：
#   /workspace/models/Qwen3-0.6B-extend-multi-dummy/v0-20260405-095908
#
# 解析顺序：
#   1. 从新到旧遍历 run 目录，跳过失败后残留但没有 checkpoint 的空 run。
#   2. 优先读取 logging.jsonl 最后一行的 best_model_checkpoint 字段。
#   3. 如果日志里没有 best_model_checkpoint，则退化为使用该 run 下编号最大的 checkpoint-*。
#   4. 两种方式都失败时直接退出，避免误从空路径启动 RL。
STAGE2_BEST_CKPT=""
RUN_DIRS=$(find "${MODEL_MULTI_ABILITY_PATH}" -maxdepth 1 -type d -name 'v*-*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2- || true)
while IFS= read -r RUN_DIR; do
  [[ -z "${RUN_DIR}" ]] && continue

  if [[ -f "${RUN_DIR}/logging.jsonl" ]]; then
    # swift 的 logging.jsonl 中通常会记录 best_model_checkpoint。
    # 这里只取最后一行，是因为最后一次记录一般包含最终选出的 best checkpoint。
    STAGE2_BEST_CKPT=$(tail -1 "${RUN_DIR}/logging.jsonl" | sed -n 's/.*"best_model_checkpoint":"\([^"]*\)".*/\1/p')

    # 如果日志里记录的是旧挂载路径（如 /workspace/models），但当前容器实际在 /root/models，
    # 则把路径映射到当前存在的位置。
    if [[ -n "${STAGE2_BEST_CKPT}" && ! -d "${STAGE2_BEST_CKPT}" && "${STAGE2_BEST_CKPT}" == /workspace/models/* ]]; then
      ALT_CKPT="/root/models/${STAGE2_BEST_CKPT#/workspace/models/}"
      if [[ -d "${ALT_CKPT}" ]]; then
        STAGE2_BEST_CKPT="${ALT_CKPT}"
      fi
    fi
  fi

  if [[ -z "${STAGE2_BEST_CKPT}" || ! -d "${STAGE2_BEST_CKPT}" ]]; then
    # 兜底逻辑：如果没有 best 字段或 best 路径失效，就选该 run 下编号最大的 checkpoint。
    # dummy 场景主要用于打通流程，因此这里允许退化选择。
    STAGE2_BEST_CKPT=$(find "${RUN_DIR}" -maxdepth 1 -type d -name 'checkpoint-*' 2>/dev/null | sort -V | tail -1 || true)
  fi

  if [[ -n "${STAGE2_BEST_CKPT}" && -d "${STAGE2_BEST_CKPT}" ]]; then
    break
  fi
done <<< "${RUN_DIRS}"

if [[ -z "${STAGE2_BEST_CKPT}" || ! -d "${STAGE2_BEST_CKPT}" ]]; then
  echo "[ERROR] 未找到阶段2的 Best Checkpoint，请检查 MODEL_MULTI_ABILITY_PATH=${MODEL_MULTI_ABILITY_PATH}"
  echo "[ERROR] 已扫描到的阶段2 run 目录如下："
  if [[ -n "${RUN_DIRS}" ]]; then
    while IFS= read -r RUN_DIR; do
      [[ -z "${RUN_DIR}" ]] && continue
      CHECKPOINT_COUNT=$(find "${RUN_DIR}" -maxdepth 1 -type d -name 'checkpoint-*' 2>/dev/null | wc -l)
      echo "  - ${RUN_DIR} (checkpoint 数量: ${CHECKPOINT_COUNT})"
    done <<< "${RUN_DIRS}"
  else
    echo "  - 未扫描到 v*-* run 目录"
  fi
  echo "[ERROR] 如尚未生成阶段2模型，请先成功运行 scripts/multi_coldstart_dummy.sh"
  exit 1
fi
echo "[INFO] 阶段3 使用阶段2 Best Checkpoint: ${STAGE2_BEST_CKPT}"

mkdir -p "${FINAL_MODEL_PATH}"
AVAILABLE_KB=$(df -Pk "${FINAL_MODEL_PATH}" | awk 'NR==2 {print $4}')
REQUIRED_KB=$((RL_MIN_FREE_GB * 1024 * 1024))
if (( AVAILABLE_KB < REQUIRED_KB )); then
  AVAILABLE_GB=$(awk -v kb="${AVAILABLE_KB}" 'BEGIN {printf "%.2f", kb / 1024 / 1024}')
  echo "[ERROR] ${FINAL_MODEL_PATH} 所在分区剩余空间不足：${AVAILABLE_GB}GB，可用空间需 >= ${RL_MIN_FREE_GB}GB。"
  echo "[ERROR] 当前报错中的 torch.save basic_ios/unexpected pos 通常就是磁盘或挂载 I/O 写入失败导致。"
  echo "[ERROR] 请先清理旧的 RL dummy 输出，例如确认不需要后删除："
  echo "        rm -rf \"${FINAL_MODEL_PATH}/ckpt\" \"${FINAL_MODEL_PATH}/export\""
  echo "[ERROR] 或把 FINAL_MODEL_PATH 指到空间充足的磁盘后重跑。"
  exit 1
fi
echo "[INFO] RL 输出目录: ${FINAL_MODEL_PATH}"
echo "[INFO] 保存策略: ckpt_interval=${RL_CKPT_INTERVAL}, hf_save_interval=${RL_HF_SAVE_INTERVAL}, max_ckpts_to_keep=${RL_MAX_CKPTS_TO_KEEP}"
echo "[INFO] 显存利用参数: train_batch=${RL_TRAIN_BATCH_SIZE}, policy_mini_batch=${RL_POLICY_MINI_BATCH_SIZE}, micro_forward/gpu=${RL_MICRO_FORWARD_BATCH_SIZE_PER_GPU}, micro_train/gpu=${RL_MICRO_TRAIN_BATCH_SIZE_PER_GPU}, vllm_gpu_mem=${RL_GENERATOR_GPU_MEMORY_UTILIZATION}, max_num_seqs=${RL_GENERATOR_MAX_NUM_SEQS}, max_input_length=${RL_GENERATOR_MAX_INPUT_LENGTH}, max_generate_length=${RL_MAX_GENERATE_LENGTH}, max_turns=${RL_MAX_TURNS}, stop=${RL_GENERATOR_STOP_STRINGS}"
echo "[INFO] DeepAnalyze 格式提示: RL_FORCE_DEEPANALYZE_FORMAT=${RL_FORCE_DEEPANALYZE_FORMAT}"

SOURCE_TRAIN_DATA_PATH="${DATA_DIR}/RL/qa.parquet"
TRAIN_DATA_PATH="${SOURCE_TRAIN_DATA_PATH}"
if (( RL_DUMMY_NUM_SAMPLES > 0 )) || [[ "${RL_FORCE_DEEPANALYZE_FORMAT}" == "true" ]]; then
  if (( RL_DUMMY_NUM_SAMPLES < RL_TRAIN_BATCH_SIZE )); then
    if (( RL_DUMMY_NUM_SAMPLES > 0 )); then
      echo "[ERROR] RL_DUMMY_NUM_SAMPLES=${RL_DUMMY_NUM_SAMPLES} 小于 train_batch_size=${RL_TRAIN_BATCH_SIZE}，SkyRL 要求训练集至少有一个完整 batch。"
      echo "[ERROR] 请增大 RL_DUMMY_NUM_SAMPLES，或降低 RL_TRAIN_BATCH_SIZE。"
      exit 1
    fi
  fi

  DUMMY_DATA_DIR="${FINAL_MODEL_PATH}/dummy_data"
  if (( RL_DUMMY_NUM_SAMPLES > 0 )); then
    TRAIN_DATA_PATH="${DUMMY_DATA_DIR}/qa_first_${RL_DUMMY_NUM_SAMPLES}.parquet"
  else
    TRAIN_DATA_PATH="${DUMMY_DATA_DIR}/qa_full_format.parquet"
  fi
  mkdir -p "${DUMMY_DATA_DIR}"
  python - "${SOURCE_TRAIN_DATA_PATH}" "${TRAIN_DATA_PATH}" "${RL_DUMMY_NUM_SAMPLES}" "${RL_FORCE_DEEPANALYZE_FORMAT}" <<'PY'
import sys
import pyarrow.parquet as pq

src, dst, limit, force_format = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4].lower() == "true"
table = pq.read_table(src)
subset = table if limit <= 0 else table.slice(0, min(limit, table.num_rows))
if force_format:
    import pyarrow as pa

    format_hint = (
        "\n\n## Required response format\n"
        "You must respond using exactly these XML-style sections:\n"
        "<Analyze>\n"
        "Briefly reason about the task. Keep this concise.\n"
        "</Analyze>\n"
        "<Answer>\n"
        "Put the final answer here. For SQL tasks, include only the final SQL query in a ```sql ...``` block.\n"
        "</Answer>\n"
        "Stop immediately after </Answer>. Do not continue with extra explanation."
    )
    prompt_col = subset.column("prompt").to_pylist()
    patched_prompts = []
    for prompt in prompt_col:
        patched_messages = []
        for message in prompt:
            message = dict(message)
            if message.get("role") == "user" and format_hint not in message.get("content", ""):
                message["content"] = message.get("content", "") + format_hint
            patched_messages.append(message)
        patched_prompts.append(patched_messages)
    prompt_idx = subset.schema.get_field_index("prompt")
    subset = subset.set_column(prompt_idx, "prompt", pa.array(patched_prompts, type=subset.schema.field("prompt").type))
pq.write_table(subset, dst)
print(f"[INFO] dummy 训练数据: {dst} ({subset.num_rows}/{table.num_rows} rows, force_format={force_format})")
PY
else
  echo "[INFO] dummy 训练数据: ${TRAIN_DATA_PATH} (full dataset)"
fi

# 推理后端。
# 当前使用 vLLM 作为 rollout/generation engine；SkyRL 也支持其它后端，但本项目脚本按 vLLM 配置。
INFERENCE_BACKEND="vllm"

# 在 ./deepanalyze/SkyRL/skyrl-train/ 下执行。
# 注意：行尾续写符「\」后面不能有空格或行内注释，否则下一行不会接上。
#
# 下面的 python 命令使用 Hydra override 覆盖 SkyRL 默认配置。
# 可以把它理解成几组参数：
#
# 1. 训练算法与轮数
#   trainer.algorithm.advantage_estimator=grpo
#     使用 GRPO，不需要额外训练 critic/value model。
#   trainer.epochs=1
#     dummy 只训练 1 个 epoch，用来验证流程是否能跑通。
#
# 2. 数据与初始模型
#   data.train_data
#     本次 RL 使用的 parquet 数据文件。
#   trainer.policy.model.path
#     policy 的初始权重，来自阶段2自动解析出的 best checkpoint。
#
# 3. 分布式与显存策略
#   trainer.placement.colocate_all=true
#     policy、ref、generator 尽量共享同一组本机 GPU 资源，适合单机 dummy。
#   trainer.strategy=fsdp2
#     使用 PyTorch FSDP2 做分布式训练。
#   trainer.policy.fsdp_config.cpu_offload=false
#     policy 需要反向传播，dummy 默认不 offload 到 CPU，避免梯度裁剪时的后端错误。
#   trainer.ref.fsdp_config.cpu_offload=true
#     ref model 只算参考 logprob，不训练；offload 到 CPU 可以节省显存。
#
# 4. batch 与长度
#   trainer.train_batch_size
#     全局训练 batch size。
#   trainer.policy_mini_batch_size
#     每次 GRPO/PPO 更新拆分出的 mini-batch size。
#   trainer.micro_forward_batch_size_per_gpu
#     每张 GPU 做前向/logprob 时一次处理多少样本。
#   trainer.micro_train_batch_size_per_gpu
#     每张 GPU 做反向训练时一次处理多少样本；OOM 时优先调小它。
#   trainer.max_prompt_length
#     训练侧允许的 prompt token 上限。
#   generator.max_input_length
#     vLLM 侧允许的输入上下文 token 上限。
#   generator.sampling_params.max_generate_length
#     每条样本最多生成多少 token。
#
# 5. vLLM rollout
#   generator.num_inference_engines
#     vLLM 推理引擎数量，这里与 GPU 数一致。
#   generator.weight_sync_backend=nccl
#     policy 更新后用 NCCL 把新权重同步给 vLLM。
#   generator.async_engine=true
#     使用异步推理引擎，提高 rollout 调度效率。
#   generator.batched=false
#     dummy 关闭 batched generation，行为更直观，便于排查。
#   generator.n_samples_per_prompt=2
#     每个 prompt 生成 2 个候选，用于 GRPO 比较不同回答的 reward。
#
# 6. 环境、日志与保存
#   environment.env_class=deepanalyze
#     使用项目自定义的 DeepAnalyze 环境计算交互和 reward。
#   trainer.logger=["console","tensorboard"]
#     日志同时输出到终端和 TensorBoard。
#   trainer.resume_mode=null
#     每次从阶段2 checkpoint 重新开始，不自动续训旧的 RL checkpoint。
#   trainer.ckpt_path / trainer.export_path
#     分别保存 SkyRL checkpoint 和 HuggingFace export 模型。

cd "${REPO_ROOT}/deepanalyze/SkyRL/skyrl-train"

# 清理上一次失败后可能残留的 Ray runtime，确保新的环境变量传给 worker。
# 如果不清理，Ray worker 可能复用旧进程，导致 CUDA_VISIBLE_DEVICES、端口或 vLLM 配置不生效。
ray stop --force >/dev/null 2>&1 || true

python -m examples.deepanalyze.main_deepanalyze \
  trainer.algorithm.advantage_estimator="grpo" \
  trainer.epochs=1 \
  data.train_data="[\"${TRAIN_DATA_PATH}\"]" \
  trainer.policy.model.path="${STAGE2_BEST_CKPT}" \
  trainer.placement.colocate_all=true \
  trainer.strategy="fsdp2" \
  trainer.policy.fsdp_config.cpu_offload=false \
  trainer.ref.fsdp_config.cpu_offload=true \
  trainer.placement.policy_num_gpus_per_node=${NPROC_PER_NODE} \
  trainer.placement.ref_num_gpus_per_node=${NPROC_PER_NODE} \
  generator.num_inference_engines=${NPROC_PER_NODE} \
  generator.inference_engine_tensor_parallel_size=1 \
  trainer.train_batch_size=${RL_TRAIN_BATCH_SIZE} \
  trainer.micro_forward_batch_size_per_gpu=${RL_MICRO_FORWARD_BATCH_SIZE_PER_GPU} \
  trainer.micro_train_batch_size_per_gpu=${RL_MICRO_TRAIN_BATCH_SIZE_PER_GPU} \
  trainer.max_prompt_length=2048 \
  generator.max_input_length=${RL_GENERATOR_MAX_INPUT_LENGTH} \
  generator.sampling_params.max_generate_length=${RL_MAX_GENERATE_LENGTH} \
  trainer.policy.optimizer_config.lr=5e-7 \
  trainer.policy_mini_batch_size=${RL_POLICY_MINI_BATCH_SIZE} \
  trainer.algorithm.use_kl_loss=false \
  generator.backend="${INFERENCE_BACKEND}" \
  generator.run_engines_locally=true \
  generator.weight_sync_backend="nccl" \
  generator.async_engine=true \
  generator.batched=false \
  generator.use_conversation_multi_turn=false \
  generator.n_samples_per_prompt=2 \
  generator.gpu_memory_utilization=${RL_GENERATOR_GPU_MEMORY_UTILIZATION} \
  generator.max_num_seqs=${RL_GENERATOR_MAX_NUM_SEQS} \
  generator.max_turns=${RL_MAX_TURNS} \
  generator.sampling_params.temperature=0.0 \
  generator.sampling_params.top_p=0.95 \
  +generator.sampling_params.stop="${RL_GENERATOR_STOP_STRINGS}" \
  generator.sampling_params.stop_token_ids="[151676,151645]" \
  environment.env_class="deepanalyze" \
  environment.skyrl_gym.deepanalyze.workspace="${DATA_DIR}/RL/data/" \
  trainer.logger="[\"console\",\"tensorboard\"]" \
  trainer.project_name="deepanalyze_dummy" \
  trainer.run_name="deepanalyze_dummy_run" \
  trainer.resume_mode=null \
  trainer.ckpt_path="${FINAL_MODEL_PATH}/ckpt" \
  trainer.export_path="${FINAL_MODEL_PATH}/export" \
  trainer.max_ckpts_to_keep=${RL_MAX_CKPTS_TO_KEEP} \
  trainer.eval_batch_size=2 \
  trainer.eval_before_train=false \
  trainer.eval_interval=-1 \
  trainer.hf_save_interval=${RL_HF_SAVE_INTERVAL} \
  trainer.ckpt_interval=${RL_CKPT_INTERVAL}

# 训练结束后用 TensorBoard 查看曲线（在 skyrl-train 目录或任意终端执行）:
#   tensorboard --logdir "${TENSORBOARD_DIR}" --port 6006
# 远程访问需监听所有网卡:  tensorboard --logdir "${TENSORBOARD_DIR}" --port 6006 --bind_all
# 然后浏览器打开 http://localhost:6006（或映射后的公网地址）
