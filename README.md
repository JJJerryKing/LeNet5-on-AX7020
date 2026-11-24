# LeNet5 on AX7020

基于 Xilinx Zynq-7000 AX7020（XC7Z020-1CLG400）的 LeNet-5 FPGA 推理工程。PS基于LwIP TCP接收可变尺寸RGB图片及宽高，写入固定DDR并刷新缓存；PL通过AXI Master读取图片，完成灰度化、缩放到28×28及LeNet推理；推理结束后产生中断，PS读取result并转发给PC。

## 环境要求

- ALINX AX7020 开发板（XC7Z020-1CLG400）
- Xilinx Vivado 2017.4
- Xilinx Vivado HLS 2017.4
- Xilinx SDK 2017.4
- PC 和开发板通过有线以太网接入同一局域网
- USB-UART 驱动（查看启动和调试日志时使用）
- Python 3 和 Pillow

## 目录说明

```text
LeNet5.xpr                         Vivado 工程入口
LeNet5.srcs/sources_1/new/         PL 端 RTL、COE、测试程序和报告
LeNet5.srcs/sources_1/ip/          权重/偏置 ROM 和预处理 IP 的配置文件
LeNet5.srcs/sources_1/bd/design_1/ Zynq Block Design 及 HDL Wrapper
LeNet5.sdk/PS_Ethernet/src/        PS 端 lwIP TCP 应用、PL 调度及平台初始化源码
LeNet5.sdk/PS_Ethernet_bsp/        BSP 配置，system.mss 保留 lwIP 等设置
LeNet5.sdk/PS/src/                 旧 UART 方案源码
hls/resize_and_gray/             HLS 预处理源码及导出 IP
LeNet5.srcs/sources_1/new/PC/     Ethernet/UART 客户端及 test_dataset 测试图片
```

更详细的网络结构和各模块实现思路见 [`LeNet5.srcs/sources_1/new/README.md`](LeNet5.srcs/sources_1/new/README.md)。

## 使用步骤

### 1. 获取工程

```bash
git clone https://github.com/JJJerryKing/LeNet5-on-AX7020.git
cd LeNet5-on-AX7020
```

### 2. PL

打开 `LeNet5.xpr`依次执行 **Generate Output Products → Run Synthesis → Run Implementation → Generate Bitstream**


### 3. PS

Export Hardware → Launch SDK，编译PS_Ethernet_bsp和PS_Ethernet

### 4. 启动

连接电源、JTAG 和网线，SDK中同时运行PL和PS

### 5. 配置网络

PC和PS处于同一局域网

### 6. 发送图片并查看结果

```bash
cd LeNet5.srcs/sources_1/new/PC
python ethernet.py test_dataset/test_1.png
```
