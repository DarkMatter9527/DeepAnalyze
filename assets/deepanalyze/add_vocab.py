#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
扩展本地 Hugging Face 模型的 tokenizer，增加自定义特殊 token。

用法示例:
    python extend_tokenizer.py \
        --model_path /原始/model/路径 \
        --save_path /保存/扩展/模型的路径 \
        --add_tags

举例:
    python extend_tokenizer.py \
        --model_path ./DeepSeek-R1-0528-Qwen3-8B \
        --save_path ./DeepSeek-R1-0528-Qwen3-8B-AddTags2
"""

import os
import torch
import argparse
from transformers import AutoModelForCausalLM, AutoTokenizer

def load_and_extend_model(model_path, new_tokens=None):
    """
    加载本地 Hugging Face 模型，扩展其 tokenizer 词表，并根据需要调整模型 embedding。

    参数:
        model_path (str): 本地模型目录路径
        new_tokens (list): 要添加到 tokenizer 的新 token 列表
    """
    print(f"正在加载模型: {model_path}")
    # 加载 tokenizer
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    # 加载模型，使用 bfloat16 精度
    model = AutoModelForCausalLM.from_pretrained(model_path, torch_dtype=torch.bfloat16)

    original_vocab_size = tokenizer.vocab_size
    print(f"原始词表大小: {original_vocab_size}")

    if new_tokens:
        # 添加新 token
        num_added_tokens = tokenizer.add_tokens(new_tokens)
        print(f"新增 token 数量: {num_added_tokens}")

        if num_added_tokens > 0:
            # 扩展模型 embedding
            model.resize_token_embeddings(len(tokenizer))
            print(f"embedding 已扩展到新词表大小: {len(tokenizer)}")

    return model, tokenizer

def main():
    parser = argparse.ArgumentParser(
        description="为 tokenizer 和模型 embedding 添加新 token。"
    )
    parser.add_argument(
        "--model_path",
        type=str,
        required=True,
        help="本地基础模型路径 (如: ./DeepSeek-R1-0528-Qwen3-8B)",
    )
    parser.add_argument(
        "--save_path",
        type=str,
        required=True,
        help="保存扩展后模型与 tokenizer 的路径 (如: ./DeepSeek-R1-0528-Qwen3-8B-AddTags2)",
    )
    parser.add_argument(
        "--add_tags",
        action="store_true",
        help="添加默认标签 token，如 <Analyze>, <Understand>, <Code> 等",
    )
    args = parser.parse_args()

    # 校验模型路径是否存在
    if not os.path.exists(args.model_path):
        raise FileNotFoundError(f"模型路径不存在: {args.model_path}")

    new_tokens = None
    if args.add_tags:
        # 定义需要添加的特殊标签 token
        new_tokens = [
            "<Analyze>",
            "</Analyze>",
            "<Understand>",
            "</Understand>",
            "<Code>",
            "</Code>",
            "<Execute>",
            "</Execute>",
            "<Answer>",
            "</Answer>",
        ]
        print(f"🔹 添加默认特殊 token: {new_tokens}")

    # 加载并扩展 model 和 tokenizer
    model, tokenizer = load_and_extend_model(args.model_path, new_tokens)

    # 创建示例文本，用于 token 化和解码测试
    sample_text = (
        "<Analyze>\nTo determine the count of customers supported by Steve Johnson, we need to.\n</Analyze>\n"
        "<Code>\n```python\n```\n</Code>\n"
        "<Execute>\n=== Employees Data ===\n\n</Execute>\n"
        "<Understand>\nFrom the execution results, we can observe.\n</Understand>\n"
        "<Answer>\nSteve Johnson supports 18 customers.\n</Answer>"
    )
    # 编码样本文本
    encoded = tokenizer.encode(sample_text, return_tensors="pt")
    # 逐 token 解码，方便检查分词效果
    decoded = [tokenizer.decode(x) for x in encoded[0]]

    print("\n样本文本分词测试:")
    print(f"输入文本: {sample_text}")
    print(f"编码后 tensor 形状: {encoded.shape}")
    print(f"解码后前 20 个 token: {decoded[:20]} ...")  # 只展示前 20 个 token

    # 保存扩展后的 tokenizer 和模型
    os.makedirs(args.save_path, exist_ok=True)
    tokenizer.save_pretrained(args.save_path)
    model.save_pretrained(args.save_path)
    print(f"\n扩展后的模型和 tokenizer 已保存到: {args.save_path}")

if __name__ == "__main__":
    main()
