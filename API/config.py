"""
DeepAnalyze API 服务的配置模块
包含所有配置常量及环境设定
"""

import os

# 环境变量设置：防止 matplotlib 在无界面环境下报错
os.environ.setdefault("MPLBACKEND", "Agg")

# API 配置
API_BASE = "http://localhost:8000/v1"            # vLLM API 端点
MODEL_PATH = "DeepAnalyze-8B"                    # 模型路径或名称
WORKSPACE_BASE_DIR = "workspace"                 # 工作区基础目录
HTTP_SERVER_PORT = 8100                          # 文件传输 HTTP 服务器端口
HTTP_SERVER_BASE = f"http://localhost:{HTTP_SERVER_PORT}"  # HTTP 服务器基础 URL

# API 服务本身配置
API_HOST = "0.0.0.0"                             # 监听所有网络接口
API_PORT = 8200                                  # API 服务端口
API_TITLE = "DeepAnalyze OpenAI-Compatible API"  # API 标题
API_VERSION = "1.0.0"                            # API 版本号

# 线程清理相关配置
CLEANUP_TIMEOUT_HOURS = 12                       # 工作区最大保留时长（小时）
CLEANUP_INTERVAL_MINUTES = 30                    # 清理线程检查间隔（分钟）

# 代码执行相关参数
CODE_EXECUTION_TIMEOUT = 120                     # 用户代码最大执行时间（秒）
MAX_NEW_TOKENS = 32768                           # 输出最大 token 数限制

# 文件存储/管理相关配置
FILE_STORAGE_DIR = os.path.join(WORKSPACE_BASE_DIR, "_files")   # 全局文件存储目录
VALID_FILE_PURPOSES = ["fine-tune", "answers", "file-extract", "assistants"]  # 允许用途分类

# 模型工作参数
DEFAULT_TEMPERATURE = 0.4                        # 默认采样温度
DEFAULT_MODEL = "DeepAnalyze-8B"                 # 默认模型

# DeepAnalyze 特定的终止 token ID（控制输出停止）
STOP_TOKEN_IDS = [151676, 151645]

# 支持的工具名称
SUPPORTED_TOOLS = ["code_interpreter"]