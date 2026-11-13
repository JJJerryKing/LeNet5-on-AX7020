# LeNet5 on AX7020

基于 Xilinx Zynq-7000 AX7020（XC7Z020-1CLG400）的 LeNet-5 FPGA 推理工程。工程使用 Vivado 2017.4 创建，PS 通过 AXI 将一帧 `28×28` 灰度图写入 BRAM，PL 读取图像并完成卷积、ReLU、池化、全连接和 Argmax，最终返回分类编号。

## 环境要求

- ALINX AX7020 开发板（XC7Z020-1CLG400）
- Xilinx Vivado 2017.4（建议使用与工程一致的版本）
- Xilinx SDK 2017.4（需要运行 PS 端程序时使用）
- USB-UART 驱动
- Python 3 和 `pyserial`（需要使用 PC 串口脚本时使用）

## 目录说明

```text
LeNet5.xpr                         Vivado 工程入口
LeNet5.srcs/sources_1/new/         PL 端 RTL、COE、测试程序和报告
LeNet5.srcs/sources_1/ip/          权重/偏置 ROM 的 IP 配置文件
LeNet5.srcs/sources_1/bd/design_1/ Zynq Block Design 及 HDL Wrapper
LeNet5.sdk/PS/src/                 PS 端裸机程序源码
```

更详细的网络结构和各模块实现思路见 [`LeNet5.srcs/sources_1/new/README.md`](LeNet5.srcs/sources_1/new/README.md)。

## 使用步骤

### 1. 获取工程

```bash
git clone https://github.com/JJJerryKing/LeNet5-on-AX7020.git
cd LeNet5-on-AX7020
```

### 2. 打开 Vivado 工程

使用 Vivado 2017.4 双击根目录下的 `LeNet5.xpr`，或在 Vivado 中选择 **File → Open Project** 后打开该文件。

如果使用更高版本的 Vivado，软件可能提示升级 IP。升级后生成的工程不保证仍能由 Vivado 2017.4 打开，建议先保留原工程副本。

### 3. 生成 IP 输出文件

仓库只保存可复现工程所需的 IP 配置，不保存 Vivado 自动生成的缓存和输出产物。第一次打开后：

1. 在 **Sources → IP Sources** 中检查各 IP。
2. 如显示输出产物缺失，右键 IP，选择 **Generate Output Products**。
3. 打开 `design_1`，选择 **Tools → Validate Design**。
4. 如 Vivado 提示重新生成 Block Design 输出文件，右键 `design_1`，选择 **Generate Output Products**。

权重和偏置由 `LeNet5.srcs/sources_1/new/coe/` 下的 COE 文件初始化。

### 4. 仿真

1. 在 **Flow Navigator → Simulation** 中选择 **Run Simulation → Run Behavioral Simulation**。
2. 仿真顶层为 `tb_PL`。
3. 观察 `I_data_valid/I_data_ready`、`O_data_valid/O_data_ready`、`result_q`，以及各级 `valid_debug`、`ready_debug` 信号。

### 5. 综合、实现并生成 Bitstream

依次执行：

1. **Run Synthesis**
2. **Run Implementation**
3. **Generate Bitstream**

综合顶层为 Block Design 的 `design_1_wrapper`。工程目标器件为 `xc7z020clg400-1`。

### 6. 导出硬件并建立 SDK 工程

1. 在 Vivado 中选择 **File → Export → Export Hardware**，勾选 **Include bitstream**。
2. 选择 **File → Launch SDK**。
3. 在 SDK 中创建或导入裸机应用，将 `LeNet5.sdk/PS/src/main.c` 和 `lscript.ld` 加入应用工程。
4. 确认 BSP 生成的 `xparameters.h` 中包含图像 BRAM、控制 GPIO 和状态 GPIO 的地址/设备定义。
5. 编译 PS 程序。

PS 程序通过 UART 接收 784 个灰度字节，将每个像素写入一个 32 位 BRAM 字，启动 PL 推理，并通过 UART 返回分类编号。

### 7. 下载到 AX7020

1. 连接 JTAG、USB-UART 和开发板电源。
2. 在 SDK 中执行 **Program FPGA**。
3. 运行 PS 应用。
4. 确认串口参数为 `115200-8-N-1`。

### 8. 从 PC 发送图片

1. 安装依赖：

   ```bash
   pip install pyserial
   ```

2. 编辑 `LeNet5.srcs/sources_1/new/PC/uart.py`，设置开发板串口号和输入图片文本文件路径。
3. 输入文件应包含 784 个十进制灰度值，每个值范围为 `0~255`。
4. 运行：

   ```bash
   python LeNet5.srcs/sources_1/new/PC/uart.py
   ```

脚本发送一帧图片后，PS 返回的分类编号范围为 `0~9`。

## 主要数据流

```text
PS/UART → AXI BRAM → image_reader → LeNet_top
→ Conv1 → ReLU → Pool1
→ Conv2 → ReLU → Pool2
→ Conv3 → FC1 → FC2 → Argmax
→ AXI GPIO → PS/UART
```

