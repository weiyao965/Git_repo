import cv2
import os

# 1. 自动定位并加载 OpenCV 自带的标准正面人脸 Haar 级联模型
# 通常硬件复刻版对应的是 default 或 alt 版本
cascade_path = os.path.join(cv2.data.haarcascades, 'haarcascade_frontalface_default.xml')
# 如果 default 效果不好，可以解除下面这行的注释尝试 alt 版本
# cascade_path = os.path.join(cv2.data.haarcascades, 'haarcascade_frontalface_alt.xml')

face_cascade = cv2.CascadeClassifier(cascade_path)

if face_cascade.empty():
    print("❌ 模型加载失败，请检查 OpenCV 安装。")
    exit()
else:
    print(f"✅ 成功加载 OpenCV 自带模型: {os.path.basename(cascade_path)}")

# 2. 读取 FPGA 抓拍的 160x120 真实视界图
img_path = 'ai_real_view.png'
img = cv2.imread(img_path, cv2.IMREAD_GRAYSCALE)

if img is None:
    print("❌ 图片读取失败，请确认 ai_real_view.png 在当前目录！")
    exit()

print(f"✅ 成功加载测试图片，分辨率: {img.shape[1]}x{img.shape[0]}")

# 3. 核心：执行检测 (参数极力模拟 FPGA 硬件限制)
faces = face_cascade.detectMultiScale(
    img,
    scaleFactor=1.2,      # 硬件中为了省资源，缩放步长通常较大
    minNeighbors=3,       # 邻近矩形数，设为3是一个合理的折中阈值
    minSize=(24, 24),     # ❗️绝对关键：必须 >= 24x24，对应硬件宏定义 `define W1 24
    maxSize=(100, 100)    # 脸太大硬件也往往算不出，设置个上限
)

print("\n================ 诊断结果 ================")
if len(faces) == 0:
    print("🚨 Python 模型【未能】检测到人脸！")
    print("-> 结论：并非 FPGA 代码有 Bug，而是当前的物理条件（人脸大小、光线对比度、背景、歪头）连软件纯算法都无法识别。")
    print("-> 建议：继续后退让脸变小（占引导框 1/3）、正脸直立、调整光线，直到抓拍的图能被本脚本识别为止。")
else:
    print(f"🎉 成功检测到 {len(faces)} 个人脸！")
    print("-> 结论：当前物理抓拍条件完美！如果 FPGA 不出红框，说明 FPGA 逻辑内部存在状态机提前复位或判决阈值过高的问题。")
    
    # 4. 绘制检测框并保存对比图
    for i, (x, y, w, h) in enumerate(faces):
        print(f"   -> 锁定目标 {i+1} : X={x}, Y={y}, 宽={w}, 高={h}")
        cv2.rectangle(img, (x, y), (x+w, y+h), (255, 255, 255), 2)

    cv2.imwrite('ai_real_view_result.png', img)
    print("\n✅ 检测结果已画框并保存为 ai_real_view_result.png")