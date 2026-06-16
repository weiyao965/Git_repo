import serial
import numpy as np
import cv2
import time

# ================= 配置区 =================
COM_PORT = 'COM8'       # 【必填】请修改为你的 FPGA 开发板实际串口号
BAUD_RATE = 1000000
TOTAL_BYTES = 19205     # 19200(图像) + 5(AI模型状态+坐标)
DELAY_SECONDS = 5       # 运行脚本后等待的时间（秒），给你时间走到镜头前摆姿势
# ==========================================

print(f"正在打开 {COM_PORT} (波特率 {BAUD_RATE})...")
try:
    # 每次运行前，请确保没有任何其他串口工具或网页后台占用 COM 口
    ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=5)
except Exception as e:
    print(f"❌ 串口打开失败，请检查端口是否被占用: {e}")
    exit()

print("\n================ 🚀 自动化 HIL 测试启动 ================")
print(f"请在 {DELAY_SECONDS} 秒内走到镜头前对准绿框...")

# 1. 倒计时
for i in range(DELAY_SECONDS, 0, -1):
    print(f"倒计时: {i}...")
    time.sleep(1)

# 2. 发送抓拍指令 (等同于按下物理按键 KEY1)
print("\n📸 正在触发硬件抓拍 (发送指令 0xC1)...")
ser.write(bytes([0xC1]))

# 等待 FPGA 完整抓取一帧图像 
# 在 60Hz 帧率下，一帧大概需要 16.6ms。我们等待 200ms，保证图像 100% 写入 BRAM
time.sleep(0.2)

# 3. 发送传输指令 (等同于按下物理按键 KEY2)
print("📡 正在请求回传数据 (发送指令 0xC2)...")
ser.write(bytes([0xC2]))

print(f"⏳ 等待 FPGA 传输 {TOTAL_BYTES} 字节，请稍候...")
data = ser.read(TOTAL_BYTES)

# 4. 解析与图像处理
if len(data) == TOTAL_BYTES:
    print("\n✅ 成功接收完整数据！正在生成 FPGA AI 深度分析报告...\n")
    
    # 剥离并恢复 160x120 图像
    img_data = data[:19200]
    img_array = np.frombuffer(img_data, dtype=np.uint8).reshape((120, 160))
    # 转换为 BGR 彩色图，以便在上面画红色的框
    img_bgr = cv2.cvtColor(img_array, cv2.COLOR_GRAY2BGR)
    
    # 剥离 AI 引擎附加的 5 字节诊断信息
    face_valid = data[19200]
    f_x = data[19201]
    f_y = data[19202]
    f_w = data[19203]
    f_h = data[19204]
    
    print("---------------- FPGA 硬件 AI 引擎实时状态 ----------------")
    print(f"探测状态标志位: {'🟩 [已触发! 成功锁定人脸]' if face_valid else '🟥 [未触发阈值 / 未检测到]'} (值为 {face_valid})")
    
    if face_valid:
        print(f"底层计算坐标:   X={f_x}, Y={f_y}, 宽={f_w}, 高={f_h} (基于 160x120 缩放尺度)")
        
        # 在全景图上画红框，这完全等价于你在 HDMI 屏幕上应该看到的红框位置
        cv2.rectangle(img_bgr, (f_x, f_y), (f_x + f_w, f_y + f_h), (0, 0, 255), 1)
        
        # 核心功能：裁剪出 AI 最终锁定的人脸区域 (ROI)
        # 确保裁剪边界不会越界
        roi_x1, roi_y1 = max(0, f_x), max(0, f_y)
        roi_x2, roi_y2 = min(160, f_x + f_w), min(120, f_y + f_h)
        
        if roi_x2 > roi_x1 and roi_y2 > roi_y1:
            face_roi = img_array[roi_y1:roi_y2, roi_x1:roi_x2]
            cv2.imwrite("fpga_ROI_extracted.png", face_roi)
            print("📸 已提取 AI 锁定的 ROI 人脸局部特征，保存为: fpga_ROI_extracted.png")
            print("💡 如果这张提取出的图片是你的脸，说明模型完全正确！如果不红则是 HDMI 显示通道问题。")
            print("💡 如果这张提取出的图片是墙壁或背景，说明 AI 认错了，你需要继续去 vj.v 修改补偿阈值。")
        
    print("-----------------------------------------------------------")
        
    # 保存并显示全景诊断图
    cv2.imwrite("fpga_full_view.png", img_bgr)
    print("🖼️ 包含红框的完整视界图已保存为: fpga_full_view.png")
    
    # 弹出窗口显示图像 (按任意键关闭)
    cv2.imshow("FPGA AI Vision Debugger", img_bgr)
    print("\n👉 请在弹出的图像窗口上按键盘任意键退出程序。")
    cv2.waitKey(0)
    cv2.destroyAllWindows()
    
else:
    print(f"\n❌ 接收超时或数据不完整。预期 {TOTAL_BYTES} 字节，仅收到 {len(data)} 字节。")
    print("👉 请检查：1. 串口波特率是否一致；2. FPGA 是否已成功烧录最新代码。")
    
ser.close()