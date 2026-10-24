from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8200/v1",
    api_key="dummy"  # 本地部署不需要真实 key
)

# 上传文件
with open("/root/autodl-tmp/DeepAnalyze/assets/sales_data.csv", "rb") as f:
    file_obj = client.files.create(file=f, purpose="file-extract")

# 发起分析
response = client.chat.completions.create(
    model="DeepAnalyze-8B",
    messages=[
        {
            "role": "user",
            "content": "分析这份销售数据，找出关键趋势和异常",
            "file_ids": [file_obj.id]
        }
    ],
    temperature=0.4
)

print(response.choices[0].message.content)