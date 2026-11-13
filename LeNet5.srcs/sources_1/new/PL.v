module PL#(
 parameter DATA_WIDTH  = 32 ,
 parameter QUANT_SIZE  = 13 ,
 parameter WEIGHT_SIZE = 13 ,
 parameter LINE_LEN    = 28 ,
 parameter LINE_NUMS   = 28 ,
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
input      [DATA_WIDTH-1:0]                         bram_data   ,
// output     [clogb2(LINE_LEN*LINE_NUMS)-1:0]         bram_addr   ,
output     [10-1:0]         bram_addr   ,
output                                              bram_en     ,
input                                               I_data_valid,
output                                              I_data_ready,
// output     [clogb2(CHANNEL_O_5)-1:0]                result_q    ,
output     [10-1:0]                result_q    ,
output     [10-1:0]                valid_debug,
output     [10-1:0]                ready_debug,
output                                              O_data_valid,
input                                               O_data_ready,
/*
调试观测总线（只读，不改变原有逻辑）：435 bit
[ 29:  0] image_reader dbg（30 bit，位定义见 image_reader.v）
[434: 30] LeNet_top dbg_bus（405 bit，位定义见 LeNet_top.v）
*/
output     [434:0]                 dbg_bus
);

wire [QUANT_SIZE*LINE_LEN-1:0] image_data;
wire image_data_valid;
wire image_data_ready;
wire [29:0]  reader_dbg;
wire [404:0] lenet_dbg_bus;

image_reader#(
    .DATA_WIDTH(DATA_WIDTH), .QUANT_SIZE(QUANT_SIZE),
    .LINE_LEN(LINE_LEN), .LINE_NUMS(LINE_NUMS)
) reader(
    .clk(clk), .rstn(rstn),
    .bram_data(bram_data), .bram_addr(bram_addr), .bram_en(bram_en),
    .I_data_valid(I_data_valid), .I_data_ready(I_data_ready),
    .DATA_LINE(image_data), .O_data_valid(image_data_valid),
    .O_data_ready(image_data_ready),
    .dbg(reader_dbg)
);

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

/* 调试观测总线：纯连线拼接，不改变任何原有逻辑。 */
assign dbg_bus = { lenet_dbg_bus, reader_dbg };

function integer clogb2(input integer bit_depth);
integer depth;
begin
    depth = bit_depth - 1;
    for(clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
end
endfunction

endmodule
