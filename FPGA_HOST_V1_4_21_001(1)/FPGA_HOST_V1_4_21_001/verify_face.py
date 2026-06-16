import cv2
import os

# 加载 OpenCV 官方人脸模型
xml_path = os.path.join(cv2.data.haarcascades, 'haarcascade_frontalface_default.xml')
cascade = cv2.CascadeClassifier(xml_path)

# 读取你刚才生成的 FPGA 视界图
img = cv2.imread("fpga_full_view.png", cv2.IMREAD_GRAYSCALE)

# 寻找人脸 (设定最小为24x24，完美贴合FPGA硬件)
faces = cascade.detectMultiScale(img, scaleFactor=1.1, minNeighbors=3, minSize=(24,24))

if len(faces) > 0:
    for (x, y, w, h) in faces:
        print(f"🎉 Python 证明图像完美！人脸坐标: X={x}, Y={y}, W={w}, H={h}")
        cv2.rectangle(img, (x, y), (x+w, y+h), 255, 1)
    cv2.imwrite("python_prove.png", img)
    print("已生成 python_prove.png，快去看看 OpenCV 是不是能认出你！")
else:
    print("🚨 Python 也没认出来，说明你刚才离镜头太远或太近，或者光线太暗。")