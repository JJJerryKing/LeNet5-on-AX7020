import csv
from collections import defaultdict
from pathlib import Path
from random import Random

import matplotlib.pyplot as plt

RESULT_DIR = Path(__file__).with_name("resize_and_gray_v5")


def main():
    data = defaultdict(lambda: [[], [], []])
    with (RESULT_DIR / "delay_100.csv").open(
            newline="", encoding="utf-8-sig") as delay:
        for row in csv.DictReader(delay):
            for values, field in zip(data[row["image"]],
                                     ("rx_us", "pl_us", "pc_us")):
                values.append(float(row[field]) / 1000)

    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei"]
    plt.rcParams["axes.unicode_minus"] = False
    fig, axes = plt.subplots(1, len(data), figsize=(13, 5), squeeze=False)
    rng = Random(0)
    for ax, (name, groups) in zip(axes[0], data.items()):
        boxes = ax.boxplot(groups, patch_artist=True, showfliers=False,
                           medianprops={"color": "#273444"})
        for i, (values, box, color) in enumerate(zip(
                groups, boxes["boxes"], ("#347fba", "#db8a36", "#3b8e75")), 1):
            box.set_facecolor(color)
            box.set_alpha(0.3)
            ax.scatter([i + rng.uniform(-0.12, 0.12) for _ in values],
                       values, color=color, s=22, alpha=0.75, zorder=3)
        ax.set_title(f"{name} · n={len(groups[0])}")
        ax.set_xticks([1, 2, 3], ["PS 收帧 rx", "PL 处理 pl", "PC 总耗时 pc"])
        ax.set_ylabel("时间（ms）")
        ax.set_ylim(bottom=0)
        ax.set_axisbelow(True)
        ax.grid(axis="y", alpha=0.3)

    fig.suptitle("耗时箱线图与散点（各子图纵轴独立）")
    fig.tight_layout()
    fig.savefig(RESULT_DIR / "delay_100.png", dpi=180)
    plt.show()


if __name__ == "__main__":
    main()
