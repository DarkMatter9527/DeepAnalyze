import requests

API_BASE = "http://localhost:8200"

# 上传文件
with open("/root/autodl-tmp/DeepAnalyze/assets/sales_data.csv", "rb") as f:
    resp = requests.post(
        f"{API_BASE}/v1/files",
        files={"file": ("sales_data.csv", f, "text/csv")},
        data={"purpose": "file-extract"}
    )
file_id = resp.json()["id"]

# 发起分析
resp = requests.post(f"{API_BASE}/v1/chat/completions", json={
    "model": "DeepAnalyze-8B",
    "messages": [
        {"role": "user", "content": "生成数据科学报告", "file_ids": [file_id]}
    ],
    "temperature": 0.4
})

result = resp.json()
print(result["choices"][0]["message"]["content"])

# 查看生成的文件（图表等）
for f in result.get("generated_files", []):
    print(f"生成文件: {f['name']} → {f['url']}")