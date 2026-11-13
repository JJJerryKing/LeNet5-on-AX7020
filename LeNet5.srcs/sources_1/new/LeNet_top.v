module LeNet_top#(
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
input                                                   clk         ,
input                                                   rstn        ,
input       [QUANT_SIZE*LINE_LEN*CHANNEL_I_1-1:0]       DATA_LINE   ,
input                                                   I_data_valid,
output                                                  I_data_ready,
output      [clogb2(CHANNEL_O_5)-1:0]                   result_q    ,
output      [9:0]                                       valid_debug,
output      [9:0]                                       ready_debug,
output                                                  O_data_valid,
input                                                   O_data_ready,
/*
调试观测总线（只读，不改变原有逻辑）：405 bit
[  7:  0] top_fsm_dbg    {idx[5:0], conv1_input_valid, I_data_ready}
[ 73:  8] conv1_dbg      {mac[13:0], line_loader_plus dbg[51:0]}
[ 77: 74] relu1_dbg
[ 97: 78] pool1_dbg
[119: 98] line_cache1_dbg
[185:120] conv2_dbg      {mac[13:0], line_loader_plus dbg[51:0]}
[189:186] relu2_dbg
[209:190] pool2_dbg
[231:210] line_cache2_dbg
[297:232] conv3_dbg      {mac[13:0], line_loader_plus dbg[51:0]}
[346:298] fc1_dbg        {mac[13:0], fullconnect dbg[34:0]}
[395:347] op_dbg         {mac[13:0], fullconnect dbg[34:0]}
[404:396] argmax_dbg
*/
output      [404:0]                                     dbg_bus
);

localparam PADDED_LINE_LEN = LINE_LEN + PADDING*2;
localparam ADDSIZE         = 2;

/* 调试观测总线内部连线（只读，不参与任何原有逻辑）。 */
wire [7:0]  top_fsm_dbg;
wire [13:0] conv1_mac_dbg, conv2_mac_dbg, conv3_mac_dbg;
wire [51:0] conv1_ll_dbg,  conv2_ll_dbg,  conv3_ll_dbg;
wire [3:0]  relu1_dbg, relu2_dbg;
wire [19:0] pool1_dbg, pool2_dbg;
wire [21:0] line_cache1_dbg, line_cache2_dbg;
wire [48:0] fc1_dbg, op_dbg;
wire [8:0]  argmax_dbg;

localparam [WEIGHT_SIZE-1:0] C1_SCALE = 13'd12;
localparam [WEIGHT_SIZE-1:0] C1_SHIFT = 13'd11;
localparam [WEIGHT_SIZE-1:0] C1_ZERO  = 13'd83;
localparam [WEIGHT_SIZE-1:0] C3_SCALE = 13'd14;
localparam [WEIGHT_SIZE-1:0] C3_SHIFT = 13'd12;
localparam [WEIGHT_SIZE-1:0] C3_ZERO  = 13'd142;
localparam [WEIGHT_SIZE-1:0] C5_SCALE = 13'd11;
localparam [WEIGHT_SIZE-1:0] C5_SHIFT = 13'd13;
localparam [WEIGHT_SIZE-1:0] C5_ZERO  = 13'd128;
localparam [WEIGHT_SIZE-1:0] F6_SCALE = 13'd13;
localparam [WEIGHT_SIZE-1:0] F6_SHIFT = 13'd13;
localparam [WEIGHT_SIZE-1:0] F6_ZERO  = 13'd115;
localparam [WEIGHT_SIZE-1:0] OP_SCALE = 13'd13;
localparam [WEIGHT_SIZE-1:0] OP_SHIFT = 13'd12;
localparam [WEIGHT_SIZE-1:0] OP_ZERO  = 13'd129;

/* 输入行补零：先发送两行零，再发送28行左右补零的数据，最后发送两行零。 */
reg [5:0] idx;
reg conv1_input_valid;
reg [QUANT_SIZE*PADDED_LINE_LEN*CHANNEL_I_1-1:0] padded_data_line;
wire conv1_input_ready;

assign I_data_ready = rstn && (idx >= 3) && (idx <= 30) &&
                      (!conv1_input_valid || conv1_input_ready);

always @(posedge clk) begin
    if(!rstn) begin
        idx               <= 1;
        padded_data_line  <= 'd0;
        conv1_input_valid <= 1'b0;
    end else if(!conv1_input_valid || conv1_input_ready) begin
        if(idx == 1 || idx == 2 || idx == 31 || idx == 32) begin
            padded_data_line  <= 'd0;
            conv1_input_valid <= 1'b1;
            if(idx == 32)
                idx <= 1;
            else
                idx <= idx + 1'b1;
        end else if(I_data_valid && I_data_ready) begin
            padded_data_line  <= {{QUANT_SIZE*PADDING{1'b0}},
                                  DATA_LINE,
                                  {QUANT_SIZE*PADDING{1'b0}}};
            conv1_input_valid <= 1'b1;
            idx               <= idx + 1'b1;
        end else begin
            conv1_input_valid <= 1'b0;
        end
    end
end

/* 权重ROM与零点换算。 */
wire [2:0] c1_w_addr;
wire [199:0] c1_weight;
wire [WEIGHT_SIZE*25-1:0] c1_weight_qx_zeropoint;
blkmem_c1_weight c1_weight_mem(
    .clka(clk), .ena(1'b1), .addra(c1_w_addr), .douta(c1_weight)
);

wire [4:0] c3_w_addr;
wire [3:0] c3_w_rom_addr;
wire [1199:0] c3_weight;
wire [WEIGHT_SIZE*6*25-1:0] c3_weight_qx_zeropoint;
assign c3_w_rom_addr = c3_w_addr[3:0];
blkmem_c3_weight c3_weight_mem(
    .clka(clk), .ena(1'b1), .addra(c3_w_rom_addr), .douta(c3_weight)
);

wire [6:0] c5_w_addr;
wire [3199:0] c5_weight;
wire [WEIGHT_SIZE*16*25-1:0] c5_weight_qx_zeropoint;
blkmem_c5_weight c5_weight_mem(
    .clka(clk), .ena(1'b1), .addra(c5_w_addr), .douta(c5_weight)
);

wire [6:0] f6_w_addr;
wire [959:0] f6_weight;
wire [WEIGHT_SIZE*120-1:0] f6_weight_qx_zeropoint;
blkmem_f6_weight f6_weight_mem(
    .clka(clk), .ena(1'b1), .addra(f6_w_addr), .douta(f6_weight)
);

wire [3:0] op_w_addr;
wire [671:0] op_weight;
wire [WEIGHT_SIZE*84-1:0] op_weight_qx_zeropoint;
blkmem_output_weight op_weight_mem(
    .clka(clk), .ena(1'b1), .addra(op_w_addr), .douta(op_weight)
);

genvar c1_weight_i;
generate
    for(c1_weight_i=0; c1_weight_i<25; c1_weight_i=c1_weight_i+1) begin: C1_WEIGHT_ZEROPOINT
        assign c1_weight_qx_zeropoint[c1_weight_i*WEIGHT_SIZE+:WEIGHT_SIZE] =
               c1_weight[c1_weight_i*8+:8] - C1_ZERO;
    end
endgenerate

genvar c3_weight_i;
generate
    for(c3_weight_i=0; c3_weight_i<6*25; c3_weight_i=c3_weight_i+1) begin: C3_WEIGHT_ZEROPOINT
        assign c3_weight_qx_zeropoint[c3_weight_i*WEIGHT_SIZE+:WEIGHT_SIZE] =
               c3_weight[c3_weight_i*8+:8] - C3_ZERO;
    end
endgenerate

genvar c5_weight_i;
generate
    for(c5_weight_i=0; c5_weight_i<16*25; c5_weight_i=c5_weight_i+1) begin: C5_WEIGHT_ZEROPOINT
        assign c5_weight_qx_zeropoint[c5_weight_i*WEIGHT_SIZE+:WEIGHT_SIZE] =
               c5_weight[c5_weight_i*8+:8] - C5_ZERO;
    end
endgenerate

genvar f6_weight_i;
generate
    for(f6_weight_i=0; f6_weight_i<120; f6_weight_i=f6_weight_i+1) begin: F6_WEIGHT_ZEROPOINT
        assign f6_weight_qx_zeropoint[f6_weight_i*WEIGHT_SIZE+:WEIGHT_SIZE] =
               f6_weight[f6_weight_i*8+:8] - F6_ZERO;
    end
endgenerate

genvar op_weight_i;
generate
    for(op_weight_i=0; op_weight_i<84; op_weight_i=op_weight_i+1) begin: OP_WEIGHT_ZEROPOINT
        assign op_weight_qx_zeropoint[op_weight_i*WEIGHT_SIZE+:WEIGHT_SIZE] =
               op_weight[op_weight_i*8+:8] - OP_ZERO;
    end
endgenerate

/* 偏置ROM。 */
wire [2:0] c1_b_addr;
wire signed [31:0] c1_bias;
blkmem_c1_bias c1_bias_mem(
    .clka(clk), .ena(1'b1), .addra(c1_b_addr), .douta(c1_bias)
);

wire [4:0] c3_b_addr;
wire [3:0] c3_b_rom_addr;
wire signed [31:0] c3_bias;
assign c3_b_rom_addr = c3_b_addr[3:0];
blkmem_c3_bias c3_bias_mem(
    .clka(clk), .ena(1'b1), .addra(c3_b_rom_addr), .douta(c3_bias)
);

wire [6:0] c5_b_addr;
wire signed [31:0] c5_bias;
blkmem_c5_bias c5_bias_mem(
    .clka(clk), .ena(1'b1), .addra(c5_b_addr), .douta(c5_bias)
);

wire [6:0] f6_b_addr;
wire signed [31:0] f6_bias;
blkmem_f6_bias f6_bias_mem(
    .clka(clk), .ena(1'b1), .addra(f6_b_addr), .douta(f6_bias)
);

wire [3:0] op_b_addr;
wire signed [31:0] op_bias;
blkmem_output_bias op_bias_mem(
    .clka(clk), .ena(1'b1), .addra(op_b_addr), .douta(op_bias)
);

/* 第一层卷积、ReLU和池化。 */
wire [QUANT_SIZE*CHANNEL_O_1-1:0] conv1_out;
wire conv1_out_valid;
wire conv1_out_ready;
line_loader_plus#(
    .QUANT_SIZE(QUANT_SIZE), .WEIGHT_SIZE(WEIGHT_SIZE),
    .LINE_LEN(PADDED_LINE_LEN), .PIPES(5), .CONV_CORE(CONV_CORE),
    .CHANNEL_I(CHANNEL_I_1), .CHANNEL_O(CHANNEL_O_1), .ADDSIZE(0)
) conv1(
    .clk(clk), .rstn(rstn), .LOAD_INIT(1'b1),
    .DATA_LINE(padded_data_line),
    .weight_input(c1_weight_qx_zeropoint), .weight_addr(c1_w_addr),
    .bias_input(c1_bias), .bias_addr(c1_b_addr),
    .SCALE(C1_SCALE), .SHIFT(C1_SHIFT),
    .I_data_valid(conv1_input_valid), .I_data_ready(conv1_input_ready),
    .result_q(conv1_out), .O_data_valid(conv1_out_valid),
    .O_data_ready(conv1_out_ready),
    .dbg(conv1_ll_dbg), .dbg_mac(conv1_mac_dbg)
);

wire [QUANT_SIZE*CHANNEL_O_1-1:0] relu1_out;
wire relu1_out_valid;
wire relu1_out_ready;
relu_plus#(
    .QUANT_SIZE(QUANT_SIZE), .LINE_LEN(LINE_LEN), .CORE_NUMS(CHANNEL_O_1)
) relu1(
    .clk(clk), .rstn(rstn), .data_in(conv1_out),
    .I_relu_valid(conv1_out_valid), .I_relu_ready(conv1_out_ready),
    .relu_out(relu1_out), .O_relu_valid(relu1_out_valid),
    .O_relu_ready(relu1_out_ready),
    .dbg(relu1_dbg)
);

wire [QUANT_SIZE*CHANNEL_O_1-1:0] pool1_out;
wire pool1_out_valid;
wire pool1_out_ready;
average_pooling#(
    .QUANT_SIZE(QUANT_SIZE), .LINE_LEN(LINE_LEN), .CORE_NUMS(CHANNEL_O_1)
) average_pooling_1(
    .clk(clk), .rstn(rstn), .data_in(relu1_out),
    .I_data_valid(relu1_out_valid), .I_data_ready(relu1_out_ready),
    .pool_out(pool1_out), .O_data_valid(pool1_out_valid),
    .O_data_ready(pool1_out_ready),
    .dbg(pool1_dbg)
);

wire [CHANNEL_O_1*14*QUANT_SIZE-1:0] line_cache_1;
wire line_cache1_valid;
wire line_cache1_ready;
Line_Cache2#(
    .QUANT_SIZE(QUANT_SIZE), .LINE_LEN(14), .CORE_NUMS(CHANNEL_O_1)
) line_cache1(
    .clk(clk), .rstn(rstn), .data_in(pool1_out),
    .I_data_valid(pool1_out_valid), .I_data_ready(pool1_out_ready),
    .data_out(line_cache_1), .O_data_valid(line_cache1_valid),
    .O_data_ready(line_cache1_ready),
    .dbg(line_cache1_dbg)
);

/* 第二层卷积、ReLU和池化。 */
wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_2-1:0] conv2_out;
wire conv2_out_valid;
wire conv2_out_ready;
line_loader_plus#(
    .QUANT_SIZE(QUANT_SIZE), .WEIGHT_SIZE(WEIGHT_SIZE),
    .LINE_LEN(14), .PIPES(5),
    .CONV_CORE(CONV_CORE), .CHANNEL_I(CHANNEL_O_1),
    .CHANNEL_O(CHANNEL_O_2), .ADDSIZE(ADDSIZE)
) conv2(
    .clk(clk), .rstn(rstn), .LOAD_INIT(1'b1),
    .DATA_LINE(line_cache_1),
    .weight_input(c3_weight_qx_zeropoint), .weight_addr(c3_w_addr),
    .bias_input(c3_bias), .bias_addr(c3_b_addr),
    .SCALE(C3_SCALE), .SHIFT(C3_SHIFT),
    .I_data_valid(line_cache1_valid), .I_data_ready(line_cache1_ready),
    .result_q(conv2_out), .O_data_valid(conv2_out_valid),
    .O_data_ready(conv2_out_ready),
    .dbg(conv2_ll_dbg), .dbg_mac(conv2_mac_dbg)
);

wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_2-1:0] relu2_out;
wire relu2_out_valid;
wire relu2_out_ready;
relu_plus#(
    .QUANT_SIZE(QUANT_SIZE+ADDSIZE), .LINE_LEN(10), .CORE_NUMS(CHANNEL_O_2)
) relu2(
    .clk(clk), .rstn(rstn), .data_in(conv2_out),
    .I_relu_valid(conv2_out_valid), .I_relu_ready(conv2_out_ready),
    .relu_out(relu2_out), .O_relu_valid(relu2_out_valid),
    .O_relu_ready(relu2_out_ready),
    .dbg(relu2_dbg)
);

wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_2-1:0] pool2_out;
wire pool2_out_valid;
wire pool2_out_ready;
average_pooling#(
    .QUANT_SIZE(QUANT_SIZE+ADDSIZE), .LINE_LEN(10), .CORE_NUMS(CHANNEL_O_2)
) average_pooling_2(
    .clk(clk), .rstn(rstn), .data_in(relu2_out),
    .I_data_valid(relu2_out_valid), .I_data_ready(relu2_out_ready),
    .pool_out(pool2_out), .O_data_valid(pool2_out_valid),
    .O_data_ready(pool2_out_ready),
    .dbg(pool2_dbg)
);

wire [QUANT_SIZE*CHANNEL_O_2-1:0] pool2_out_low_bit;
genvar pool2_channel_i;
generate
    for(pool2_channel_i=0; pool2_channel_i<CHANNEL_O_2; pool2_channel_i=pool2_channel_i+1) begin: POOL2_TRUNCATE
        assign pool2_out_low_bit[pool2_channel_i*QUANT_SIZE+:QUANT_SIZE] =
               pool2_out[pool2_channel_i*(QUANT_SIZE+ADDSIZE)+:QUANT_SIZE];
    end
endgenerate

wire [CHANNEL_O_2*5*QUANT_SIZE-1:0] line_cache_2;
wire line_cache2_valid;
wire line_cache2_ready;
Line_Cache2#(
    .QUANT_SIZE(QUANT_SIZE), .LINE_LEN(5), .CORE_NUMS(CHANNEL_O_2)
) line_cache2(
    .clk(clk), .rstn(rstn), .data_in(pool2_out_low_bit),
    .I_data_valid(pool2_out_valid), .I_data_ready(pool2_out_ready),
    .data_out(line_cache_2), .O_data_valid(line_cache2_valid),
    .O_data_ready(line_cache2_ready),
    .dbg(line_cache2_dbg)
);

/* 第三层卷积与位宽截取。 */
wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_3-1:0] conv3_out;
wire conv3_out_valid;
wire conv3_out_ready;
line_loader_plus#(
    .QUANT_SIZE(QUANT_SIZE), .WEIGHT_SIZE(WEIGHT_SIZE),
    .LINE_LEN(5), .PIPES(5),
    .CONV_CORE(CONV_CORE), .CHANNEL_I(CHANNEL_O_2),
    .CHANNEL_O(CHANNEL_O_3), .ADDSIZE(ADDSIZE)
) conv3(
    .clk(clk), .rstn(rstn), .LOAD_INIT(1'b1),
    .DATA_LINE(line_cache_2),
    .weight_input(c5_weight_qx_zeropoint), .weight_addr(c5_w_addr),
    .bias_input(c5_bias), .bias_addr(c5_b_addr),
    .SCALE(C5_SCALE), .SHIFT(C5_SHIFT),
    .I_data_valid(line_cache2_valid), .I_data_ready(line_cache2_ready),
    .result_q(conv3_out), .O_data_valid(conv3_out_valid),
    .O_data_ready(conv3_out_ready),
    .dbg(conv3_ll_dbg), .dbg_mac(conv3_mac_dbg)
);

wire [QUANT_SIZE*CHANNEL_O_3-1:0] conv3_out_low_bit;
genvar conv3_channel_i;
generate
    for(conv3_channel_i=0; conv3_channel_i<CHANNEL_O_3; conv3_channel_i=conv3_channel_i+1) begin: CONV3_TRUNCATE
        assign conv3_out_low_bit[conv3_channel_i*QUANT_SIZE+:QUANT_SIZE] =
               conv3_out[conv3_channel_i*(QUANT_SIZE+ADDSIZE)+:QUANT_SIZE];
    end
endgenerate

/* 两层全连接。 */
wire [QUANT_SIZE*CHANNEL_O_4-1:0] fc1_output;
wire fc1_out_valid;
wire fc1_out_ready;
fullconnect#(
    .QUANT_SIZE(QUANT_SIZE), .WEIGHT_SIZE(WEIGHT_SIZE),
    .LINE_LEN(CHANNEL_O_3), .LINE_LEN_O(CHANNEL_O_4),
    .PIPES(20), .ADDSIZE(0)
) fc1(
    .clk(clk), .rstn(rstn), .DATA_LINE(conv3_out_low_bit),
    .weight_input(f6_weight_qx_zeropoint), .weight_addr(f6_w_addr),
    .bias_input(f6_bias), .bias_addr(f6_b_addr),
    .SCALE(F6_SCALE), .SHIFT(F6_SHIFT),
    .I_data_valid(conv3_out_valid), .I_data_ready(conv3_out_ready),
    .result_q(fc1_output), .O_data_valid(fc1_out_valid),
    .O_data_ready(fc1_out_ready),
    .dbg(fc1_dbg)
);

wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_5-1:0] op_output;
wire op_out_valid;
wire op_out_ready;
fullconnect#(
    .QUANT_SIZE(QUANT_SIZE), .WEIGHT_SIZE(WEIGHT_SIZE),
    .LINE_LEN(CHANNEL_O_4), .LINE_LEN_O(CHANNEL_O_5),
    .PIPES(2), .ADDSIZE(ADDSIZE)
) op(
    .clk(clk), .rstn(rstn), .DATA_LINE(fc1_output),
    .weight_input(op_weight_qx_zeropoint), .weight_addr(op_w_addr),
    .bias_input(op_bias), .bias_addr(op_b_addr),
    .SCALE(OP_SCALE), .SHIFT(OP_SHIFT),
    .I_data_valid(fc1_out_valid), .I_data_ready(fc1_out_ready),
    .result_q(op_output), .O_data_valid(op_out_valid),
    .O_data_ready(op_out_ready),
    .dbg(op_dbg)
);

/* 组合比较得到最终类别编号。 */
argmax#(
    .QUANT_SIZE(QUANT_SIZE+ADDSIZE), .CLASS_NUMS(CHANNEL_O_5)
) argmax_1(
    .clk(clk), .rstn(rstn), .data_in(op_output),
    .I_data_valid(op_out_valid), .I_data_ready(op_out_ready),
    .result_q(result_q), .O_data_valid(O_data_valid),
    .O_data_ready(O_data_ready),
    .dbg(argmax_dbg)
);

/* ILA probe6[9:0]：从第一层卷积到最终分类输出的关键valid信号。 */
assign valid_debug = {
    O_data_valid,
    op_out_valid,
    fc1_out_valid,
    conv3_out_valid,
    line_cache2_valid,
    pool2_out_valid,
    conv2_out_valid,
    line_cache1_valid,
    pool1_out_valid,
    conv1_out_valid
};

/* ILA probe7[9:0]：与valid_debug位序一一对应的ready信号。 */
assign ready_debug = {
    O_data_ready,
    op_out_ready,
    fc1_out_ready,
    conv3_out_ready,
    line_cache2_ready,
    pool2_out_ready,
    conv2_out_ready,
    line_cache1_ready,
    pool1_out_ready,
    conv1_out_ready
};

/*
调试观测总线（纯连线，不改变任何原有逻辑）：位定义见端口注释。
*/
assign top_fsm_dbg = { idx, conv1_input_valid, I_data_ready };

assign dbg_bus = { argmax_dbg,                                  // [404:396]
                   op_dbg,                                      // [395:347]
                   fc1_dbg,                                     // [346:298]
                   conv3_mac_dbg, conv3_ll_dbg,                 // [297:232]
                   line_cache2_dbg, pool2_dbg, relu2_dbg,       // [231:186]
                   conv2_mac_dbg, conv2_ll_dbg,                 // [185:120]
                   line_cache1_dbg, pool1_dbg, relu1_dbg,       // [119: 74]
                   conv1_mac_dbg, conv1_ll_dbg,                 // [ 73:  8]
                   top_fsm_dbg };                               // [  7:  0]

function integer clogb2(input integer number);
begin
    for(clogb2=0; number>0; clogb2=clogb2+1)
        number = number >> 1;
end
endfunction

endmodule
