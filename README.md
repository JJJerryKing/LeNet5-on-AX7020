# LeNet5 on AX7020

基于 Xilinx Zynq-7000 AX7020（XC7Z020-1CLG400）的 LeNet-5 FPGA 推理工程。工程使用 Vivado 2017.4 创建，PS 通过串口接收可变尺寸RGB图片及宽高，写入固定DDR并刷新缓存；PL通过AXI Master读取图片，完成灰度化、缩放到 `28×28` 及LeNet分类，最终返回分类编号。

## 环境要求

- ALINX AX7020 开发板（XC7Z020-1CLG400）
- Xilinx Vivado 2017.4（建议使用与工程一致的版本）
- Xilinx Vivado HLS 2017.4（需要重新生成预处理IP时使用）
- Xilinx SDK 2017.4（需要运行 PS 端程序时使用）
- USB-UART 驱动
- Python 3、`pyserial` 和 `Pillow`（需要使用 PC 串口脚本时使用）

## 目录说明

```text
LeNet5.xpr                         Vivado 工程入口
LeNet5.srcs/sources_1/new/         PL 端 RTL、COE、测试程序和报告
LeNet5.srcs/sources_1/ip/          权重/偏置 ROM 和预处理 IP 的配置文件
LeNet5.srcs/sources_1/bd/design_1/ Zynq Block Design 及 HDL Wrapper
LeNet5.sdk/PS/src/                 PS 端裸机程序源码
hls/resize_and_gray/             HLS 预处理源码及导出 IP
LeNet5.srcs/sources_1/new/PC/     PC 串口脚本及 test_dataset 测试图片
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

Vivado自动生成的缓存和输出产物可以重新生成。在 **Settings → IP → Repository** 中添加 `hls/resize_and_gray/solution1/impl/ip/example/xilinx_com_hls_resize_and_gray_1_0`，其中包含已导出的 `component.xml` 和RTL，并刷新IP Catalog。需要重新综合导出时，在 `hls` 目录运行 `vivado_hls -f resize_and_gray/solution1/script.tcl`，顶层为 `resize_and_gray`。

第一次打开后：

1. 在 **Sources → IP Sources** 中检查各 IP。
2. 如显示输出产物缺失，右键 IP，选择 **Generate Output Products**。
3. 打开 `design_1`，选择 **Tools → Validate Design**。
4. 如 Vivado 提示重新生成 Block Design 输出文件，右键 `design_1`，选择 **Generate Output Products**。

权重和偏置由 `LeNet5.srcs/sources_1/new/coe/` 下的 COE 文件初始化。

### 4. 仿真

现有 `tb_PL` 使用旧BRAM接口，详见v1，尚未适配当前DDR预处理系统，不能直接用于完整系统仿真。当前使用下述上板流程验证图片处理及分类。

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
4. 确认 BSP 生成的 `xparameters.h` 中包含控制 GPIO 和状态 GPIO 的地址/设备定义。
5. 在链接脚本中为固定图像区 `0x10000000` 起的8MB预留空间，避免与程序、堆栈重叠；地址须与PL一致。
6. 编译 PS 程序。

PS程序接收宽高及连续RGB888数据，写入DDR参数头和图片、刷新缓存，再握手启动PL。读取并确认分类结果后，等待预处理结束，复位计算模块并等待就绪，最后通过UART返回类别。

控制GPIO地址为 `0x41200000`：通道1的bit0为启动、bit1为低有效计算复位，待机写 `0x02`、启动写 `0x03`、复位写 `0x00`；通道2的bit0用于结果确认。状态GPIO地址为 `0x41210000`：通道1为类别编号，通道2的bit0为结果valid、bit1为输入ready。软件复位仅作用于计算模块，GPIO和AXI互连保持工作。

### 7. 下载到 AX7020

1. 连接 JTAG、USB-UART 和开发板电源。
2. 在 SDK 中执行 **Program FPGA**。
3. 将编译生成的 `PS.elf` 下载到CPU #0并运行。
4. 确认串口参数为 `115200-8-N-1`。

### 8. 从 PC 发送图片

1. 安装依赖：

   ```bash
   python -m pip install pyserial Pillow
   ```

2. 确认开发板串口号并关闭占用串口的其他程序。输入使用PNG、JPEG或BMP等图片文件，宽度为 `1~1920`、高度为 `1~1080`；脚本转换为RGB，保留原始尺寸，由PL灰度化和缩放。
3. 从工程根目录进入PC目录并运行（将 `COM4` 替换为实际串口）：

   ```bash
   cd LeNet5.srcs/sources_1/new/PC
   python uart.py test_dataset/test_1.png --port COM4
   ```

`test_1.png` 为28×28的数字7；另外两张 `test_2.png`、`test_3.png` 分别为640×480的数字2、1920×1080的数字1，可替换命令中的文件名逐张运行。115200波特率下，后两张传输分别约80秒和9分钟。

发送格式为 `RGB8` 帧头、32位小端宽度、32位小端高度以及逐行紧密排列的RGB888数据。PS成功时只返回一个原始类别字节 `0~9`，宽高非法时返回 `E`，没有额外确认字节或结束标记。每次等待结果后再发送下一帧。

## 主要数据流

```text
PC/UART → PS写DDR并刷新缓存 → preprocessing（AXI读取、灰度化、28×28缩放）
→ LeNet_top
→ Conv1 → ReLU → Pool1
→ Conv2 → ReLU → Pool2
→ Conv3 → FC1 → FC2 → Argmax
→ AXI GPIO → PS/UART
```

