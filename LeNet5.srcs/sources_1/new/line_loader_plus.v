/*
line_loader_Timingbase1修
与line_loader_base3相比，将装载结束条件移入状态跳转：I_data_ready只由装载状态决定，
initial_cnt和row_cnt不再经过组合逻辑驱动全部行缓存寄存器的写使能，缩短高扇出时序路径。
模块参数、接口、行缓存结构、MAC计算周期及valid/ready握手规则保持不变。解决WNS高的问题
*/
/*
line_loader_base3修
与line_loader_base2.v的区别：
1. 行缓存统一为CONV_CORE级固定移位，删除第六级预读行、取模和动态行索引。
2. LINE_LEN大于CONV_CORE时恢复原有mem_A作为完整工作行，通过固定右移生成窗口，
   消除由col_cnt控制的动态位选取；LINE_LEN等于CONV_CORE时直接从mem生成窗口。
3. 首次统一装载CONV_CORE行，后续每完成一个输出行再装载下一行。
4. 模块接口、MAC、量化及valid/ready握手方式保持不变。
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
    input                                       O_data_ready    ,
    /*
    调试观测口：仅把内部状态/计数器/握手信号引出，不参与、不改变任何原有逻辑。
    dbg[ 3: 0] CURRENT_STATE      状态机当前状态
    dbg[ 7: 4] initial_cnt        LOAD_INIT_LINE 已装载行数
    dbg[15: 8] col_cnt            已完成输出列数
    dbg[23:16] row_cnt            已完成输出行数
    dbg[31:24] mac_cnt_j          当前列输出通道计数
    dbg[32]    CONV_I_DATA_VALID  MAC 输入 valid
    dbg[33]    CONV_I_DATA_READY  MAC 输入 ready
    dbg[34]    CONV_O_DATA_VALID  MAC 输出 valid
    dbg[35]    CONV_O_DATA_READY  MAC 输出 ready（=O_data_ready 打一拍）
    dbg[43:36] out_cnt            result_channel 写地址
    dbg[51:44] bias_cnt           偏置/输出通道计数

    另有 dbg_mac[13:0]：内部 mac（第 0 个通道，其余通道与其同 valid/ready、状态同步）
    的观测量，位定义见 mac.v。
    */
    output      [51:0]                          dbg,
    output      [13:0]                          dbg_mac
    );

/******************LOCALPARAM********************/
localparam NUMS = CONV_CORE*CONV_CORE;
localparam CONV_LEN = LINE_LEN - CONV_CORE + 1;
/*******************GENVAR***********************/
genvar tensorA_i,Channel_I_i;
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
reg  [7:0] mac_cnt_j;

reg  CONV_O_DATA_READY;
reg  CONV_I_DATA_VALID;
reg [QUANT_SIZE*LINE_LEN - 1 : 0] mem  [0:CHANNEL_I-1][0:CONV_CORE-1];
reg [QUANT_SIZE*LINE_LEN - 1 : 0] mem_A[0:CHANNEL_I-1][0:CONV_CORE-1];
/*
line_loader_base3修
Tensor_A只作为固定窗口连线：普通卷积连接mem_A低CONV_CORE个像素，
输入宽度等于卷积核宽度时直接连接mem，不再保存第二份窗口寄存器。
*/
wire [QUANT_SIZE*CONV_CORE - 1 : 0] Tensor_A[0:CHANNEL_I-1][0:CONV_CORE-1];
reg O_DATA_VALID[0:1];
reg signed [QUANT_SIZE+WEIGHT_SIZE+clogb2(NUMS)-1:0]RESULT;

/********************LOGIC***********************/

assign I_data_Fire = I_data_valid && I_data_ready;
assign CONV_I_DATA_FIRE = CONV_I_DATA_READY && CONV_I_DATA_VALID;
/*
line_loader_Timingbase1修
计数器只参与下一状态判断，装载状态本身表示当前可以接收一行数据。
*/
assign STATE2_I_READY = (CURRENT_STATE == LOAD_INIT_LINE);
assign STATE4_I_READY = (CURRENT_STATE == LOAD_NEW_LINE );
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
    else begin
        /*
        line_loader_Timingbase1修
        最后一条初始输入在握手当拍结束装载；每个输出行计算完成时先判断是否为
        最后一行，只有仍需输入新行时才进入LOAD_NEW_LINE。
        */
        if      ( (CURRENT_STATE == IDLE           )  && ( LOAD_INIT ) ) //先加载
            CURRENT_STATE  <=  LOAD_INIT_LINE;
        else if ( (CURRENT_STATE == LOAD_INIT_LINE )  && ( I_data_Fire ) && ( initial_cnt == CONV_CORE-1 ) ) //加载完CONV_CORE行开始计算
            CURRENT_STATE  <=  BEGIN_CALC;
        else if ( (CURRENT_STATE == BEGIN_CALC     )  && ( col_cnt == CONV_LEN ) && ( row_cnt == CONV_LEN-1 ) ) //最后一个输出行计算完成
            CURRENT_STATE  <=  CALC_END;
        else if ( (CURRENT_STATE == BEGIN_CALC     )  && ( col_cnt == CONV_LEN ) ) //当前输出行计算完成，继续加载新行
            CURRENT_STATE  <=  LOAD_NEW_LINE;
        else if ( (CURRENT_STATE == LOAD_NEW_LINE  )  && ( I_data_Fire ) ) //新行握手后继续计算
            CURRENT_STATE  <=  BEGIN_CALC;
        else if ( (CURRENT_STATE == CALC_END       )  && ( out_cnt == CHANNEL_O-1 )  ) //计算到最后一行的�?后一列时停止计算
            CURRENT_STATE  <=  IDLE;
        else 
            CURRENT_STATE  <=  CURRENT_STATE;
    end
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
            LOAD_INIT_LINE: begin//先读CONV_CORE行
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
                    line_loader_base3修
                    新行固定移入mem后的下一周期再装载mem_A，避免MAC读取旧窗口。
                    */
                    CONV_I_DATA_VALID <= 0;
                end
            end 
            CALC_END      : begin//�?后一行的�?后一�?
                /*
                line_loader_Timingbase1修
                只有最后一个输出行完成后才进入CALC_END，因此不再使用row_cnt组合判断。
                */
                CONV_I_DATA_VALID <= 0;
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

/*
line_loader_base3修
首次装载和后续换行共用同一套固定移位：mem始终保存当前卷积所需的
CONV_CORE行，新输入行只写入最后一级，不再使用initial_cnt或row_cnt寻址。
*/
always @(posedge clk) begin
    if(!rstn) begin
        for(CHANNEL_I_j = 0; CHANNEL_I_j < CHANNEL_I; CHANNEL_I_j = CHANNEL_I_j + 1) begin
            for(CONV_CORE_j = 0; CONV_CORE_j < CONV_CORE; CONV_CORE_j = CONV_CORE_j + 1) begin
                mem[CHANNEL_I_j][CONV_CORE_j] <= {QUANT_SIZE*LINE_LEN{1'b1}};
            end
        end
    end else if(I_data_Fire) begin
        for(CHANNEL_I_j = 0; CHANNEL_I_j < CHANNEL_I; CHANNEL_I_j = CHANNEL_I_j + 1) begin
            for(CONV_CORE_j = 0; CONV_CORE_j < CONV_CORE-1; CONV_CORE_j = CONV_CORE_j + 1) begin
                mem[CHANNEL_I_j][CONV_CORE_j] <= mem[CHANNEL_I_j][CONV_CORE_j+1];
            end
            mem[CHANNEL_I_j][CONV_CORE-1] <=
                DATA_LINE[CHANNEL_I_j*LINE_LEN*QUANT_SIZE+:LINE_LEN*QUANT_SIZE];
        end
    end
end

/*
line_loader_base3修
LINE_LEN大于CONV_CORE时，每个新输出行开始先把固定五行复制到mem_A，
当前列最后一个输出通道完成输入握手后将mem_A固定右移一个像素。
LINE_LEN等于CONV_CORE时不生成mem_A更新逻辑，Tensor_A直接连接mem。
*/
generate
    if(LINE_LEN > CONV_CORE) begin: MEM_A_SHIFT
        always @(posedge clk) begin
            if(!rstn) begin
                for(CHANNEL_I_j = 0; CHANNEL_I_j < CHANNEL_I; CHANNEL_I_j = CHANNEL_I_j + 1) begin
                    for(CONV_CORE_j = 0; CONV_CORE_j < CONV_CORE; CONV_CORE_j = CONV_CORE_j + 1) begin
                        mem_A[CHANNEL_I_j][CONV_CORE_j] <= {QUANT_SIZE*LINE_LEN{1'b0}};
                    end
                end
            end else if((col_cnt == 0) && (mac_cnt_j == 0)) begin
                for(CHANNEL_I_j = 0; CHANNEL_I_j < CHANNEL_I; CHANNEL_I_j = CHANNEL_I_j + 1) begin
                    for(CONV_CORE_j = 0; CONV_CORE_j < CONV_CORE; CONV_CORE_j = CONV_CORE_j + 1) begin
                        mem_A[CHANNEL_I_j][CONV_CORE_j] <= mem[CHANNEL_I_j][CONV_CORE_j];
                    end
                end
            end else if(CONV_I_DATA_FIRE && (mac_cnt_j == CHANNEL_O-1) &&
                        (col_cnt < CONV_LEN-1)) begin
                for(CHANNEL_I_j = 0; CHANNEL_I_j < CHANNEL_I; CHANNEL_I_j = CHANNEL_I_j + 1) begin
                    for(CONV_CORE_j = 0; CONV_CORE_j < CONV_CORE; CONV_CORE_j = CONV_CORE_j + 1) begin
                        mem_A[CHANNEL_I_j][CONV_CORE_j] <=
                            mem_A[CHANNEL_I_j][CONV_CORE_j] >> QUANT_SIZE;
                    end
                end
            end
        end
    end

    for(Channel_I_i = 0; Channel_I_i < CHANNEL_I; Channel_I_i = Channel_I_i + 1) begin: TENSOR_CHANNEL
        for(tensorA_i = 0; tensorA_i < CONV_CORE; tensorA_i = tensorA_i + 1) begin: TENSOR_ROW
            if(LINE_LEN == CONV_CORE) begin: DIRECT_WINDOW
                assign Tensor_A[Channel_I_i][tensorA_i] =
                    mem[Channel_I_i][tensorA_i][QUANT_SIZE*CONV_CORE-1:0];
            end else begin: SHIFT_WINDOW
                assign Tensor_A[Channel_I_i][tensorA_i] =
                    mem_A[Channel_I_i][tensorA_i][QUANT_SIZE*CONV_CORE-1:0];
            end
        end
    end
endgenerate
wire signed [(QUANT_SIZE+WEIGHT_SIZE)-1+clogb2(NUMS) : 0] conv_result [0:CHANNEL_I-1];
wire signed [(QUANT_SIZE+WEIGHT_SIZE)-1+clogb2(NUMS*CHANNEL_I) : 0] conv_channel_out_result [0:CHANNEL_I];
assign conv_channel_out_result[0] = bias_input;

wire [CHANNEL_I-1:0] mac_i_v;
wire [CHANNEL_I-1:0] mac_i_r;
wire [CHANNEL_I-1:0] mac_o_v;
wire [CHANNEL_I-1:0] mac_o_r;
wire [13:0]          mac_dbg [0:CHANNEL_I-1];
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
        .O_data_ready   (  mac_o_r[mac_gen_i]                            ),
        .dbg            (  mac_dbg[mac_gen_i]                            )
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

/*
调试观测：纯连线引出，不参与任何原有逻辑；位定义见端口注释。
*/
assign dbg = { bias_cnt,               // [51:44]
               out_cnt,                // [43:36]
               CONV_O_DATA_READY,      // [35]
               CONV_O_DATA_VALID,      // [34]
               CONV_I_DATA_READY,      // [33]
               CONV_I_DATA_VALID,      // [32]
               mac_cnt_j,              // [31:24]
               row_cnt,                // [23:16]
               col_cnt,                // [15: 8]
               initial_cnt,            // [ 7: 4]
               CURRENT_STATE };        // [ 3: 0]

/* 调试观测：内部 mac（第 0 通道代表全部通道）的观测量。 */
assign dbg_mac = mac_dbg[0];


function integer clogb2(input integer number);
begin
    for(clogb2 = 0 ; number > 0 ; clogb2 = clogb2 + 1 )
        number = number >> 1;
    end
endfunction


endmodule
