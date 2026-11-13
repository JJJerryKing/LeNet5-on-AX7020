module average_pooling#(
 parameter QUANT_SIZE = 12 ,
 parameter LINE_LEN   = 28 , 
 parameter CORE_NUMS  = 6     

)(
input                                               clk             ,
input                                               rstn            ,
input [QUANT_SIZE*CORE_NUMS - 1   :   0]            data_in         ,
input                                               I_data_valid    ,
output                                              I_data_ready    ,
output [QUANT_SIZE*CORE_NUMS- 1   :   0]            pool_out        ,
output                                              O_data_valid    ,
input                                               O_data_ready    ,
/*
调试观测口：仅引出各通道内部计数（转接通道 0，各通道共用 valid/ready，状态同步）。
*/
output      [19:0]                                  dbg

);
wire [CORE_NUMS-1:0]I_data_ready_0;
assign I_data_ready = &I_data_ready_0;


wire [CORE_NUMS-1:0]O_data_valid_0;                        
assign O_data_valid = &O_data_valid_0;
wire [19:0] dbg_ch [0:CORE_NUMS-1];
genvar pooling_unit;
for (pooling_unit = 0; pooling_unit < CORE_NUMS; pooling_unit = pooling_unit + 1) begin
    AverPooling#(
    .QUANT_SIZE    (   QUANT_SIZE     ),
    .LINE_LEN      (   LINE_LEN       ), 
    .CORE_NUMS     (   CORE_NUMS      )
    ) Pooling1(
        .clk            (  clk                         ),
        .rstn           (  rstn                        ),
        .relu_out       (  data_in[pooling_unit*QUANT_SIZE+:QUANT_SIZE]                   ),
        .I_data_valid   (  I_data_valid           ),
        .I_data_ready   (  I_data_ready_0[pooling_unit]           ),
        .result_q       (  pool_out[pooling_unit*QUANT_SIZE+:QUANT_SIZE]           ),
        .O_data_valid   (  O_data_valid_0[pooling_unit]           ),
        .O_data_ready   (  O_data_ready           ),
        .dbg            (  dbg_ch[pooling_unit]    )
    );
end

/* 调试观测：纯连线引出（通道 0 代表全部通道）。 */
assign dbg = dbg_ch[0];

endmodule
