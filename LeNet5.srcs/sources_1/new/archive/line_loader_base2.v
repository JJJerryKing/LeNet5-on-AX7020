/*
 * 与line_loader_base1.v的区别：
 * 1. 删除完整行宽度的mem_A副本，Tensor_A由连线改为寄存器，
 *    仅保存当前CONV_CORE*CONV_CORE卷积窗口所需的数据。
 * 2. 每个新输出行开始时，直接从循环行缓存mem装载窗口最前面的CONV_CORE列。
 * 3. 当前列的全部输出通道完成valid/ready握手后，Tensor_A按像素移位，
 *    并从mem补入下一列像素，避免对整行数据执行复制和移位。
 * 4. 新输入行写入mem后增加一个窗口装载周期，防止MAC读取尚未更新的数据。
 * 5. 外部接口、卷积计算结果及整体valid/ready握手方式保持不变。
 */
module line_loader_plus#(
 parameter QUANT_SIZE  = 12 , //量化步长
 parameter WEIGHT_SIZE = 12 , //量化步长
 parameter LINE_LEN    = 14 , //输入行长度
 parameter PIPES       = 5  , //乘法打几拍
 parameter CONV_CORE   = 5  ,  //5*5卷积核
 parameter CHANNEL_I   = 6  ,  //输入通道
 parameter CHANNEL_O   = 16 ,  //输出通道
 parameter ADDSIZE     = 2     //输出需要补充的大小
)(
    input                                       clk             ,
    input                                       rstn            ,
    input                                       LOAD_INIT       ,
    input       [QUANT_SIZE*LINE_LEN*CHANNEL_I -   1 : 0]       DATA_LINE       ,
    input       [WEIGHT_SIZE*CONV_CORE*CONV_CORE*CHANNEL_I - 1 : 0]       weight_input      ,
    output      [clogb2(CHANNEL_O) - 1 : 0]       weight_addr     ,
    input signed [31:0]                            bias_input      ,
    output      [clogb2(CHANNEL_O) - 1 : 0]       bias_addr       ,
    input       [WEIGHT_SIZE          -  1  : 0] SCALE           ,
    input       [WEIGHT_SIZE          -  1  : 0] SHIFT           ,
    input                                       I_data_valid    ,
    output                                      I_data_ready    ,
    output      [(QUANT_SIZE+ADDSIZE)*CHANNEL_O -  1  : 0]  result_q        ,
    output                                      O_data_valid    ,
    input                                       O_data_ready    
    );

/******************LOCALPARAM********************/
localparam NUMS = CONV_CORE*CONV_CORE;
localparam CONV_LEN = LINE_LEN - CONV_CORE + 1;
localparam INIT_USELESS = LINE_LEN == CONV_CORE;
/*******************GENVAR***********************/
genvar result_gen_channel_i;
genvar mac_gen_i;
/*******************INTEGER***********************/
integer CHANNEL_I_j;
integer CONV_CORE_j;
integer result_int_channel_i;
/********************WIRE************************/
wire I_data_Fire;
wire CONV_I_DATA_READY;
wire CONV_O_DATA_VALID;
wire CONV_I_DATA_FIRE;

wire STATE2_I_READY;
wire STATE4_I_READY;

/********************REG*************************/

reg  [3:0] initial_cnt;
reg  [7:0] col_cnt;
reg  [7:0] row_cnt;

reg  CONV_O_DATA_READY;
reg  CONV_I_DATA_VALID;
reg [QUANT_SIZE*LINE_LEN - 1 : 0] mem  [0:CHANNEL_I-1][0:CONV_CORE];
/*
line_loader_base1修
Tensor_A直接作为当前卷积窗口寄存器，每行只保存CONV_CORE个像素。
*/
reg [QUANT_SIZE*CONV_CORE - 1 : 0] Tensor_A[0:CHANNEL_I-1][0:CONV_CORE-1];
reg O_DATA_VALID[0:1];
reg signed [QUANT_SIZE+WEIGHT_SIZE+clogb2(NUMS)-1:0]RESULT;

/********************LOGIC***********************/

assign I_data_Fire = I_data_valid && I_data_ready;
assign CONV_I_DATA_FIRE = CONV_I_DATA_READY && CONV_I_DATA_VALID;
assign STATE2_I_READY = ( (CURRENT_STATE == LOAD_INIT_LINE) && (initial_cnt <= CONV_CORE) );
assign STATE4_I_READY = ( (CURRENT_STATE == LOAD_NEW_LINE ) && (row_cnt!=CONV_LEN-1));
assign I_data_ready   = STATE2_I_READY | STATE4_I_READY;

assign O_data_valid = O_DATA_VALID[0]&~O_DATA_VALID[1];

// assign CONV_I_DATA_READY = 1;
/********************STATE************************/
parameter IDLE              = 1;
parameter LOAD_INIT_LINE    = 2;
parameter BEGIN_CALC        = 3;
parameter LOAD_NEW_LINE     = 4;
parameter CALC_END          = 5;

reg       [3:0]             CURRENT_STATE;


always @(posedge clk) begin
    if(!rstn)
        CURRENT_STATE <= IDLE;
    else
        if      ( (CURRENT_STATE == IDLE           )  && ( LOAD_INIT ) ) //先加载
            CURRENT_STATE  <=  LOAD_INIT_LINE;
        else if ( (CURRENT_STATE == LOAD_INIT_LINE )  && ( ( initial_cnt == CONV_CORE + 1 ) || (INIT_USELESS == 1 && initial_cnt == CONV_CORE) )) //加载完开始计算，多一行
            CURRENT_STATE  <=  BEGIN_CALC;
        else if ( (CURRENT_STATE == BEGIN_CALC     )  && ( col_cnt == CONV_LEN ) ) //计算
            CURRENT_STATE  <=  LOAD_NEW_LINE;
        else if ( (CURRENT_STATE == LOAD_NEW_LINE  )  && ( row_cnt != CONV_LEN-1 ) && (I_data_Fire )) //计算到最后一列的时�?�加载新�?
            CURRENT_STATE  <=  BEGIN_CALC;
        else if ( (CURRENT_STATE == LOAD_NEW_LINE  )  && ( row_cnt == CONV_LEN-1 ) ) //计算到最后一列的时�?�加载新�?
            CURRENT_STATE  <=  CALC_END;
        else if ( (CURRENT_STATE == CALC_END       )  && ( out_cnt == CHANNEL_O-1 )  ) //计算到最后一行的�?后一列时停止计算
            CURRENT_STATE  <=  IDLE;
        else 
            CURRENT_STATE  <=  CURRENT_STATE;    
end

always @(posedge clk) begin
    if(!rstn)begin
        initial_cnt <= 0;
        col_cnt <= 0;
        CONV_I_DATA_VALID <=0 ;
        row_cnt <= 0;
        
    end
    else begin
        case ( CURRENT_STATE )
            IDLE          : begin//WAIT
                initial_cnt <= 0;
                col_cnt <= 0;
                CONV_I_DATA_VALID <=0 ;
                row_cnt <= 0;
                CONV_O_DATA_READY <= 0;
                mac_cnt_j <= 0;
            end
            LOAD_INIT_LINE: begin//先读六行
                if( I_data_Fire ) begin
                    initial_cnt <= initial_cnt + 1;
                end
            end
            BEGIN_CALC    : begin//�?始计�?
                CONV_I_DATA_VALID <= CONV_I_DATA_READY;
                CONV_O_DATA_READY <= O_data_ready;
                if(CONV_I_DATA_READY && CONV_I_DATA_VALID)begin
                    if(mac_cnt_j == CHANNEL_O-1) begin
                        mac_cnt_j <= 0;
                        col_cnt <=  col_cnt + 1;
                    end else begin
                        mac_cnt_j <= mac_cnt_j + 1;
                    end
                end
            end
            LOAD_NEW_LINE : begin//换行
                if(I_data_Fire)begin
                    col_cnt <=  0;
                    row_cnt <=  row_cnt + 1;
                    /*
                    line_loader_base1修
                    新行写入后的下一周期先装载Tensor_A，避免MAC读取尚未更新的窗口。
                    */
                    CONV_I_DATA_VALID <= 0;
                end
            end 
            CALC_END      : begin//�?后一行的�?后一�?
                CONV_I_DATA_VALID <= CONV_I_DATA_READY && ((col_cnt != CONV_LEN) && (row_cnt != CONV_LEN-1));
                CONV_O_DATA_READY <= O_data_ready;
                if(CONV_I_DATA_READY && CONV_I_DATA_VALID)begin
                    if(mac_cnt_j == CHANNEL_O-1) begin
                        mac_cnt_j <= 0;
                        col_cnt <=  col_cnt + 1;
                    end else begin
                        mac_cnt_j <= mac_cnt_j + 1;
                    end
                end
            end
            default: ;
        endcase
    end
end

always @(posedge clk) begin
    if(!rstn) begin
        for (CHANNEL_I_j = 0; CHANNEL_I_j<CHANNEL_I; CHANNEL_I_j=CHANNEL_I_j+1) begin
            for (CONV_CORE_j = 0; CONV_CORE_j < CONV_CORE+1; CONV_CORE_j=CONV_CORE_j+1) begin
                mem[CHANNEL_I_j][CONV_CORE_j] <= {QUANT_SIZE*LINE_LEN{1'b1}};
            end
        end
    end else if (I_data_Fire)begin
        if(CURRENT_STATE == LOAD_INIT_LINE) begin
            for (CHANNEL_I_j = 0; CHANNEL_I_j<CHANNEL_I; CHANNEL_I_j=CHANNEL_I_j+1) begin
                mem[CHANNEL_I_j][initial_cnt] <= DATA_LINE[CHANNEL_I_j*LINE_LEN*QUANT_SIZE+:LINE_LEN*QUANT_SIZE];
            end
        end else if (CURRENT_STATE == LOAD_NEW_LINE) begin
            for (CHANNEL_I_j = 0; CHANNEL_I_j<CHANNEL_I; CHANNEL_I_j=CHANNEL_I_j+1) begin
                mem[CHANNEL_I_j][row_cnt % 6] <= DATA_LINE[CHANNEL_I_j*LINE_LEN*QUANT_SIZE+:LINE_LEN*QUANT_SIZE];
            end
        end
    end
end

/*
line_loader_base1修
新输出行开始时，从循环行缓存中装载每行前CONV_CORE个像素；当前列的最后一个
输出通道完成握手后，窗口右移一个像素并从mem补入下一像素。这样不再复制、
移位QUANT_SIZE*LINE_LEN位的完整数据行。
*/
always @(posedge clk) begin
    if(!rstn) begin
        for (CHANNEL_I_j = 0; CHANNEL_I_j<CHANNEL_I; CHANNEL_I_j=CHANNEL_I_j+1) begin
            for(CONV_CORE_j = 0; CONV_CORE_j<CONV_CORE; CONV_CORE_j=CONV_CORE_j+1)begin
                Tensor_A[CHANNEL_I_j][CONV_CORE_j] <= {QUANT_SIZE*CONV_CORE{1'b0}};
            end
        end
    end else if (col_cnt == 0 && mac_cnt_j == 0) begin
        for(CHANNEL_I_j = 0; CHANNEL_I_j < CHANNEL_I; CHANNEL_I_j = CHANNEL_I_j + 1)begin
            for(CONV_CORE_j = 0; CONV_CORE_j < CONV_CORE; CONV_CORE_j = CONV_CORE_j + 1)begin
                Tensor_A[CHANNEL_I_j][CONV_CORE_j] <=
                    mem[CHANNEL_I_j][(row_cnt+CONV_CORE_j)%(CONV_CORE+1)]
                       [QUANT_SIZE*CONV_CORE-1:0];
            end
        end
    end else if(CONV_I_DATA_FIRE && (mac_cnt_j == CHANNEL_O-1) && (col_cnt < CONV_LEN-1)) begin
        for(CHANNEL_I_j = 0; CHANNEL_I_j < CHANNEL_I; CHANNEL_I_j = CHANNEL_I_j + 1)begin
            for(CONV_CORE_j = 0; CONV_CORE_j < CONV_CORE; CONV_CORE_j = CONV_CORE_j + 1)begin
                Tensor_A[CHANNEL_I_j][CONV_CORE_j] <= {
                    mem[CHANNEL_I_j][(row_cnt+CONV_CORE_j)%(CONV_CORE+1)]
                       [(col_cnt+CONV_CORE)*QUANT_SIZE+:QUANT_SIZE],
                    Tensor_A[CHANNEL_I_j][CONV_CORE_j][QUANT_SIZE*CONV_CORE-1:QUANT_SIZE]
                };
            end
        end
    end
end
wire signed [(QUANT_SIZE+WEIGHT_SIZE)-1+clogb2(NUMS) : 0] conv_result [0:CHANNEL_I-1];
wire signed [(QUANT_SIZE+WEIGHT_SIZE)-1+clogb2(NUMS*CHANNEL_I) : 0] conv_channel_out_result [0:CHANNEL_I];
assign conv_channel_out_result[0] = bias_input;

reg [7:0] mac_cnt_j;
wire [CHANNEL_I-1:0] mac_i_v;
wire [CHANNEL_I-1:0] mac_i_r;
wire [CHANNEL_I-1:0] mac_o_v;
wire [CHANNEL_I-1:0] mac_o_r;
assign CONV_I_DATA_READY = &mac_i_r;
assign CONV_O_DATA_VALID = &mac_o_v;
for (mac_gen_i = 0; mac_gen_i<CHANNEL_I; mac_gen_i=mac_gen_i+1) begin
    assign mac_i_v[mac_gen_i] = CONV_I_DATA_VALID;
    assign mac_o_r[mac_gen_i] = CONV_O_DATA_READY;
    assign conv_channel_out_result[mac_gen_i+1] = conv_channel_out_result[mac_gen_i] + conv_result[mac_gen_i];
    mac#(
    .DSIZE ( QUANT_SIZE  ) ,//数据尺寸
    .WSIZE ( WEIGHT_SIZE  ) ,//权重尺寸
    .NUMS  ( NUMS ) ,//5*5卷积
    .PIPES ( PIPES)  //乘法打几级流水，NUMS/PIPES = DSPs
    ) mac_i_j(
        .clk(        clk               ),
        .rstn(       rstn               ),
    //  input 5x5 x 8(bit) , A & B
        .A              ({  Tensor_A[mac_gen_i][4],
                            Tensor_A[mac_gen_i][3],
                            Tensor_A[mac_gen_i][2],
                            Tensor_A[mac_gen_i][1],
                            Tensor_A[mac_gen_i][0]}),
        .W              (  weight_input[mac_gen_i*NUMS*WEIGHT_SIZE +: NUMS*WEIGHT_SIZE]),
        .I_data_valid   (  mac_i_v[mac_gen_i]                            ),
        .I_data_ready   (  mac_i_r[mac_gen_i]                            ),
        .result_q       (  conv_result[mac_gen_i]                        ),
        .O_data_valid   (  mac_o_v[mac_gen_i]                            ),
        .O_data_ready   (  mac_o_r[mac_gen_i]                            )
    );  
end
reg [7:0] bias_cnt;
reg [7:0] out_cnt;
reg [12:0] Trash;
always @(posedge clk) begin
if(!rstn) begin
    RESULT <= 'd0;
    bias_cnt<= 'd0;
    out_cnt <= 'd0;
end else if(CONV_O_DATA_READY && CONV_O_DATA_VALID)begin
        if(bias_cnt == CHANNEL_O-1)begin
            bias_cnt <= 'd0;
        end else begin
            bias_cnt<=bias_cnt+1;
        end
        out_cnt <= bias_cnt;
        case (SHIFT)
            12 : {RESULT, Trash[11:0]} <= {conv_channel_out_result[CHANNEL_I] * SCALE}; // scale 4bit 右边是 1
            11 : {RESULT, Trash[10:0]} <= {conv_channel_out_result[CHANNEL_I] * SCALE};
            13 : {RESULT, Trash[12:0]} <= {conv_channel_out_result[CHANNEL_I] * SCALE};
            // default: {RESULT}<= {conv_result * scale_sameBits};
        endcase
    end
end
reg signed[(QUANT_SIZE+ADDSIZE)-1:0] result_channel[0:CHANNEL_O-1];


always @(posedge clk) begin
if(!rstn) begin
    for (result_int_channel_i = 0; result_int_channel_i<CHANNEL_O; result_int_channel_i=result_int_channel_i+1) begin
        result_channel[result_int_channel_i] <= 'd0;
    end
    O_DATA_VALID[0]<=0;
    O_DATA_VALID[1]<=0;
end else begin
        result_channel[out_cnt] <= RESULT[(QUANT_SIZE+ADDSIZE)-1:0];
        if((out_cnt == CHANNEL_O-1) && (1))begin
            O_DATA_VALID[0]<=1;
            O_DATA_VALID[1]<=O_DATA_VALID[0];
        end else begin
            O_DATA_VALID[0]<=0;
            O_DATA_VALID[1]<=0;
        end
    end
end
for (result_gen_channel_i = 0; result_gen_channel_i<CHANNEL_O; result_gen_channel_i=result_gen_channel_i+1) begin
    assign result_q[result_gen_channel_i*(QUANT_SIZE+ADDSIZE)+:(QUANT_SIZE+ADDSIZE)] = result_channel[result_gen_channel_i];
end

assign weight_addr = mac_cnt_j[clogb2(CHANNEL_O)-1:0];
assign bias_addr = bias_cnt[clogb2(CHANNEL_O)-1:0];


function integer clogb2(input integer number);
begin
    for(clogb2 = 0 ; number > 0 ; clogb2 = clogb2 + 1 )
        number = number >> 1;
    end
endfunction


endmodule
