module Line_Cache2#(
 parameter QUANT_SIZE = 12 ,
 parameter LINE_LEN   = 14 ,
 parameter CORE_NUMS  = 6 
)(
    input                                               clk,
    input                                               rstn,
    input [QUANT_SIZE *CORE_NUMS -1 : 0]                data_in,
    input                                               I_data_valid,
    output                                              I_data_ready,
    output [CORE_NUMS*QUANT_SIZE*LINE_LEN -  1 : 0]     data_out,
    output                                              O_data_valid,
    input                                               O_data_ready,
    /*
    调试观测口：仅引出各通道内部计数（转接通道 0，各通道共用 valid/ready，状态同步）。
    */
    output      [21:0]                                  dbg
);

function integer clogb2(input integer number);
begin
    for(clogb2 = 0 ; number > 0 ; clogb2 = clogb2 + 1 )
        number = number >> 1;
    end
endfunction
wire [CORE_NUMS-1:0] O_data_valid0;
wire [CORE_NUMS-1:0] I_data_ready0;

assign O_data_valid = & O_data_valid0;
assign I_data_ready = & I_data_ready0;
wire [21:0] dbg_ch [0:CORE_NUMS-1];
genvar c;
generate
    for (c = 0; c < CORE_NUMS; c = c + 1) begin
        Line_Out_Cache#(
        .QUANT_SIZE( QUANT_SIZE ),
        .LINE_LEN  ( LINE_LEN ) //28
        ) LOC0 (
        .clk            (clk                            ),
        .rstn           (rstn                           ),
        .result_q       (data_in[(c+1) * QUANT_SIZE -  1 -:QUANT_SIZE]),
        .I_data_valid   (I_data_valid                   ),
        .I_data_ready   (I_data_ready0[c]               ),
        .DATA_LINE      (data_out[(c+1)*QUANT_SIZE*LINE_LEN-1  -:  QUANT_SIZE*LINE_LEN]),
        .O_data_valid   (O_data_valid0[c]                  ),
        .O_data_ready   (O_data_ready                   ),
        .dbg            (dbg_ch[c]                       )
        );

    end
endgenerate

/* 调试观测：纯连线引出（通道 0 代表全部通道）。 */
assign dbg = dbg_ch[0];

endmodule