import os
import io
import base64
import time
import serial
import serial.tools.list_ports
import numpy as np
from PIL import Image
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)

# 全局串口对象
ser = None
BAUD_RATE = 1000000

def get_ports():
    return [port.device for port in serial.tools.list_ports.comports()]

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/ports', methods=['GET'])
def list_ports():
    return jsonify({"ports": get_ports()})

@app.route('/api/connect', methods=['POST'])
def connect_port():
    global ser
    port = request.json.get('port')
    try:
        if ser and ser.is_open:
            ser.close()
        # 设置超时为 12 秒，确保 8 秒的抓拍不会触发超时报错
        ser = serial.Serial(port, BAUD_RATE, timeout=12.0)
        return jsonify({"status": "success", "msg": f"已成功连接 {port} @3Mbps"})
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)})

@app.route('/api/command', methods=['POST'])
def send_command():
    global ser
    if not ser or not ser.is_open:
        return jsonify({"status": "error", "msg": "串口未连接！"})
    
    cmd_hex = request.json.get('cmd') # 例如 "AA 01 05 02 55"
    try:
        cmd_bytes = bytes.fromhex(cmd_hex.replace(" ", ""))
        ser.write(cmd_bytes)
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)})

@app.route('/api/capture', methods=['POST'])
def capture_image():
    global ser
    if not ser or not ser.is_open:
        return jsonify({"status": "error", "msg": "串口未连接！"})
    
    try:
        # 1. 发送抓拍指令
        ser.reset_input_buffer()
        ser.write(bytes.fromhex("AA04000055"))
        
        # 2. 等待帧头 BB 66 (可能需要等一点时间)
        header_found = False
        start_wait = time.time()
        while time.time() - start_wait < 5.0:
            if ser.in_waiting >= 2:
                head = ser.read(2)
                if head == b'\xbb\x66':
                    header_found = True
                    break
        
        if not header_found:
            return jsonify({"status": "error", "msg": "等待帧头超时，请检查板子状态！"})
        
        # 3. 接收 614400 字节数据
        expected_bytes = 614400
        data = bytearray()
        while len(data) < expected_bytes:
            chunk = ser.read(expected_bytes - len(data))
            if not chunk:
                return jsonify({"status": "error", "msg": "接收图像数据超时断流！"})
            data.extend(chunk)
            
        # 4. 图像解码 (RGB565 大端序 -> RGB888 -> Base64)
        img_data = np.frombuffer(data, dtype='>u2')
        r = ((img_data >> 11) & 0x1F) * 255 // 31
        g = ((img_data >> 5) & 0x3F) * 255 // 63
        b = (img_data & 0x1F) * 255 // 31
        
        rgb_array = np.stack((r, g, b), axis=-1).astype(np.uint8)
        rgb_array = rgb_array.reshape((480, 640, 3)) # 重组为 640x480
        
        img = Image.fromarray(rgb_array, 'RGB')
        buf = io.BytesIO()
        img.save(buf, format='PNG')
        img_base64 = base64.b64encode(buf.getvalue()).decode('utf-8')
        
        return jsonify({"status": "success", "image": img_base64})
        
    except Exception as e:
        return jsonify({"status": "error", "msg": str(e)})

if __name__ == '__main__':
    # 开启局域网访问，关闭 debug 避免串口被重复占用
    app.run(host='0.0.0.0', port=5000, debug=False)