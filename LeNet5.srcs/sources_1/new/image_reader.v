/*
image_reader_base1修
与image_reader_base.v的区别：
1. 删除整幅图片寄存器阵列image[0:LINE_NUMS-1][0:LINE_LEN-1]，只保留一行缓冲
   image_line[0:LINE_LEN-1]，不再驻留LINE_LEN*LINE_NUMS*QUANT_SIZE位图片数据。
2. 状态机由IDLE->LOAD_IMAGE->OUTPUT_IMAGE改为IDLE->LOAD_LINE->OUTPUT_LINE按行循环：
   每行先从BRAM顺序读入LINE_LEN个像素，再握手输出，第LINE_NUMS行握手完成后回到IDLE。
3. 输出侧改为常量下标访问image_line，去掉原image[idx][col_i]的整行动态选择网络，
   DATA_LINE在O_data_ready拉低期间保持不变。
4. 端口、I_data_ready/O_data_valid握手语义以及bram_en到bram_data的一拍读延迟假设
   与image_reader_base.v完全一致，可直接替换。
*/
module image_reader#(
 parameter DATA_WIDTH = 16,
 parameter QUANT_SIZE = 13,
 parameter LINE_LEN   = 28,
 parameter LINE_NUMS  = 28
)(
input                                               clk         ,
input                                               rstn        ,
input      [DATA_WIDTH-1:0]                         bram_data   ,
output     [clogb2(LINE_LEN*LINE_NUMS)-1:0]         bram_addr   ,
output                                              bram_en     ,
input                                               I_data_valid,
output                                              I_data_ready,
output     [QUANT_SIZE*LINE_LEN-1:0]                DATA_LINE   ,
output                                              O_data_valid,
input                                               O_data_ready,
/*
调试观测口：仅引出状态/地址计数/BRAM 使能与握手，不改变原有逻辑。
dbg[29:28] CURRENT_STATE   dbg[27:18] load_cnt   dbg[17:13] store_col_cnt
dbg[12: 8] idx             dbg[ 7] bram_en_delay1  dbg[ 6] bram_en
dbg[ 5] I_data_valid       dbg[ 4] I_data_ready    dbg[ 3] O_data_valid
dbg[ 2] O_data_ready       dbg[ 1] I_data_Fire     dbg[ 0] O_data_Fire
*/
output      [29:0]                                  dbg
);

localparam IMAGE_PIXELS = LINE_LEN*LINE_NUMS;
localparam ADDR_WIDTH   = clogb2(IMAGE_PIXELS);
localparam COUNT_WIDTH  = clogb2(IMAGE_PIXELS+1);
localparam INDEX_WIDTH  = clogb2(LINE_NUMS);
localparam COL_WIDTH    = clogb2(LINE_LEN);

localparam IDLE         = 2'd0;
localparam LOAD_LINE    = 2'd1;
localparam OUTPUT_LINE  = 2'd2;

wire I_data_Fire;
wire O_data_Fire;

reg [1:0] CURRENT_STATE;
reg [COUNT_WIDTH-1:0] load_cnt;
reg [COL_WIDTH-1:0] store_col_cnt;
reg bram_en_delay1;
reg [INDEX_WIDTH-1:0] idx;
/*
新增：行缓冲只保存当前正在装载/输出的一行像素，写侧按store_col_cnt寻址，
读侧在generate中用常量下标访问，综合为纯寄存器，不再产生动态选行网络。
*/
reg [QUANT_SIZE-1:0] image_line[0:LINE_LEN-1];

assign I_data_Fire = I_data_valid && I_data_ready;
assign O_data_Fire = O_data_valid && O_data_ready;

assign I_data_ready = (CURRENT_STATE == IDLE);
assign O_data_valid = (CURRENT_STATE == OUTPUT_LINE);

/*
修改：bram_data相对bram_en晚一拍返回，store_col_cnt计到LINE_LEN-1的那一拍只等
最后一个像素返回、不再发出新地址，因此门限是LINE_LEN-1。
*/
assign bram_en   = (CURRENT_STATE == LOAD_LINE) &&
                   (store_col_cnt < LINE_LEN-1);
assign bram_addr = load_cnt[ADDR_WIDTH-1:0];

always @(posedge clk) begin
    if(!rstn)
        CURRENT_STATE <= IDLE;
    else if((CURRENT_STATE == IDLE) && I_data_Fire)
        CURRENT_STATE <= LOAD_LINE;
    else if((CURRENT_STATE == LOAD_LINE) && bram_en_delay1 &&
            (store_col_cnt == LINE_LEN-1))
        CURRENT_STATE <= OUTPUT_LINE;
    else if((CURRENT_STATE == OUTPUT_LINE) && O_data_Fire &&
            (idx == LINE_NUMS-1))
        CURRENT_STATE <= IDLE;
    else if((CURRENT_STATE == OUTPUT_LINE) && O_data_Fire)
        CURRENT_STATE <= LOAD_LINE;
end

/*
修改：load_cnt不再只在整幅加载阶段累加，而是跨行连续计数，作为BRAM的线性像素地址，
只在IDLE清零，保证第n行从地址n*LINE_LEN开始。
*/
always @(posedge clk) begin
    if(!rstn)
        load_cnt <= 'd0;
    else if(CURRENT_STATE == IDLE)
        load_cnt <= 'd0;
    else if(bram_en)
        load_cnt <= load_cnt + 1'b1;
end

always @(posedge clk) begin
    if(!rstn)
        bram_en_delay1 <= 1'b0;
    else
        bram_en_delay1 <= bram_en;
end

/*
修改：删除store_row_cnt，行内列号只在一行装载期间计数，离开LOAD_LINE即清零。
*/
always @(posedge clk) begin
    if(!rstn)
        store_col_cnt <= 'd0;
    else if(CURRENT_STATE != LOAD_LINE)
        store_col_cnt <= 'd0;
    else if(bram_en_delay1) begin
        if(store_col_cnt == LINE_LEN-1)
            store_col_cnt <= 'd0;
        else
            store_col_cnt <= store_col_cnt + 1'b1;
    end
end

/*
修改：写入目标由image[store_row_cnt][store_col_cnt]改为行缓冲image_line[store_col_cnt]。
*/
always @(posedge clk) begin
    if((CURRENT_STATE == LOAD_LINE) && bram_en_delay1)
        image_line[store_col_cnt] <=
            bram_data[QUANT_SIZE-1:0];
end

/*
修改：idx跨行保持，OUTPUT_LINE期间每握手一次加一，整幅输出完成后随状态回IDLE清零。
*/
always @(posedge clk) begin
    if(!rstn)
        idx <= 'd0;
    else if(CURRENT_STATE == IDLE)
        idx <= 'd0;
    else if(O_data_Fire) begin
        if(idx == LINE_NUMS-1)
            idx <= 'd0;
        else
            idx <= idx + 1'b1;
    end
end

/*
修改：DATA_LINE改由行缓冲直接拼接，col_i为常量下标，不再有image[idx][col_i]的动态选行；
generate块名由OUTPUT_LINE改为DATA_LINE_OUT，避免与新增的OUTPUT_LINE状态名冲突。
*/
genvar col_i;
generate
    for(col_i=0; col_i<LINE_LEN; col_i=col_i+1) begin: DATA_LINE_OUT
        assign DATA_LINE[col_i*QUANT_SIZE+:QUANT_SIZE] = image_line[col_i];
    end
endgenerate

/*
调试观测：纯连线引出，不改变任何原有逻辑。
*/
assign dbg = { CURRENT_STATE, load_cnt, store_col_cnt, idx,
               bram_en_delay1, bram_en,
               I_data_valid, I_data_ready, O_data_valid, O_data_ready,
               I_data_Fire, O_data_Fire };

function integer clogb2(input integer bit_depth);
integer depth;
begin
    depth = bit_depth - 1;
    for(clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
end
endfunction

endmodule
