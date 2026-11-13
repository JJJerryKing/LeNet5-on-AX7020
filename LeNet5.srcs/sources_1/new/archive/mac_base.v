/*
 * 设计思路：将NUMS组输入数据按PIPES个周期分组送入并行乘法器，
 * 各周期的乘积分别保存到result_mul中；全部乘法完成后，使用串联加法器
 * 对NUMS个乘积统一求和，并通过valid/ready接口输出最终点积结果。
 */
module mac#(
 parameter DSIZE = 8  ,//数据尺寸
 parameter WSIZE = 8  ,//权重尺寸
 parameter NUMS  = 25 ,//5*5卷积
 parameter PIPES = 1   //乘法打几级流水，NUMS/PIPES = DSPs
)(
input                                               clk,
input                                               rstn,
input       [(NUMS) * DSIZE  -  1 : 0]              A,
input       [(NUMS) * WSIZE  -  1 : 0]              W,
input                                               I_data_valid,
output                                              I_data_ready,
output    reg    [(DSIZE+WSIZE)-1+clogb2(NUMS):0]   result_q,
output                                              O_data_valid,
input                                               O_data_ready
);
function integer clogb2(input integer number);
begin
    for(clogb2 = 0 ; number > 0 ; clogb2 = clogb2 + 1 )
        number = number >> 1;
    end
endfunction

localparam EACH_NUMS   = NUMS/PIPES + ((NUMS%PIPES>0)?1:0);
localparam REAL_OUT_IDX = (NUMS%PIPES == 0)? (EACH_NUMS):(NUMS%PIPES);
reg [7:0] calc_cnt;
reg [(NUMS) * DSIZE  -  1 : 0] data_1;
reg [(NUMS) * WSIZE  -  1 : 0] data_2;
wire signed [DSIZE  -  1 : 0] Signed_data_1[0:NUMS-1];
wire signed [WSIZE  -  1 : 0] Signed_data_2[0:NUMS-1];
genvar idx,jdx;
for (idx = 0; idx<NUMS; idx=idx+1) begin
    assign Signed_data_1[idx] = data_1[idx*DSIZE+:DSIZE];
    assign Signed_data_2[idx] = data_2[idx*WSIZE+:WSIZE];
end

wire I_data_Fire;
assign I_data_Fire = I_data_valid & I_data_ready;

wire [(DSIZE+WSIZE)-1:0] Signed_data_multiplier[0:EACH_NUMS-1];

genvar i;
for (i = 0; i<EACH_NUMS; i=i+1) begin
    assign Signed_data_multiplier[i] = Signed_data_1[calc_cnt*EACH_NUMS+i] * Signed_data_2[calc_cnt*EACH_NUMS+i];
end


localparam IDLE      = 3'b001;
localparam CALC_BUSY = 3'b010;
localparam CALC_END  = 3'b100;
reg [3:0] STATE;
reg [3:0] next_STATE;
always @(posedge clk ) begin
    if(!rstn)
        STATE <= IDLE;
    else 
        STATE <= next_STATE;
end

always @(*) begin
    if(!rstn)
        next_STATE <= IDLE;
    else if(STATE == IDLE && (I_data_Fire))
        next_STATE <= CALC_BUSY;
    else if(STATE == CALC_BUSY && (calc_cnt == PIPES - 1))
        next_STATE <= CALC_END;    
    else if(STATE == CALC_END)
        next_STATE <= IDLE;    
end
assign I_data_ready = STATE == IDLE && O_data_ready;


always @(posedge clk ) begin
    if(!rstn) 
        calc_cnt <= 'd0;
    else 
        case (STATE)
            IDLE     : calc_cnt <= 'd0;
            CALC_BUSY: begin
                if(calc_cnt == PIPES)
                    calc_cnt <= 'd0;
                else    
                    calc_cnt <= calc_cnt + 'd1;
            end
            CALC_END : calc_cnt <= calc_cnt;
            default: calc_cnt <= calc_cnt;
        endcase
end

always @(posedge clk ) begin
    if(!rstn) begin
        data_1<= 'd0;
        data_2<= 'd0;
    end else begin
        if(I_data_Fire) begin
            data_1 <= A;
            data_2 <= W;
        end else begin
            data_1 <= data_1;
            data_2 <= data_2;
        end
    end
end
(*use_dsp="yes"*)reg signed [(DSIZE+WSIZE)-1:0] result_mul[0:NUMS-1];
integer j;
always @(posedge clk ) begin
    if(!rstn) begin
        for (j = 0; j<NUMS; j=j+1) begin
            result_mul[j] <= 'd0;
        end
    end else if(calc_cnt == PIPES - 1)begin
        for (j = 0; j<REAL_OUT_IDX; j=j+1) begin
            result_mul[j+calc_cnt*EACH_NUMS] <= Signed_data_multiplier[j];
        end
    end else begin
        for (j = 0; j<EACH_NUMS; j=j+1) begin
            result_mul[j+calc_cnt*EACH_NUMS] <= Signed_data_multiplier[j];
        end
    end
end
wire signed [DSIZE+WSIZE-1+clogb2(NUMS):0] data_adder [0:NUMS-1];
assign data_adder[0] = result_mul[0];

for (i = 1; i<NUMS; i=i+1) begin
    assign data_adder[i] = data_adder[i-1] + result_mul[i];
end


reg O_DATA_valid[0:1];
always @(posedge clk ) begin
    if(!rstn) begin
        O_DATA_valid[0]<=0;
        O_DATA_valid[1]<=0;
        result_q <= 'd0;
    end else if(calc_cnt == PIPES)begin
        result_q <= data_adder[NUMS-1];
        O_DATA_valid[0]<=1;
        O_DATA_valid[1]<=O_DATA_valid[0];
    end else begin
        result_q <= result_q;
        O_DATA_valid[0]<=0;
        O_DATA_valid[1]<=0;
    end
end
assign O_data_valid = O_DATA_valid[0]&~O_DATA_valid[1];
endmodule
