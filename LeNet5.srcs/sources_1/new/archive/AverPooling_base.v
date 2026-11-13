/*
in 1 pixel  |  total:28*28 |  6 channel
cycle 0  1  2  3  4  ...  27  28  29  30  31  32  ...  63  64  65
      load pixel          done
                              load pixel               done
*/
/*  A B ....
    C D
    when the data idx is D, do pooling.
*/
module AverPooling#(
 parameter QUANT_SIZE = 8,
 parameter LINE_LEN   = 28, //28
 parameter CORE_NUMS  = 6 //28

)(
input                                               clk,
input                                               rstn,
//image 
input  signed    [QUANT_SIZE - 1   :   0]           relu_out,
input                                               I_data_valid,
output                                              I_data_ready,
//weight and bias

//result
output  signed    [QUANT_SIZE - 1   :   0]          result_q,
output  reg                                         O_data_valid,
input                                               O_data_ready

);
wire I_data_Fire;
assign I_data_Fire = I_data_ready && I_data_valid;
assign I_data_ready = O_data_ready;
reg  [QUANT_SIZE*LINE_LEN-1 : 0]loadline;
wire [(QUANT_SIZE+1)*(LINE_LEN/2)-1 : 0]loadline_add;
reg  [QUANT_SIZE-1 :          0]C;
wire [QUANT_SIZE   :          0]C_add_D;
reg  [QUANT_SIZE+1 :          0]D_out;
wire [QUANT_SIZE+1 :          0]D_out_round;
reg [7 : 0]         col_cnt;
reg [7 : 0]         row_cnt;
assign result_q =  (D_out_round %2 == 1) ? ((D_out[1:0]>=2) ? D_out_round + 1 : D_out_round) : ((D_out[1:0]>2) ? D_out_round + 1 : D_out_round);
assign C_add_D = C+relu_out;
assign D_out_round = D_out >> 2;
genvar i;
for (i = 0; i<LINE_LEN/2; i=i+1) begin
   assign loadline_add[i*(QUANT_SIZE+1)+:(QUANT_SIZE+1)] = loadline[2*i*QUANT_SIZE+:QUANT_SIZE] + loadline[(2*i+1)*QUANT_SIZE+:QUANT_SIZE];
end
always @(posedge clk) begin
    if(!rstn) begin
        col_cnt <= 0;
        row_cnt <= 0;
    end else if(I_data_Fire)begin

        if(col_cnt == LINE_LEN - 1 && row_cnt != LINE_LEN - 1)begin
            row_cnt <= row_cnt + 1;
            col_cnt <= 0;
        end else if(col_cnt == LINE_LEN - 1 && row_cnt == LINE_LEN - 1)begin
            col_cnt <= 0;
            row_cnt <= 0;
        end else begin
            col_cnt <= col_cnt + 1;
        end
    end
end

always @(posedge clk) begin
    if(!rstn)begin
        O_data_valid<=0;
        loadline<=0;
    end else if(I_data_Fire)begin
        case (row_cnt %2)   
            1 : begin                    //奇数行
                if(col_cnt %2 == 1)begin //奇数列 此时可以计算
                    O_data_valid <= 1;
                    D_out <= loadline_add[(col_cnt>>1)*(QUANT_SIZE+1)+:(QUANT_SIZE+1)] + C_add_D;
                end
                else begin
                    O_data_valid <= 0; //偶数列，存储 C 等待 D来了一起计算
                    C <= relu_out;
                end
            end
            0 : begin
                O_data_valid <= 0;      //偶数行，存储行数据
                loadline[col_cnt*QUANT_SIZE+:QUANT_SIZE] <= relu_out;
            end 
            default: ;
        endcase

    end else begin
        O_data_valid <= 0;
    end
end
endmodule
