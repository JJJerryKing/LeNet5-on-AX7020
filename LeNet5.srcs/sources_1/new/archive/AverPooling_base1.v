/*
AverPooling_base1修
与AverPooling_base.v的区别：
1. 删除整行像素寄存器loadline和常开的LINE_LEN/2个加法器loadline_add，只保留每行相邻
   两像素之和loadline_pair[0:LINE_LEN/2-1]；偶数行逐列累加，奇数行按col_cnt>>1取用。
2. 偶数行由“整行存储、并行求对和”改为“逐对求和”：偶列寄存当前像素C，奇列直接写入
   C_add_D，因此不再需要整行缓冲。
3. 模块接口、I_data_ready/O_data_valid握手、col_cnt/row_cnt计数以及result_q的四舍六入
   五取偶舍入逻辑保持不变，输出与AverPooling_base.v逐位一致。
*/
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
/*
base1修
loadline_pair[i]保存偶数行第i对相邻像素之和，取代原来的整行loadline，位宽比像素多1位。
*/
reg  [QUANT_SIZE:0] loadline_pair[0:LINE_LEN/2-1];
reg  [QUANT_SIZE-1 :          0]C;
wire [QUANT_SIZE   :          0]C_add_D;
reg  [QUANT_SIZE+1 :          0]D_out;
wire [QUANT_SIZE+1 :          0]D_out_round;
reg [7 : 0]         col_cnt;
reg [7 : 0]         row_cnt;
assign result_q =  (D_out_round %2 == 1) ? ((D_out[1:0]>=2) ? D_out_round + 1 : D_out_round) : ((D_out[1:0]>2) ? D_out_round + 1 : D_out_round);
assign C_add_D = C+relu_out;
assign D_out_round = D_out >> 2;
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

integer k;
always @(posedge clk) begin
    if(!rstn)begin
        O_data_valid<=0;
        for(k=0;k<LINE_LEN/2;k=k+1)
            loadline_pair[k]<=0;
    end else if(I_data_Fire)begin
        case (row_cnt %2)   
            1 : begin                    //奇数行
                if(col_cnt %2 == 1)begin //奇数列 此时可以计算
                    O_data_valid <= 1;
                    D_out <= loadline_pair[col_cnt>>1] + C_add_D;
                end
                else begin
                    O_data_valid <= 0; //偶数列，存储 C 等待 D来了一起计算
                    C <= relu_out;
                end
            end
            0 : begin
                O_data_valid <= 0;      //偶数行，逐列累加相邻两像素
                if(col_cnt %2 == 1)     //奇数列，一对像素的和已由C_add_D给出
                    loadline_pair[col_cnt>>1] <= C_add_D;
                else                    //偶数列，存储本列像素等待下一列
                    C <= relu_out;
            end 
            default: ;
        endcase

    end else begin
        O_data_valid <= 0;
    end
end
endmodule
