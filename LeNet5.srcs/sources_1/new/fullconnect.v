module fullconnect#(
 parameter QUANT_SIZE  = 12 , //量化步长
 parameter WEIGHT_SIZE = 12 , //量化步长
 parameter LINE_LEN    = 120, //输入行长度
 parameter LINE_LEN_O  = 84 , //输入行长度
 parameter PIPES       = 5  , //乘法打几拍
 parameter ADDSIZE     = 2     //输出需要补充的大小
)(
input                                               clk         ,
input                                               rstn        ,
input       [(LINE_LEN) * QUANT_SIZE  -  1 : 0]     DATA_LINE   ,
input       [(LINE_LEN) * WEIGHT_SIZE  -  1 : 0]    weight_input,
output      [clogb2(LINE_LEN_O) - 1 : 0]            weight_addr ,
input signed [31:0]                                  bias_input  ,
output      [clogb2(LINE_LEN_O) - 1 : 0]            bias_addr   ,
input       [WEIGHT_SIZE          -  1  : 0]        SCALE       ,
input       [WEIGHT_SIZE          -  1  : 0]        SHIFT       ,
input                                               I_data_valid,
output                                              I_data_ready,
output      [(QUANT_SIZE+ADDSIZE)*LINE_LEN_O-1:0]   result_q    ,
output reg                                          O_data_valid,
input                                               O_data_ready,
/*
调试观测口：仅引出内部计数/流水握手，不改变原有逻辑。
dbg[48:35] 内部 mac 的 dbg（14 bit，位定义见 mac.v）
dbg[34:27] calc_cnt        dbg[26:19] mul_out_cnt     dbg[18:11] out_cnt
dbg[10] I_mul_valid        dbg[ 9] I_mul_ready        dbg[ 8] O_mul_valid
dbg[ 7] O_mul_ready        dbg[ 6] I_mul_valid_pipe1  dbg[ 5] O_mul_valid_pipe1
dbg[ 4] I_data_Fire        dbg[ 3] I_data_valid       dbg[ 2] I_data_ready
dbg[ 1] O_data_valid       dbg[ 0] O_data_ready
*/
output      [48:0]                                  dbg

);

wire I_data_Fire;
reg I_mul_valid;
wire I_mul_ready;
wire O_mul_valid;
reg O_mul_ready;
wire [(QUANT_SIZE+WEIGHT_SIZE)-1+clogb2(LINE_LEN):0] mul_result;
assign I_data_Fire = I_data_ready&I_data_valid;
assign I_data_ready = calc_cnt == 'd0;
reg [(LINE_LEN) * QUANT_SIZE  -  1 : 0] r_DATA_LINE;
reg [7:0]calc_cnt;
reg [7:0]calc_cnt_pipe;
reg [7:0]out_cnt;
reg [7:0]mul_out_cnt;
always @(posedge clk ) begin
    if(!rstn) begin
        r_DATA_LINE <= 'd0;
    end else if(I_data_Fire) begin
        r_DATA_LINE <= DATA_LINE;
    end
end

always @(posedge clk) begin
    if(!rstn) begin
        calc_cnt <= 'd0;
    end else if(I_mul_valid && I_mul_ready) begin
        if(calc_cnt == LINE_LEN_O-1)
            calc_cnt <= 'd0;
        else
            calc_cnt <= calc_cnt + 1;
    end
end
always @(posedge clk) begin
    if(!rstn) begin
        calc_cnt_pipe <= 'd0;
    end else begin
        calc_cnt_pipe <= calc_cnt;
    end
end
always @(posedge clk) begin
    if(!rstn) begin
        mul_out_cnt <= 'd0;
    end else if(O_mul_valid && O_mul_ready) begin
        if(mul_out_cnt == LINE_LEN_O-1)
            mul_out_cnt <= 'd0;
        else
            mul_out_cnt <= mul_out_cnt + 1;
    end
end
reg I_mul_valid_pipe1;
always @(posedge clk) begin
    if(!rstn) begin
        I_mul_valid_pipe1<=0;
    end else if(I_data_Fire) begin
        I_mul_valid_pipe1 <= 1;
    end else begin
        I_mul_valid_pipe1 <= 0;
    end
end
always @(posedge clk) begin
    if(!rstn) begin
        I_mul_valid <= 0;
    end else if(I_mul_ready)begin
        I_mul_valid <= 1;
    end else begin
        I_mul_valid <= I_mul_valid_pipe1;
    end
end
always @(posedge clk) begin
    if(!rstn) begin
        O_mul_ready <= 'd0;
    end else if(I_data_Fire) begin
        O_mul_ready <= O_data_ready;
    end else if(out_cnt == LINE_LEN_O-1) begin
        O_mul_ready <= 0;
    end
end
mac#(
.DSIZE(QUANT_SIZE),
.WSIZE(WEIGHT_SIZE),
.NUMS (LINE_LEN),
.PIPES(PIPES)
) MUL(
.clk            (  clk            ),
.rstn           (  rstn           ),
.A              (  r_DATA_LINE    ),
.W              (  weight_input   ),
.I_data_valid   (  I_mul_valid   ),
.I_data_ready   (  I_mul_ready   ),
.result_q       (  mul_result     ),
.O_data_valid   (  O_mul_valid    ),
.O_data_ready   (  O_mul_ready    ),
.dbg            (  mac_dbg        )
);

reg [12:0] Trash;
reg signed [31:0] r_bias;
always @(posedge clk) begin
    if(!rstn)
        r_bias <= 'd0;
    else if(I_mul_valid && I_mul_ready)
        r_bias <= bias_input;
end

wire signed [(QUANT_SIZE+WEIGHT_SIZE)-1+clogb2(LINE_LEN_O*1) : 0] conv_channel_out_result [0:1];
assign conv_channel_out_result[0] = r_bias;
assign conv_channel_out_result[1] = conv_channel_out_result[0] + mul_result;
reg signed [QUANT_SIZE+WEIGHT_SIZE+clogb2(LINE_LEN_O)-1:0]RESULT;
always @(posedge clk) begin
if(!rstn) begin
    RESULT <= 'd0;
    out_cnt <= 'd0;
end else if(O_mul_ready && O_mul_valid)begin
        out_cnt <= mul_out_cnt;
        case (SHIFT)
            12 : {RESULT, Trash[11:0]} <= {conv_channel_out_result[1] * SCALE}; // scale 4bit 右边是 1
            11 : {RESULT, Trash[10:0]} <= {conv_channel_out_result[1] * SCALE};
            13 : {RESULT, Trash[12:0]} <= {conv_channel_out_result[1] * SCALE};
            // default: {RESULT}<= {conv_result * scale_sameBits};
        endcase
    end
end
wire [QUANT_SIZE+ADDSIZE-1:0] fc_result;
assign fc_result = RESULT[QUANT_SIZE+ADDSIZE-1:0];
reg [(QUANT_SIZE+ADDSIZE)*LINE_LEN_O-1:0] fc_result_line;
reg O_mul_valid_pipe1;

/*
MAC结果在握手当拍写入RESULT，延迟一拍后再将对应结果写入fc_result_line。
该有效信号只表示产生了一个新的结果，不受下游O_data_ready控制。
*/
always @(posedge clk) begin
    if(!rstn)
        O_mul_valid_pipe1 <= 1'b0;
    else
        O_mul_valid_pipe1 <= O_mul_valid && O_mul_ready;
end

always @(posedge clk ) begin
    if(!rstn)begin
        O_data_valid  <= 1'b0;
        fc_result_line <= 'd0;
    end else begin
        if(O_mul_valid_pipe1)
            fc_result_line[out_cnt*(QUANT_SIZE+ADDSIZE)+:QUANT_SIZE+ADDSIZE] <= fc_result;

        if(O_mul_valid_pipe1 && (out_cnt == LINE_LEN_O-1))
            O_data_valid <= 1'b1;
        else if(O_data_valid && O_data_ready)
            O_data_valid <= 1'b0;
    end
end
assign result_q = fc_result_line;
assign weight_addr = calc_cnt[clogb2(LINE_LEN_O)-1:0];
assign bias_addr = calc_cnt[clogb2(LINE_LEN_O)-1:0];

/*
调试观测：纯连线引出，不改变任何原有逻辑。
*/
wire [13:0] mac_dbg;
assign dbg = { mac_dbg,
               calc_cnt, mul_out_cnt, out_cnt,
               I_mul_valid, I_mul_ready, O_mul_valid, O_mul_ready,
               I_mul_valid_pipe1, O_mul_valid_pipe1,
               I_data_Fire, I_data_valid, I_data_ready,
               O_data_valid, O_data_ready };


function integer clogb2(input integer number);
begin
    for(clogb2 = 0 ; number > 0 ; clogb2 = clogb2 + 1 )
        number = number >> 1;
    end
endfunction


endmodule
