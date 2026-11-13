module relu_plus#(
 parameter QUANT_SIZE = 12,
 parameter LINE_LEN   = 28, //28
 parameter CORE_NUMS  = 6 //28
)(
input                                               clk         ,
input                                               rstn        ,
input  signed [QUANT_SIZE*CORE_NUMS - 1   :   0]    data_in     ,
input                                               I_relu_valid,
output reg                                          I_relu_ready,
output signed [QUANT_SIZE*CORE_NUMS - 1   :   0]    relu_out    ,
output reg                                          O_relu_valid,
input                                               O_relu_ready,
/*
调试观测口：仅引出内部寄存器/握手，不改变原有逻辑。
dbg[3] O_relu_ready  dbg[2] O_relu_valid  dbg[1] I_relu_ready  dbg[0] I_relu_valid
*/
output      [3:0]                                   dbg
);
reg  [QUANT_SIZE*CORE_NUMS-1:0] r_data_o; //为了时序稳定，选择打一拍
wire [QUANT_SIZE*CORE_NUMS-1:0] w_data_in;
genvar i;
for (i = 0; i<CORE_NUMS; i=i+1) begin
    assign w_data_in[QUANT_SIZE*i+:QUANT_SIZE] = (data_in[QUANT_SIZE*(i+1)-1] == 1'b0)? data_in[QUANT_SIZE*i+:QUANT_SIZE] : 'd0;
end
always @(posedge clk ) begin
    if(!rstn) begin
        r_data_o <='d0;
        O_relu_valid <= 0;
    end else if(I_relu_ready&&I_relu_valid)begin
        r_data_o <= w_data_in;
        O_relu_valid <= 1;
    end else begin
        O_relu_valid <= 0;
    end
end

always @(posedge clk ) begin
    if(!rstn) begin
        I_relu_ready <= 0;
    end else if(O_relu_ready)begin
        I_relu_ready <= 1;
    end else begin
        I_relu_ready <= 0;
    end
end

assign relu_out = r_data_o;

/*
调试观测：纯连线引出，不改变任何原有逻辑。
*/
assign dbg = { O_relu_ready, O_relu_valid, I_relu_ready, I_relu_valid };

endmodule
