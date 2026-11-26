1.这是延迟的优化路径说明

2.resize_and_gray_v2相较于resize_and_gray_v1的优化在于将直接访问DDR的单字并解析成rgb像素修改为独立的DDR reader，并设置FIFO缓存，解析rgb像素时从FIFO读取单字。源码位于D:\Users\hjx91\Project\FPGA\AX7020\LeNet5\hls\resize_and_gray_v2

3.简单说明2的优化效果，从resize_and_gray_v2和resize_and_gray_v1下的两幅delay_100.png来看，test_3.png为1920×1080大图，PL处理时间明显下降，由约1607.6 ms降至326.5 ms；但是PS收帧时间却更加分层，并且延迟更高，此时PS的TCP并未做任何修改；PL的处理时间出现分层，并且出现result错误，初步判断帧间处理有问题。

4.resize_and_gray_v3相较于resize_and_gray_v2的优化在于，resize_and_gray ip核存在对外显示空闲，但是内部模块还存在数据流动的问题，此时复位会导致末尾的数据处理存在问题；优化点：DDR 全部读取后发送标志，28 行输出完成后等待该标志再返回。源码位于D:\Users\hjx91\Project\FPGA\AX7020\LeNet5\hls\resize_and_gray_v2。1920×1080图片的PL异常短耗时消失，处理时间由约0.845 ms与326.5 ms分层变为稳定在326.5 ms。

5.resize_and_gray_v4相较于resize_and_gray_v3的优化在于，把PS的TCP wnd接收窗口设置为65535字节。1920×1080图片的PS平均收帧时间由约962.4 ms降至64.9 ms。

6.resize_and_gray_v5相较于resize_and_gray_v4的优化在于，优化解析rgb像素逻辑，把流水线的处理单位从“一个颜色分量”提升为“一个完整 RGB 像素”。源码位于D:\Users\hjx91\Project\FPGA\AX7020\LeNet5\hls\resize_and_gray_v4。1920×1080图片的PL平均处理时间由约326.5 ms降至123.0 ms。

当前 v5 延迟汇总（对应 `resize_and_gray_v5/delay_100.png`，数值取同名 CSV 中每张图片 100 次测试的平均值，单位：ms）：

| 图片 | 分辨率 | PS 收帧 rx | PL 处理 pl | PC 总耗时 pc |
| --- | --- | ---: | ---: | ---: |
| test_1.png | 28×28 | 0.016 | 0.849 | 1.073 |
| test_2.png | 640×480 | 9.975 | 18.528 | 29.081 |
| test_3.png | 1920×1080 | 67.071 | 123.040 | 192.949 |
