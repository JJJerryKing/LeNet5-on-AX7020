
from pathlib import Path
import serial

PORT = "COM4"
BAUD_RATE = 115200
PIXEL_COUNT = 28 * 28
IMAGE_FILE = Path(
    r"D:\Users\hjx91\Project\FPGA\AX7020\LeNet5\LeNet5.sim"
    r"\sim_1\behav\xsim\ori0.txt"
)

pixels = [int(value) for value in IMAGE_FILE.read_text().split()]
if len(pixels) != PIXEL_COUNT or any(not 0 <= value <= 255 for value in pixels):
    raise ValueError("MNIST image must contain exactly 784 bytes in range 0..255")

with serial.Serial(PORT, BAUD_RATE, timeout=1, write_timeout=5) as uart:
    uart.reset_input_buffer()

    # 发送图片
    uart.write(bytes(pixels))
    uart.flush()
    print(f"Sent {PIXEL_COUNT} bytes from {IMAGE_FILE} to {PORT}")

    # 循环接收
    print("Waiting for data... Press Ctrl+C to stop.")
    try:
        while True:
            response = uart.read(1)

            if response:
                print(f"Received: {response[0]}")

    except KeyboardInterrupt:
        print("\nSerial reception stopped.")
