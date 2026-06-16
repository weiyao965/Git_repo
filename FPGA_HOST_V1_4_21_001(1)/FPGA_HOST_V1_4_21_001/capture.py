import serial
import numpy as np
from PIL import Image

# 请将 COM3 修改为你 FPGA 的实际端口号
ser = serial.Serial('COM8', 1000000, timeout=10) 

print("===================================")
print("1. 请把脸对准摄像头")
print("2. 在 FPGA 板子上按一下 KEY1 抓拍缓存")
print("3. 接着按一下 KEY2 通过串口推流...")
print("===================================")

data = ser.read(19200)

if len(data) == 19200:
    # 将接收到的 19200 字节转为 120 行 x 160 列的灰度矩阵
    img_array = np.frombuffer(data, dtype=np.uint8).reshape((120, 160))
    img = Image.fromarray(img_array, mode='L')
    img.save("ai_real_view.png")
    print("✅ 接收成功！已保存为 ai_real_view.png，快去看看 AI 到底看到了什么吧！")
else:
    print(f"❌ 接收超时或失败，仅收到 {len(data)} 字节")