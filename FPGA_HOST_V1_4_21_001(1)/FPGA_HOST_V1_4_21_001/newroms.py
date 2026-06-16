import re

print("🚀 正在启动终极 ROM 转换引擎 (Case-Statement 模式)...")

try:
    with open("roms.v", "r", encoding="utf-8") as f:
        content = f.read()
except FileNotFoundError:
    print("❌ 找不到原始的 roms.v，请确保文件在当前目录！")
    exit()

modules = re.split(r'\bendmodule\b', content)
out_code = ""

for mod in modules:
    if not mod.strip(): continue
    
    # 寻找包含 initial 初始化的 ROM 模块
    if "initial" in mod and "rom[" in mod:
        # 提取模块的头部 (直到 output reg ... q ); )
        header_match = re.search(r'(module.*?output\s+reg\s*\[\d+:0\]\s+q\s*\n\s*\);)', mod, re.DOTALL | re.IGNORECASE)
        if not header_match:
            header_match = re.search(r'(module.*?output.*?q.*?\);)', mod, re.DOTALL | re.IGNORECASE)
            
        if not header_match:
            out_code += mod + "\nendmodule\n"
            continue
            
        header_str = header_match.group(1)
        
        # 提取所有的赋值语句
        assignments = re.findall(r'rom\s*\[\s*(\d+)\s*\]\s*=\s*(.*?);', mod)
        
        # 生成强制综合为 BRAM 的 case 语句
        case_body = "\n\t(* rom_style = \"block\", ramstyle = \"block\" *)\n"
        case_body += "\talways @(posedge clk) begin\n\t\tcase(addr)\n"
        for addr, val in assignments:
            case_body += f"\t\t\t{addr}: q <= {val};\n"
        case_body += "\t\t\tdefault: q <= 0;\n\t\tendcase\n\tend\n"
        
        out_code += header_str + case_body + "endmodule\n"
    else:
        out_code += mod + "\nendmodule\n"

with open("roms_case.v", "w", encoding="utf-8") as f:
    f.write(out_code)

print("✅ 转换大功告成！已生成最硬核的 roms_case.v")
print("👉 请在 FPGA 工程中删除所有旧的 rom 文件和 txt 文件，只添加 roms_case.v！")