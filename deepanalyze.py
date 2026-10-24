"""
DeepAnalyze 客户端：通过 vLLM 兼容的 Chat Completions API 多轮对话，
解析模型输出中的 <Code> 块并在工作区内执行，直到出现 <Answer> 或达到轮数上限。
"""
import re
import io
import traceback
import contextlib
import os
import requests
from pathlib import Path


class DeepAnalyzeVLLM:
    """
    封装 vLLM API 调用：多轮推理、提取并执行 <Code>、将执行结果以 execute 角色回传。
    """

    def __init__(
        self,
        model_name: str,
        api_url: str = "http://localhost:8000/v1/chat/completions",
        max_rounds: int = 30,
    ):
        self.model_name = model_name
        self.api_url = api_url
        self.max_rounds = max_rounds

    def execute_code(self, code_str: str) -> str:
        """
        在独立全局命名空间中 exec 一段 Python 代码，捕获 stdout/stderr。
        成功时返回合并输出；异常时返回格式化的 [Error] 信息与 traceback 片段。
        """
        stdout_capture = io.StringIO()
        stderr_capture = io.StringIO()

        try:
            # 重定向标准输出/错误，避免污染调用方控制台
            with contextlib.redirect_stdout(stdout_capture), contextlib.redirect_stderr(
                stderr_capture
            ):
                exec(code_str, {})
            output = stdout_capture.getvalue()
            if stderr_capture.getvalue():
                output += stderr_capture.getvalue()
            return output
        except Exception as exec_error:
            code_lines = code_str.splitlines()
            tb_lines = traceback.format_exc().splitlines()
            error_line = None

            # 从 traceback 中解析 "<string>" 对应的行号，便于在错误信息里高亮源码行
            for line in tb_lines:
                if 'File "<string>", line' in line:
                    try:
                        line_num = int(line.split(", line ")[1].split(",")[0])
                        error_line = line_num
                        break
                    except (IndexError, ValueError):
                        continue

            # 拼装与 CPython 风格接近的简短错误展示，便于模型下一轮修正代码
            error_message = "Traceback (most recent call last):\n"
            if error_line and 1 <= error_line <= len(code_lines):
                error_message += f'  File "<string>", line {error_line}, in <module>\n'
                error_message += f"    {code_lines[error_line - 1].strip()}\n"
            error_message += f"{type(exec_error).__name__}: {str(exec_error)}"
            if stderr_capture.getvalue():
                error_message += f"\n{stderr_capture.getvalue()}"
            return f"[Error]:\n{error_message.strip()}"

    def generate(
        self,
        prompt: str,
        workspace: str,
        temperature: float = 0.5,
        max_tokens: int = 32768,
        top_p: float = None,
        top_k: int = None,
    ) -> dict:
        """
        在工作目录 workspace 下多轮请求 vLLM；遇到 <Code> 则执行并把结果写入对话。
        当某轮回复含 <Answer> 时结束循环。返回 {"reasoning": 拼接后的完整文本}。
        """
        original_cwd = os.getcwd()
        os.chdir(workspace)
        reasoning = ""
        messages = [{"role": "user", "content": prompt}]
        response_message = []

        try:
            for round_idx in range(self.max_rounds):
                # stop 在 </Code> 处截断，由服务端在生成到闭合标签前停止
                payload = {
                    "model": self.model_name,
                    "messages": messages,
                    "temperature": temperature,
                    "max_tokens": max_tokens,
                    "add_generation_prompt": False,
                    "stop": ["</Code>"],
                }
                if top_p is not None:
                    payload["top_p"] = top_p
                if top_k is not None:
                    payload["top_k"] = top_k

                response = requests.post(
                    self.api_url,
                    headers={"Content-Type": "application/json"},
                    json=payload,
                )
                response.raise_for_status()
                response_data = response.json()

                ans = response_data["choices"][0]["message"]["content"]
                # 因 stop 序列被吃掉，需手动补回闭合标签，便于正则匹配整段 <Code>...</Code>
                if response_data["choices"][0].get("stop_reason") == "</Code>":
                    ans += "</Code>"

                response_message.append(ans)

                if "<Answer>" in ans:
                    break

                code_match = re.search(r"<Code>(.*?)</Code>", ans, re.DOTALL)
                if not code_match:
                    # 仅有 <Analyze> 等中间步骤：继续对话，等待后续轮次产出 <Code>
                    messages.append({"role": "assistant", "content": ans})
                    continue

                code_content = code_match.group(1).strip()
                # 支持模型在 <Code> 内用 markdown 代码块包裹源码
                md_match = re.search(r"```(?:python)?(.*?)```", code_content, re.DOTALL)
                code_str = md_match.group(1).strip() if md_match else code_content

                exe_output = self.execute_code(code_str)
                response_message.append(f"<Execute>\n{exe_output}\n</Execute>")

                messages.append({"role": "assistant", "content": ans})
                # execute 角色：把运行结果作为下一轮 user/工具侧上下文（依服务端约定）
                messages.append({"role": "execute", "content": exe_output})

            reasoning = "\n".join(response_message)

        except Exception:
            # 请求失败等：仍返回已收集的部分 reasoning，避免整段丢失
            reasoning = "\n".join(response_message)

        os.chdir(original_cwd)
        return {"reasoning": reasoning}
