import argparse
from pathlib import Path
import socket
import struct
from time import perf_counter

from PIL import Image

IP = "10.4.162.19"
PORT = 6001


def main():
    parser = argparse.ArgumentParser(description="Send RGB images to PS/PL over TCP.")
    parser.add_argument("images", nargs="+", type=Path, help="Image files to classify")
    args = parser.parse_args()

    with socket.create_connection((IP, PORT), timeout=30) as conn:
        for path in args.images:
            # 保留原始尺寸，灰度化和缩放由 PL 完成。
            with Image.open(path) as image:
                packet = (b"RGB8" + struct.pack("<II", *image.size)
                          + image.convert("RGB").tobytes())

            start = perf_counter()
            conn.sendall(packet)
            result = conn.recv(1)
            if not result:
                raise ConnectionError("PS closed the TCP connection")
            print(f"{path.name}: class={result[0]}, elapsed={perf_counter() - start:.3f}s")


if __name__ == "__main__":
    main()
