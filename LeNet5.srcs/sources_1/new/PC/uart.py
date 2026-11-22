import argparse
from pathlib import Path
import struct

import serial
from PIL import Image

PORT = "COM4"
BAUD_RATE = 115200
MAX_WIDTH = 1920
MAX_HEIGHT = 1080


def receive_byte(uart):
    # 每次读取最多等待1秒；持续等待响应，允许用户通过Ctrl+C退出。
    while True:
        value = uart.read(1)
        if value:
            return value


def main():
    parser = argparse.ArgumentParser(description="Send an RGB image to PS/PL for classification.")
    parser.add_argument("image", type=Path, help="Image file, such as PNG, JPEG or BMP")
    parser.add_argument("--port", default=PORT, help=f"Serial port (default: {PORT})")
    args = parser.parse_args()

    # 保留原始尺寸，由PL完成灰度化和缩放；PC只统一为RGB888。
    with Image.open(args.image) as source:
        width, height = source.size
        if not (1 <= width <= MAX_WIDTH and 1 <= height <= MAX_HEIGHT):
            raise ValueError(f"Image dimensions must be within 1..{MAX_WIDTH} x 1..{MAX_HEIGHT}")
        pixels = source.convert("RGB").tobytes()

    # 帧头 + 32位小端宽高 + 逐行紧密排列的R/G/B字节，不发送DDR保留字。
    packet = b"RGB8" + struct.pack("<II", width, height) + pixels

    # 大图传输可能超过5秒，不限制写入时间；串口保持115200、8N1。
    with serial.Serial(args.port, BAUD_RATE, timeout=1, write_timeout=None) as uart:
        uart.reset_input_buffer()
        print(f"Sending {width}x{height} RGB image ({len(packet)} bytes) to {args.port}...")
        print("Press Ctrl+C to stop.")
        if uart.write(packet) != len(packet):
            raise RuntimeError("Incomplete serial write; the frame was not fully sent")
        uart.flush()

        # 每帧只返回一个类别字节或'E'错误响应，没有确认字节和结束标记。
        response = receive_byte(uart)
        if response == b"E":
            raise RuntimeError("PS rejected the image dimensions")

        # 类别是原始数值字节0..9，不是ASCII字符。
        result = response[0]
        if not 0 <= result <= 9:
            raise RuntimeError(f"Invalid class index: {result}")
        print(f"Classification result: {result}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nSerial transfer stopped.")
