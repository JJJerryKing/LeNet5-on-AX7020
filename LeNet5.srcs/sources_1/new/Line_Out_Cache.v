module Line_Out_Cache#(
 parameter QUANT_SIZE = 12,
 parameter LINE_LEN   = 14 //28
)(
    input                                       clk,
    input                                       rstn,
    input      [QUANT_SIZE - 1 : 0]             result_q,
    input                                       I_data_valid,
    output  reg                                 I_data_ready,


    output        [QUANT_SIZE*(LINE_LEN) -  1 : 0]DATA_LINE,
    output     reg                              O_data_valid,
    input                                       O_data_ready,
    /*
    调试观测口：仅引出内部计数/单拍标志/握手，不改变原有逻辑。
    dbg[21:14] line_cnt  dbg[13:6] pix_cnt  dbg[5] wait_one_cycle
    dbg[4] one_shot  dbg[3] O_data_ready  dbg[2] O_data_valid
    dbg[1] I_data_ready  dbg[0] I_data_valid
    */
    output      [21:0]                          dbg
    );
reg [7:0] line_cnt;
reg[QUANT_SIZE*LINE_LEN -  1 : 0]DATA_LINE_FILL;
assign DATA_LINE = DATA_LINE_FILL;



wire I_data_Fire;
assign I_data_Fire = I_data_valid  &  I_data_ready;

always @(posedge clk) begin
    if(!rstn)begin
        I_data_ready <= 0;
    end else begin
        I_data_ready <= O_data_ready | (pix_cnt != LINE_LEN - 1);
    end
end





reg [7:0] pix_cnt;

always @(posedge clk) begin
    if(!rstn)
        pix_cnt<= 'd0;
    else if (I_data_Fire) begin
        if(pix_cnt == LINE_LEN - 1)
            pix_cnt <=0;
        else
            pix_cnt <= pix_cnt + 1;
    end
end
genvar gen_var_k;
generate
    for (gen_var_k = 0; gen_var_k < LINE_LEN; gen_var_k = gen_var_k +1) 
    begin: loc
        always @(posedge clk) begin
            if(!rstn) begin
                    DATA_LINE_FILL[QUANT_SIZE*( gen_var_k + 1 ) - 1 -:QUANT_SIZE]<='d0;
            end else begin
                if(pix_cnt == gen_var_k)begin
                    DATA_LINE_FILL[QUANT_SIZE*( gen_var_k + 1 ) - 1 -:QUANT_SIZE] <= result_q;
                end
            end
        end
    end
endgenerate
reg wait_one_cycle;
reg one_shot;
always @(posedge clk) begin
    if(!rstn) begin
        O_data_valid <= 0;
        one_shot <= 0;
        line_cnt <= 'd0;
        wait_one_cycle<='d0;
    end
    else begin
        if( (I_data_Fire)&& ((pix_cnt == LINE_LEN - 1) || (pix_cnt == 0) )  && O_data_ready )begin
            if(one_shot)begin
                O_data_valid <= 1;
                one_shot <= 0;
                line_cnt <= line_cnt + 1;
            end else if(!one_shot)begin
                O_data_valid<= 0;
            end 
        end 
        else begin
            if(pix_cnt == (LINE_LEN-1)/2 )
                one_shot <= 1;
                O_data_valid <= 0;
                wait_one_cycle <=0;
        end
        
    end 
end
/*
调试观测：纯连线引出，不改变任何原有逻辑。
*/
assign dbg = { line_cnt, pix_cnt, wait_one_cycle, one_shot,
               O_data_ready, O_data_valid, I_data_ready, I_data_valid };
endmodule