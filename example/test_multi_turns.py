import requests

API_BASE = "http://localhost:8200"  # 定义 API 基础地址

# 上传文件到服务，获取文件 ID
with open("/root/autodl-tmp/DeepAnalyze/assets/sales_data.csv", "rb") as f:
    resp = requests.post(
        f"{API_BASE}/v1/files",  # 文件上传接口
        files={"file": ("sales_data", f, "text/csv")},  # 以 multipart 形式上传文件
        data={"purpose": "file-extract"}  # 指定文件用途
    )
file_id = resp.json()["id"]  # 从接口响应中提取文件 ID

# 第一轮对话：分析文件基本结构
resp1 = requests.post(
    f"{API_BASE}/v1/chat/completions",  # 聊天接口
    json={
        "model": "DeepAnalyze-8B",  # 模型名称
        "messages": [
            {"role": "user", "content": "探索数据的基本结构", "file_ids": [file_id]}  # 用户提问并附带文件
        ]
    }
)
thread_id = resp1.json()["choices"][0]["message"]["thread_id"]  # 记录会话 thread_id，便于多轮对话追踪

# 第二轮对话：继续在同一 thread 上基于前述分析建立预测模型
resp2 = requests.post(
    f"{API_BASE}/v1/chat/completions",
    json={
        "model": "DeepAnalyze-8B",
        "messages": [
            {"role": "user", "content": "探索数据的基本结构", "file_ids": [file_id]},  # 第一轮的用户输入
            {"role": "assistant", "content": resp1.json()["choices"][0]["message"]["content"]},  # 第一轮助手回复
            {"role": "user", "content": "基于上面的分析，建立一个预测模型", "thread_id": thread_id}  # 新一轮提问，传递 thread_id 继续上下文
        ]
    }
)

print("file_id:", file_id)
print("--------------------------------")
print("thread_id:", thread_id)
print("--------------------------------")
print("round1:", resp1.json())
print("--------------------------------")
print("round2:", resp2.json())