import csv
from pathlib import Path
from queue import Queue
import re
import socket
import struct
from threading import Event, Thread
from time import perf_counter

from PIL import Image
import serial

IP = "10.4.162.19"
PORT = 6001
UART_PORT = "COM4"
BAUD_RATE = 115200
TRIALS = 100
PC_DIR = Path(__file__).resolve().parents[2]
RESULT_DIR = Path(__file__).with_name("resize_and_gray_v5")


def receive_timing(uart, timings, stop):
    while not stop.is_set():
        match = re.search(rb"rx=(\d+) us, pl=(\d+) us", uart.readline())
        if match:
            timings.put(tuple(map(int, match.groups())))


def main():
    RESULT_DIR.mkdir(exist_ok=True)
    timings = Queue()
    stop = Event()
    with serial.Serial(UART_PORT, BAUD_RATE, timeout=1) as uart:
        uart.reset_input_buffer()
        worker = Thread(target=receive_timing, args=(uart, timings, stop))
        worker.start()
        try:
            with socket.create_connection((IP, PORT), timeout=30) as conn, \
                    (RESULT_DIR / "delay_100.csv").open(
                        "w", newline="", encoding="utf-8") as delay:
                writer = csv.writer(delay)
                writer.writerow(["image", "trial", "result", "rx_us", "pl_us", "pc_us"])
                for name in ("test_1.png", "test_2.png", "test_3.png"):
                    with Image.open(PC_DIR / "test_dataset" / name) as image:
                        packet = (b"RGB8" + struct.pack("<II", *image.size)
                                  + image.convert("RGB").tobytes())

                    for trial in range(1, TRIALS + 1):
                        start = perf_counter()
                        conn.sendall(packet)
                        result = conn.recv(1)
                        pc_us = round((perf_counter() - start) * 1_000_000)
                        if not result:
                            raise ConnectionError("PS closed the TCP connection")

                        # 收到本帧串口计时后再发送下一帧，保持结果一一对应。
                        rx_us, pl_us = timings.get(timeout=30)
                        writer.writerow([name, trial, result[0], rx_us, pl_us, pc_us])
                        delay.flush()
                        print(f"{name} [{trial}/{TRIALS}]: class={result[0]}, "
                              f"rx={rx_us} us, pl={pl_us} us, pc={pc_us} us")
        finally:
            stop.set()
            worker.join()


if __name__ == "__main__":
    main()
