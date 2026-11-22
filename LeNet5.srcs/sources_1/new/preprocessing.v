`timescale 1ns / 1ps

/*
 * RGB 图片预处理封装：
 * 1. I_data_valid/I_data_ready 接受一次整帧处理请求。
 * 2. resize_and_gray 通过 AXI Master 读取固定 DDR 基址处的参数和 RGB888。
 * 3. DATA_LINE/O_data_valid/O_data_ready 向 LeNet 逐行交付 28 行数据。
 *
 * 数据格式与 HLS IP 固定一致：28 列、每像素 13 位，DATA_LINE 共 364 位。
 * HLS AXIS 为 368 位，丢弃高 4 位补零；不再增加输出缓存。
 * 本模块和 LeNet 使用同一 clk/rstn，rstn 为低有效复位。
 *
 * DDR_BASE_ADDR 当前默认取 0x10000000；PS 必须在同一地址写入参数和图片，
 * 并为该内存块保留空间。此参数固定连接 IP 的 ddr_offset，不是运行时端口。
 */
module preprocessing #(
    parameter [31:0] DDR_BASE_ADDR = 32'h10000000
)(
    // ========================================================================
    // 时钟、复位与整帧请求
    // ========================================================================
    input               clk,
    input               rstn,
    input               I_data_valid,
    output              I_data_ready,

    // ========================================================================
    // LeNet 行数据接口：每次 valid/ready 握手交付一整行
    // ========================================================================
    output [363:0]      DATA_LINE,
    output              O_data_valid,
    input               O_data_ready,

    // ========================================================================
    // AXI Master 写地址通道：按 HLS IP 原接口完整引出
    // 当前预处理流程只读 DDR，写通道是否使用由 IP 决定。
    // ========================================================================
    output              m_axi_ddr_AWVALID,
    input               m_axi_ddr_AWREADY,
    output [31:0]       m_axi_ddr_AWADDR,
    output [0:0]        m_axi_ddr_AWID,
    output [7:0]        m_axi_ddr_AWLEN,
    output [2:0]        m_axi_ddr_AWSIZE,
    output [1:0]        m_axi_ddr_AWBURST,
    output [1:0]        m_axi_ddr_AWLOCK,
    output [3:0]        m_axi_ddr_AWCACHE,
    output [2:0]        m_axi_ddr_AWPROT,
    output [3:0]        m_axi_ddr_AWQOS,
    output [3:0]        m_axi_ddr_AWREGION,
    output [0:0]        m_axi_ddr_AWUSER,

    // AXI Master 写数据通道
    output              m_axi_ddr_WVALID,
    input               m_axi_ddr_WREADY,
    output [31:0]       m_axi_ddr_WDATA,
    output [3:0]        m_axi_ddr_WSTRB,
    output              m_axi_ddr_WLAST,
    output [0:0]        m_axi_ddr_WID,
    output [0:0]        m_axi_ddr_WUSER,

    // AXI Master 写响应通道
    input               m_axi_ddr_BVALID,
    output              m_axi_ddr_BREADY,
    input [1:0]         m_axi_ddr_BRESP,
    input [0:0]         m_axi_ddr_BID,
    input [0:0]         m_axi_ddr_BUSER,

    // ========================================================================
    // AXI Master 读地址通道
    // ========================================================================
    output              m_axi_ddr_ARVALID,
    input               m_axi_ddr_ARREADY,
    output [31:0]       m_axi_ddr_ARADDR,
    output [0:0]        m_axi_ddr_ARID,
    output [7:0]        m_axi_ddr_ARLEN,
    output [2:0]        m_axi_ddr_ARSIZE,
    output [1:0]        m_axi_ddr_ARBURST,
    output [1:0]        m_axi_ddr_ARLOCK,
    output [3:0]        m_axi_ddr_ARCACHE,
    output [2:0]        m_axi_ddr_ARPROT,
    output [3:0]        m_axi_ddr_ARQOS,
    output [3:0]        m_axi_ddr_ARREGION,
    output [0:0]        m_axi_ddr_ARUSER,

    // AXI Master 读数据通道
    input               m_axi_ddr_RVALID,
    output              m_axi_ddr_RREADY,
    input [31:0]        m_axi_ddr_RDATA,
    input               m_axi_ddr_RLAST,
    input [0:0]         m_axi_ddr_RID,
    input [0:0]         m_axi_ddr_RUSER,
    input [1:0]         m_axi_ddr_RRESP
);

// ============================================================================
// 帧控制状态：不复制 HLS 的内部状态机，只管理本模块接受的整帧事务
// ============================================================================
localparam [4:0] LINE_NUMS = 5'd28;

reg             busy;
reg             ap_start;
reg             done_seen;
reg [4:0]       row_count;

wire            ap_done;
wire            ap_idle;
wire            ap_ready;
wire [367:0]    axis_data;
wire            axis_valid;

assign I_data_ready = rstn && !busy && ap_idle;

// 行输出直接使用 IP 的 AXIS 缓存，valid 不依赖下游 ready。
assign DATA_LINE    = axis_data[363:0];
assign O_data_valid = rstn && axis_valid;

always @(posedge clk) begin
    if (!rstn) begin
        busy      <= 1'b0;
        ap_start  <= 1'b0;
        done_seen <= 1'b0;
        row_count <= 5'd0;
    end else if (I_data_valid && I_data_ready) begin
        busy      <= 1'b1;
        ap_start  <= 1'b1;
        done_seen <= 1'b0;
        row_count <= 5'd0;
    end else if (busy) begin
        // HLS 启动请求保持到 ap_ready 确认，不能只发送一个任意宽度脉冲。
        if (ap_ready)
            ap_start <= 1'b0;

        // ap_done 可能先于最后一行被 LeNet 接收，必须记住其有效事件。
        if (ap_done)
            done_seen <= 1'b1;

        // 只统计模块对外真正发生的行握手，计满 28 后保持。
        if (O_data_valid && O_data_ready && row_count < LINE_NUMS)
            row_count <= row_count + 1'b1;

        // 两个完成条件可以任意先后到达。
        // 最后一行握手后 row_count 在下一拍达到 28，再释放 busy。
        if ((done_seen || ap_done) && row_count == LINE_NUMS) begin
            busy      <= 1'b0;
            ap_start  <= 1'b0;
            done_seen <= 1'b0;
        end
    end
end

// ============================================================================
// HLS IP 实例：端口名称和位宽对应当前生成的 resize_and_gray RTL
// ============================================================================
u_resize_and_gray u_hls (
    .ap_clk                     (clk),
    .ap_rst_n                   (rstn),
    .ap_start                   (ap_start),
    .ap_done                    (ap_done),
    .ap_idle                    (ap_idle),
    .ap_ready                   (ap_ready),

    .ddr_offset                 (DDR_BASE_ADDR),
    .DATA_LINE_V_V_TDATA         (axis_data),
    .DATA_LINE_V_V_TVALID        (axis_valid),
    .DATA_LINE_V_V_TREADY        (rstn && O_data_ready),

    .m_axi_ddr_AWVALID           (m_axi_ddr_AWVALID),
    .m_axi_ddr_AWREADY           (m_axi_ddr_AWREADY),
    .m_axi_ddr_AWADDR            (m_axi_ddr_AWADDR),
    .m_axi_ddr_AWID              (m_axi_ddr_AWID),
    .m_axi_ddr_AWLEN             (m_axi_ddr_AWLEN),
    .m_axi_ddr_AWSIZE            (m_axi_ddr_AWSIZE),
    .m_axi_ddr_AWBURST           (m_axi_ddr_AWBURST),
    .m_axi_ddr_AWLOCK            (m_axi_ddr_AWLOCK),
    .m_axi_ddr_AWCACHE           (m_axi_ddr_AWCACHE),
    .m_axi_ddr_AWPROT            (m_axi_ddr_AWPROT),
    .m_axi_ddr_AWQOS             (m_axi_ddr_AWQOS),
    .m_axi_ddr_AWREGION          (m_axi_ddr_AWREGION),
    .m_axi_ddr_AWUSER            (m_axi_ddr_AWUSER),

    .m_axi_ddr_WVALID            (m_axi_ddr_WVALID),
    .m_axi_ddr_WREADY            (m_axi_ddr_WREADY),
    .m_axi_ddr_WDATA             (m_axi_ddr_WDATA),
    .m_axi_ddr_WSTRB             (m_axi_ddr_WSTRB),
    .m_axi_ddr_WLAST             (m_axi_ddr_WLAST),
    .m_axi_ddr_WID               (m_axi_ddr_WID),
    .m_axi_ddr_WUSER             (m_axi_ddr_WUSER),

    .m_axi_ddr_BVALID            (m_axi_ddr_BVALID),
    .m_axi_ddr_BREADY            (m_axi_ddr_BREADY),
    .m_axi_ddr_BRESP             (m_axi_ddr_BRESP),
    .m_axi_ddr_BID               (m_axi_ddr_BID),
    .m_axi_ddr_BUSER             (m_axi_ddr_BUSER),

    .m_axi_ddr_ARVALID           (m_axi_ddr_ARVALID),
    .m_axi_ddr_ARREADY           (m_axi_ddr_ARREADY),
    .m_axi_ddr_ARADDR            (m_axi_ddr_ARADDR),
    .m_axi_ddr_ARID              (m_axi_ddr_ARID),
    .m_axi_ddr_ARLEN             (m_axi_ddr_ARLEN),
    .m_axi_ddr_ARSIZE            (m_axi_ddr_ARSIZE),
    .m_axi_ddr_ARBURST           (m_axi_ddr_ARBURST),
    .m_axi_ddr_ARLOCK            (m_axi_ddr_ARLOCK),
    .m_axi_ddr_ARCACHE           (m_axi_ddr_ARCACHE),
    .m_axi_ddr_ARPROT            (m_axi_ddr_ARPROT),
    .m_axi_ddr_ARQOS             (m_axi_ddr_ARQOS),
    .m_axi_ddr_ARREGION          (m_axi_ddr_ARREGION),
    .m_axi_ddr_ARUSER            (m_axi_ddr_ARUSER),

    .m_axi_ddr_RVALID            (m_axi_ddr_RVALID),
    .m_axi_ddr_RREADY            (m_axi_ddr_RREADY),
    .m_axi_ddr_RDATA             (m_axi_ddr_RDATA),
    .m_axi_ddr_RLAST             (m_axi_ddr_RLAST),
    .m_axi_ddr_RID               (m_axi_ddr_RID),
    .m_axi_ddr_RUSER             (m_axi_ddr_RUSER),
    .m_axi_ddr_RRESP             (m_axi_ddr_RRESP)
);

endmodule
