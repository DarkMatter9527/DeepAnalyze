#!/usr/bin/env bash
# 批量上传并记录所有返回的 file_id
# 用法：在项目根目录执行 bash example/analysis_on_student_loan/run.sh

set -e
API_BASE="${API_BASE:-http://localhost:8200}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE_IDS=()
FILE_IDS_OUT="${SCRIPT_DIR}/file_ids.txt"

# 无匹配时 glob 不展开为字面量
shopt -s nullglob 2>/dev/null || true

# 当前目录 + data 子目录下的 csv/xlsx（与执行路径无关，始终相对脚本所在目录）
for f in "${SCRIPT_DIR}"/*.csv "${SCRIPT_DIR}"/*.xlsx "${SCRIPT_DIR}"/data/*.csv "${SCRIPT_DIR}"/data/*.xlsx; do
  [ -f "$f" ] || continue
  echo "上传: $f"
  resp=$(curl -sS -X POST "${API_BASE}/v1/files" \
    -F "file=@$f" \
    -F "purpose=file-extract")
  file_id=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)
  if [ -n "$file_id" ]; then
    FILE_IDS+=("$file_id")
    echo "  -> file_id: $file_id"
  else
    echo "  -> 解析失败或接口报错: $resp" >&2
  fi
done

# 输出并持久化所有 file_id（JSON 数组格式）
echo ""
echo "========== 本次上传的 file_id 列表 =========="
FILE_IDS_JSON=$(printf '%s\n' "${FILE_IDS[@]}" | python3 -c "import sys,json; ids=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(ids))")
echo "$FILE_IDS_JSON"
echo "$FILE_IDS_JSON" > "$FILE_IDS_OUT"
echo "已保存到: $FILE_IDS_OUT"
echo "共 ${#FILE_IDS[@]} 个文件"