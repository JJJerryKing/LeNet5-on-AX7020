module argmax#(
 parameter QUANT_SIZE = 15 , //单个分类分数位宽
 parameter CLASS_NUMS = 10   //分类数量
)(
input                                               clk         ,
input                                               rstn        ,
input signed [QUANT_SIZE*CLASS_NUMS - 1 : 0]        data_in     ,
input                                               I_data_valid,
output                                              I_data_ready,
output reg [clogb2(CLASS_NUMS) - 1 : 0]             result_q    ,
output reg                                          O_data_valid,
input                                               O_data_ready,
/*
调试观测口：仅引出比较计数与握手，不改变原有逻辑。
dbg[8:5] compare_cnt  dbg[4] O_data_ready  dbg[3] O_data_valid
dbg[2] I_data_ready   dbg[1] I_data_valid  dbg[0] I_data_Fire
*/
output      [8:0]                                   dbg
);

localparam INDEX_SIZE = clogb2(CLASS_NUMS);

wire I_data_Fire;
assign I_data_Fire = I_data_valid && I_data_ready;

reg [QUANT_SIZE*CLASS_NUMS - 1 : 0] class_data;
reg signed [QUANT_SIZE - 1 : 0] max_value;
reg [INDEX_SIZE - 1 : 0] compare_cnt;
wire signed [QUANT_SIZE - 1 : 0] current_value;

assign current_value = class_data[QUANT_SIZE-1:0];
assign I_data_ready = (compare_cnt == CLASS_NUMS) && !O_data_valid;

always @(posedge clk) begin
    if(!rstn) begin
        class_data   <= 'd0;
        max_value    <= 'd0;
        compare_cnt  <= CLASS_NUMS;
        result_q     <= 'd0;
        O_data_valid <= 1'b0;
    end else if(I_data_Fire) begin
        class_data   <= data_in;
        max_value    <= {1'b1, {(QUANT_SIZE-1){1'b0}}};
        compare_cnt  <= 'd0;
        result_q     <= 'd0;
        O_data_valid <= 1'b0;
    end else if(compare_cnt < CLASS_NUMS) begin
        class_data <= class_data >> QUANT_SIZE;
        if(current_value > max_value) begin
            max_value <= current_value;
            result_q  <= compare_cnt;
        end
        if(compare_cnt == CLASS_NUMS-1) begin
            compare_cnt  <= CLASS_NUMS;
            O_data_valid <= 1'b1;
        end else begin
            compare_cnt <= compare_cnt + 1'b1;
        end
    end else if(O_data_valid && O_data_ready) begin
        O_data_valid <= 1'b0;
    end
end

/*
调试观测：纯连线引出，不改变任何原有逻辑。
*/
assign dbg = { compare_cnt, O_data_ready, O_data_valid, I_data_ready, I_data_valid, I_data_Fire };

function integer clogb2(input integer number);
begin
    for(clogb2 = 0; number > 0; clogb2 = clogb2 + 1)
        number = number >> 1;
end
endfunction

endmodule
