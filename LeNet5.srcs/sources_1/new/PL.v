module PL#(
 parameter [31:0] DDR_BASE_ADDR = 32'h10000000,
 parameter QUANT_SIZE  = 13 ,
 parameter WEIGHT_SIZE = 13 ,
 parameter LINE_LEN    = 28 ,
 parameter PADDING     = 2  ,
 parameter CONV_CORE   = 5  ,
 parameter CHANNEL_I_1 = 1  ,
 parameter CHANNEL_O_1 = 6  ,
 parameter CHANNEL_O_2 = 16 ,
 parameter CHANNEL_O_3 = 120,
 parameter CHANNEL_O_4 = 84 ,
 parameter CHANNEL_O_5 = 10
)(
input                                               clk         ,
input                                               rstn        ,
// 整帧请求：由 preprocessing 接受固定 DDR 地址中的一帧图片。
input                                               I_data_valid,
output                                              I_data_ready,
// 分类结果：由 LeNet 输出，和内部逐行握手相互独立。
output     [10-1:0]                result_q    ,
output     [10-1:0]                valid_debug,
output     [10-1:0]                ready_debug,
output                                              O_data_valid,
input                                               O_data_ready,
/*
调试观测总线：435 bit，保留 LeNet 原有位段位置。
[ 29:  0] 保留，固定为 0
[434: 30] LeNet_top dbg_bus（405 bit，位定义见 LeNet_top.v）
*/
output     [434:0]                 dbg_bus,

// ============================================================================
// DDR AXI Master：从 preprocessing 完整透传，连接外部 AXI 互连/PS DDR 通道
// ============================================================================
// 写地址通道
output                                              m_axi_ddr_AWVALID,
input                                               m_axi_ddr_AWREADY,
output     [31:0]                                   m_axi_ddr_AWADDR,
output     [0:0]                                    m_axi_ddr_AWID,
output     [7:0]                                    m_axi_ddr_AWLEN,
output     [2:0]                                    m_axi_ddr_AWSIZE,
output     [1:0]                                    m_axi_ddr_AWBURST,
output     [1:0]                                    m_axi_ddr_AWLOCK,
output     [3:0]                                    m_axi_ddr_AWCACHE,
output     [2:0]                                    m_axi_ddr_AWPROT,
output     [3:0]                                    m_axi_ddr_AWQOS,
output     [3:0]                                    m_axi_ddr_AWREGION,
output     [0:0]                                    m_axi_ddr_AWUSER,

// 写数据通道
output                                              m_axi_ddr_WVALID,
input                                               m_axi_ddr_WREADY,
output     [31:0]                                   m_axi_ddr_WDATA,
output     [3:0]                                    m_axi_ddr_WSTRB,
output                                              m_axi_ddr_WLAST,
output     [0:0]                                    m_axi_ddr_WID,
output     [0:0]                                    m_axi_ddr_WUSER,

// 写响应通道
input                                               m_axi_ddr_BVALID,
output                                              m_axi_ddr_BREADY,
input      [1:0]                                    m_axi_ddr_BRESP,
input      [0:0]                                    m_axi_ddr_BID,
input      [0:0]                                    m_axi_ddr_BUSER,

// 读地址通道
output                                              m_axi_ddr_ARVALID,
input                                               m_axi_ddr_ARREADY,
output     [31:0]                                   m_axi_ddr_ARADDR,
output     [0:0]                                    m_axi_ddr_ARID,
output     [7:0]                                    m_axi_ddr_ARLEN,
output     [2:0]                                    m_axi_ddr_ARSIZE,
output     [1:0]                                    m_axi_ddr_ARBURST,
output     [1:0]                                    m_axi_ddr_ARLOCK,
output     [3:0]                                    m_axi_ddr_ARCACHE,
output     [2:0]                                    m_axi_ddr_ARPROT,
output     [3:0]                                    m_axi_ddr_ARQOS,
output     [3:0]                                    m_axi_ddr_ARREGION,
output     [0:0]                                    m_axi_ddr_ARUSER,

// 读数据通道
input                                               m_axi_ddr_RVALID,
output                                              m_axi_ddr_RREADY,
input      [31:0]                                   m_axi_ddr_RDATA,
input                                               m_axi_ddr_RLAST,
input      [0:0]                                    m_axi_ddr_RID,
input      [0:0]                                    m_axi_ddr_RUSER,
input      [1:0]                                    m_axi_ddr_RRESP
);

// HLS 预处理核固定输出 28 列、13 位、单通道；对应的 LeNet 参数须保持一致。
wire [QUANT_SIZE*LINE_LEN-1:0] image_data;
wire image_data_valid;
wire image_data_ready;
wire [404:0] lenet_dbg_bus;

// ============================================================================
// 预处理：DDR RGB888 -> 灰度 -> 28x28 -> 逐行交付 LeNet
// ============================================================================
preprocessing #(
    .DDR_BASE_ADDR(DDR_BASE_ADDR)
) u_preprocessing (
    .clk(clk), .rstn(rstn),
    .I_data_valid(I_data_valid), .I_data_ready(I_data_ready),
    .DATA_LINE(image_data), .O_data_valid(image_data_valid),
    .O_data_ready(image_data_ready),

    .m_axi_ddr_AWVALID (m_axi_ddr_AWVALID),
    .m_axi_ddr_AWREADY (m_axi_ddr_AWREADY),
    .m_axi_ddr_AWADDR  (m_axi_ddr_AWADDR),
    .m_axi_ddr_AWID    (m_axi_ddr_AWID),
    .m_axi_ddr_AWLEN   (m_axi_ddr_AWLEN),
    .m_axi_ddr_AWSIZE  (m_axi_ddr_AWSIZE),
    .m_axi_ddr_AWBURST (m_axi_ddr_AWBURST),
    .m_axi_ddr_AWLOCK  (m_axi_ddr_AWLOCK),
    .m_axi_ddr_AWCACHE (m_axi_ddr_AWCACHE),
    .m_axi_ddr_AWPROT  (m_axi_ddr_AWPROT),
    .m_axi_ddr_AWQOS   (m_axi_ddr_AWQOS),
    .m_axi_ddr_AWREGION(m_axi_ddr_AWREGION),
    .m_axi_ddr_AWUSER  (m_axi_ddr_AWUSER),

    .m_axi_ddr_WVALID  (m_axi_ddr_WVALID),
    .m_axi_ddr_WREADY  (m_axi_ddr_WREADY),
    .m_axi_ddr_WDATA   (m_axi_ddr_WDATA),
    .m_axi_ddr_WSTRB   (m_axi_ddr_WSTRB),
    .m_axi_ddr_WLAST   (m_axi_ddr_WLAST),
    .m_axi_ddr_WID     (m_axi_ddr_WID),
    .m_axi_ddr_WUSER   (m_axi_ddr_WUSER),

    .m_axi_ddr_BVALID  (m_axi_ddr_BVALID),
    .m_axi_ddr_BREADY  (m_axi_ddr_BREADY),
    .m_axi_ddr_BRESP   (m_axi_ddr_BRESP),
    .m_axi_ddr_BID     (m_axi_ddr_BID),
    .m_axi_ddr_BUSER   (m_axi_ddr_BUSER),

    .m_axi_ddr_ARVALID (m_axi_ddr_ARVALID),
    .m_axi_ddr_ARREADY (m_axi_ddr_ARREADY),
    .m_axi_ddr_ARADDR  (m_axi_ddr_ARADDR),
    .m_axi_ddr_ARID    (m_axi_ddr_ARID),
    .m_axi_ddr_ARLEN   (m_axi_ddr_ARLEN),
    .m_axi_ddr_ARSIZE  (m_axi_ddr_ARSIZE),
    .m_axi_ddr_ARBURST (m_axi_ddr_ARBURST),
    .m_axi_ddr_ARLOCK  (m_axi_ddr_ARLOCK),
    .m_axi_ddr_ARCACHE (m_axi_ddr_ARCACHE),
    .m_axi_ddr_ARPROT  (m_axi_ddr_ARPROT),
    .m_axi_ddr_ARQOS   (m_axi_ddr_ARQOS),
    .m_axi_ddr_ARREGION(m_axi_ddr_ARREGION),
    .m_axi_ddr_ARUSER  (m_axi_ddr_ARUSER),

    .m_axi_ddr_RVALID  (m_axi_ddr_RVALID),
    .m_axi_ddr_RREADY  (m_axi_ddr_RREADY),
    .m_axi_ddr_RDATA   (m_axi_ddr_RDATA),
    .m_axi_ddr_RLAST   (m_axi_ddr_RLAST),
    .m_axi_ddr_RID     (m_axi_ddr_RID),
    .m_axi_ddr_RUSER   (m_axi_ddr_RUSER),
    .m_axi_ddr_RRESP   (m_axi_ddr_RRESP)
);

// LeNet 行输入接预处理输出；PL 对外 O_data_valid/O_data_ready 仍表示分类结果。
LeNet_top#(
    .QUANT_SIZE(QUANT_SIZE), .WEIGHT_SIZE(WEIGHT_SIZE),
    .LINE_LEN(LINE_LEN), .PADDING(PADDING), .CONV_CORE(CONV_CORE),
    .CHANNEL_I_1(CHANNEL_I_1), .CHANNEL_O_1(CHANNEL_O_1),
    .CHANNEL_O_2(CHANNEL_O_2), .CHANNEL_O_3(CHANNEL_O_3),
    .CHANNEL_O_4(CHANNEL_O_4), .CHANNEL_O_5(CHANNEL_O_5)
) lenet(
    .clk(clk), .rstn(rstn), .DATA_LINE(image_data),
    .I_data_valid(image_data_valid), .I_data_ready(image_data_ready),
    .result_q(result_q), .valid_debug(valid_debug),
    .ready_debug(ready_debug),
    .O_data_valid(O_data_valid),
    .O_data_ready(O_data_ready),
    .dbg_bus(lenet_dbg_bus)
);

assign dbg_bus = { lenet_dbg_bus, 30'd0 };

endmodule
