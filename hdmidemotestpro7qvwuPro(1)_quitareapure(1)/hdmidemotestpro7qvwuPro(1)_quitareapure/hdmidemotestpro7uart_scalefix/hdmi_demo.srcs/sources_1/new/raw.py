#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os

def read_file_with_fallback(filepath):
    """
    尝试用不同编码读取文件，返回字符串。
    顺序：UTF-8 -> GBK -> 带替换的 UTF-8
    """
    encodings = ['utf-8', 'gbk']
    for enc in encodings:
        try:
            with open(filepath, 'r', encoding=enc) as f:
                return f.read()
        except UnicodeDecodeError:
            continue
    # 最后的备选：忽略错误，用替换符 '�' 代替无法解码的字节
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        return f.read()

def merge_verilog_files(output_filename="combined.txt"):
    """
    将当前目录下所有 .v 文件合并到一个 txt 文件中。
    格式：文件名\n文件内容\n
    自动处理编码问题。
    """
    v_files = [f for f in os.listdir('.')
               if f.endswith('.v') and os.path.isfile(f)]

    if not v_files:
        print("当前目录下没有找到 .v 文件。")
        return

    with open(output_filename, 'w', encoding='utf-8') as out_file:
        for v_file in v_files:
            try:
                content = read_file_with_fallback(v_file)
                out_file.write(f"{v_file}:\n")
                out_file.write(content)
                if not content.endswith('\n'):
                    out_file.write('\n')  # 保证每个文件内容后至少有一个换行
                print(f"已处理: {v_file}")
            except Exception as e:
                print(f"处理文件 {v_file} 时出错: {e}")

    print(f"\n所有文件已合并到 {output_filename}")

if __name__ == "__main__":
    merge_verilog_files()