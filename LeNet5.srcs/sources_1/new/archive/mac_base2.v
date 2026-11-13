/*
mac_base2修
相较于mac_base1，乘法器始终读取数据寄存器最低一组，并在每个计算周期后
将下一组数据右移到最低位置，从而去掉由动态数组索引产生的多路选择逻辑。
加法树、跨周期累加器、模块接口和PIPES个计算周期均保持不变。
*/
/* mac_base1修 */
/*
 * 与mac_base.v的设计区别：
 * 1. mac_base会保存全部NUMS个乘积，全部乘法结束后再使用线性串联加法器求和；
 *    当NUMS较大时，组合加法路径较长，同时需要较多乘积寄存器。
 * 2. 本设计每个计算周期只保存当前EACH_NUMS个乘积，并使用平衡加法树
 *    计算当前组的部分和，使组内加法深度由线性增长改为log2增长。
 * 3. 从第二个计算周期开始，将上一组的加法树结果累加到部分和寄存器；
 *    CALC_END阶段再把最后一组结果加入部分和并输出最终点积结果。
 * 4. 当NUMS不能被PIPES整除时，最后一组中不存在的乘法项按零处理。
 * 5. 模块接口、乘法器并行数量、PIPES个计算周期以及valid/ready时序保持不变，
 *    主要目的是缩短加法路径并减少保存全部乘积所需的逻辑资源。
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

/* mac_base1修 */
// clogb2(EACH_NUMS-1)等价于向上取整log2(EACH_NUMS)，并单独处理单叶节点。
localparam TREE_LEVELS = (EACH_NUMS <= 1) ? 0 : clogb2(EACH_NUMS-1);
localparam TREE_NUMS   = 1 << TREE_LEVELS;
reg [7:0] calc_cnt;
reg [(NUMS) * DSIZE  -  1 : 0] data_1;
reg [(NUMS) * WSIZE  -  1 : 0] data_2;
/*
mac_base2修
只拆分数据寄存器最低的EACH_NUMS项，供当前周期的并行乘法器使用。
*/
wire signed [DSIZE  -  1 : 0] Signed_data_1[0:EACH_NUMS-1];
wire signed [WSIZE  -  1 : 0] Signed_data_2[0:EACH_NUMS-1];
genvar idx;
for (idx = 0; idx<EACH_NUMS; idx=idx+1) begin: GEN_SIGNED_DATA
    assign Signed_data_1[idx] = data_1[idx*DSIZE+:DSIZE];
    assign Signed_data_2[idx] = data_2[idx*WSIZE+:WSIZE];
end

wire I_data_Fire;
assign I_data_Fire = I_data_valid & I_data_ready;

wire signed [(DSIZE+WSIZE)-1:0] Signed_data_multiplier[0:EACH_NUMS-1];

genvar i;
for (i = 0; i<EACH_NUMS; i=i+1) begin
    /*
    mac_base2修
    乘法器固定读取最低一组数据，不再根据calc_cnt进行动态索引。
    */
    assign Signed_data_multiplier[i] = Signed_data_1[i] * Signed_data_2[i];
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
        end else if(STATE == CALC_BUSY) begin
            /*
            mac_base2修
            当前组乘积被寄存后，将下一组逻辑右移到最低位置；高位自动补零，
            因此NUMS不能被PIPES整除时，最后一组多余的乘法输入自然为零。
            */
            data_1 <= data_1 >> (EACH_NUMS*DSIZE);
            data_2 <= data_2 >> (EACH_NUMS*WSIZE);
        end else begin
            data_1 <= data_1;
            data_2 <= data_2;
        end
    end
end
/* mac_base1修 */
// 每周期只保存当前一组乘积，不再保存全部NUMS个乘积。
(*use_dsp="yes"*)reg signed [(DSIZE+WSIZE)-1:0] result_mul[0:EACH_NUMS-1];
integer j;
always @(posedge clk ) begin
    if(!rstn) begin
        for (j = 0; j<EACH_NUMS; j=j+1) begin
            result_mul[j] <= 'd0;
        end
    end else if(STATE == CALC_BUSY) begin
        for (j = 0; j<EACH_NUMS; j=j+1) begin
            result_mul[j] <= Signed_data_multiplier[j];
        end
    end
end

/* mac_base1修 */
// 平衡加法树：叶子数补齐为2的幂，树深由EACH_NUMS自动确定。
/* mac_base1修 */
// 数组按“层”展开存放，每层占TREE_NUMS个位置，便于Verilog-2001综合。
(*use_dsp="no"*)wire signed [(DSIZE+WSIZE)-1+clogb2(NUMS):0] adder_tree [0:(TREE_LEVELS+1)*TREE_NUMS-1];
genvar tree_leaf;
for(tree_leaf = 0; tree_leaf < TREE_NUMS; tree_leaf = tree_leaf + 1) begin: GEN_TREE_LEAF
    if(tree_leaf < EACH_NUMS) begin: GEN_TREE_REAL_LEAF
        assign adder_tree[tree_leaf] =
            {{clogb2(NUMS){result_mul[tree_leaf][DSIZE+WSIZE-1]}},
             result_mul[tree_leaf]};
    end else begin: GEN_TREE_ZERO_LEAF
        assign adder_tree[tree_leaf] = {(DSIZE+WSIZE+clogb2(NUMS)){1'b0}};
    end
end

genvar tree_level;
genvar tree_node;
for(tree_level = 0; tree_level < TREE_LEVELS; tree_level = tree_level + 1) begin: GEN_TREE_LEVEL
    for(tree_node = 0; tree_node < (TREE_NUMS >> (tree_level+1)); tree_node = tree_node + 1) begin: GEN_TREE_NODE
        assign adder_tree[(tree_level+1)*TREE_NUMS+tree_node] =
            adder_tree[tree_level*TREE_NUMS+tree_node*2]
          + adder_tree[tree_level*TREE_NUMS+tree_node*2+1];
    end
end

wire signed [(DSIZE+WSIZE)-1+clogb2(NUMS):0] group_sum;
assign group_sum = adder_tree[TREE_LEVELS*TREE_NUMS];

/* mac_base1修 */
// result_mul比乘法器晚一拍；从第二个计算周期开始累加上一组的树形求和结果。
reg result_mul_valid;
always @(posedge clk ) begin
    if(!rstn)
        result_mul_valid <= 1'b0;
    else
        result_mul_valid <= (STATE == CALC_BUSY);
end

/* mac_base1修 */
// 部分和明确使用逻辑资源，避免每个mac额外占用一个DSP48。
(*use_dsp="no"*)reg signed [(DSIZE+WSIZE)-1+clogb2(NUMS):0] result_accumulator;
always @(posedge clk ) begin
    if(!rstn)
        result_accumulator <= 'd0;
    else if(I_data_Fire)
        result_accumulator <= 'd0;
    else if(result_mul_valid)
        result_accumulator <= result_accumulator + group_sum;
end

reg O_DATA_valid[0:1];
always @(posedge clk ) begin
    if(!rstn) begin
        O_DATA_valid[0]<=0;
        O_DATA_valid[1]<=0;
        result_q <= 'd0;
    end else if(calc_cnt == PIPES)begin
        /* mac_base1修 */
        // CALC_END时group_sum是最后一组，和此前部分和相加后直接输出。
        result_q <= result_accumulator + group_sum;
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
