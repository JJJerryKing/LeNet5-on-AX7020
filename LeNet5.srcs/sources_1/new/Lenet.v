module Lenet#(
 parameter QUANT_SIZE  = 13 , //量化步长
 parameter WEIGHT_SIZE = 13 , //量化步长
 parameter LINE_LEN    = 32 , //输入行长度
 parameter CONV_CORE   = 5  ,  //5*5卷积核
 parameter CHANNEL_I_1 = 1  ,  //输入第一层的通道数
 parameter CHANNEL_O_1 = 6  ,  //输出第一层的通道数
 parameter CHANNEL_O_2 = 16 ,  //输出第二层的通道数
 parameter CHANNEL_O_3 = 120,  //输出第三层的通道数
 parameter CHANNEL_O_4 = 84 ,  //输出第三层的通道数
 parameter CHANNEL_O_5 = 10 ,  //输出第三层的通道数
 parameter CONV_LOG_1  = 1  ,
 parameter RELU_LOG_1  = 1  ,
 parameter POOL_LOG_1  = 1  ,
 parameter CONV_LOG_2  = 1  ,
 parameter RELU_LOG_2  = 1  ,
 parameter POOL_LOG_2  = 1  ,
 parameter CONV_LOG_3  = 1   

)(

);
localparam NUMS = CONV_CORE*CONV_CORE;
reg                                                                         clk             ;
reg                                                                         rstn            ;
reg                                                                         LOAD_INIT       ;
reg [QUANT_SIZE*LINE_LEN*CHANNEL_I_1 -   1 : 0]                             DATA_LINE       ;
reg                                                                         I_data_valid    ;
wire                                                                        I_data_ready    ;
// output      [QUANT_SIZE*CHANNEL_O_1 -  1  : 0]result_q        ,
wire                                                                        O_data_valid    ;
reg                                                                         O_data_ready    ;
//时钟源
always begin
    #5 clk <= 1;
    #5 clk <= 0;    
end
//全局复位
initial begin
  rstn = 0;
  #20 rstn = 1;
end
//还需要添加的设计：
//1，使用Bram存储权重 第一层5x5x1     x8bit 深度6
//                   第二层5x5x6     x8bit 深度16
//                   第三层5x5x16    x8bit 深度120



//region 变量
integer idx; //用以读取输入图片
integer a,b,c,d,e,f,g,h,i,aa,bb,cc,dd,ee,ff,gg,hh,ii;//用以读取权重偏执
integer fid1,fid2,fid3,fid4,fid5,fid6,fid7,fid8,fid9;//用以做文件指针
genvar  j,k,l,m,n,o,p,jj,kk,ll,mm,nn,oo,pp;//用以构建权重偏执向量
//region RAM
reg signed  [QUANT_SIZE-1:0]     image      [1:784];
reg signed  [QUANT_SIZE-1:0]     scale_zero [1:15];
reg signed  [(QUANT_SIZE-1):0]   weight_1   [1:NUMS*CHANNEL_I_1*CHANNEL_O_1];
reg signed  [(QUANT_SIZE-1):0]   weight_2   [1:NUMS*CHANNEL_O_1*CHANNEL_O_2];
reg signed  [(QUANT_SIZE-1):0]   weight_3   [1:NUMS*CHANNEL_O_2*CHANNEL_O_3];
wire signed [QUANT_SIZE * NUMS * CHANNEL_O_1 * CHANNEL_I_1 - 1 : 0] weight_minus_zeropoint_1;
wire signed [QUANT_SIZE * NUMS * CHANNEL_O_2 * CHANNEL_O_1 - 1 : 0] weight_minus_zeropoint_2;
wire signed [QUANT_SIZE * NUMS * CHANNEL_O_3 * CHANNEL_O_2 - 1 : 0] weight_minus_zeropoint_3;
//region量化相关的参数
initial begin
    {scale_zero[ 1],scale_zero[ 2],scale_zero[ 3],
     scale_zero[ 4],scale_zero[ 5],scale_zero[ 6],
     scale_zero[ 7],scale_zero[ 8],scale_zero[ 9],
     scale_zero[10],scale_zero[11],scale_zero[12],
     scale_zero[13],scale_zero[14],scale_zero[15]
     }<={
        13'd12,13'd11,13'd83,13'd14,13'd12,13'd142,13'd11,13'd13,13'd128,13'd13,13'd13,13'd115,13'd13,13'd12,13'd129
     };
end

//region输入图像2
initial begin
   fid1 = $fopen("ori0.txt","r");
   for(a=1;a<=784;a=a+1)
    begin
        $fscanf(fid1,"%d",image[a]);
    end
    $fclose(fid1);
end
//region输入权重1
// initial
// begin
//    fid2 = $fopen("c1.weight.txt","r");
//    b=1;
//    for(c=1;b<1019;c=c+1)
//        begin
//         if(c==1) begin
//             $fscanf(fid2,"tensor([[[[%d,%d,%d,%d,%d],",weight_1[b],weight_1[b+1],weight_1[b+2],weight_1[b+3],weight_1[b+4]);
//             b = b + 5;
//         end else if ( c == 40 ) begin
//             $fscanf(fid2,"[%d,%d,%d,%d,%d]]]], dtype=torch.int32)",weight_1[b],weight_1[b+1],weight_1[b+2],weight_1[b+3],weight_1[b+4]);
//             b = 1019;
//         end else if ( (c%7 > 1) && (c%7 < 5) ) begin
//             $fscanf(fid2,"[%d,%d,%d,%d,%d],",weight_1[b],weight_1[b+1],weight_1[b+2],weight_1[b+3],weight_1[b+4]);
//             b = b + 5;
//         end else if ( (c%7 == 5) ) begin
//             $fscanf(fid2,"[%d,%d,%d,%d,%d]]],",weight_1[b],weight_1[b+1],weight_1[b+2],weight_1[b+3],weight_1[b+4]);
//             b = b + 5;
//         end else if ( (c%7 == 1) ) begin
//             $fscanf(fid2,"[[[%d,%d,%d,%d,%d],",weight_1[b],weight_1[b+1],weight_1[b+2],weight_1[b+3],weight_1[b+4]);
//             b = b + 5;
//         end else if ( (c%7 == 6) || (c%7 == 0) ) begin
//             $fscanf(fid2,"\n");
//         end
//        end
//    $fclose(fid2);
// end
//region 所有权重RAM实例化
wire [2:0] c1_w_addr;
wire [199:0] c1_weight;
wire [WEIGHT_SIZE*25-1:0] c1_weight_qx_zeropoint;
blkmem_c1_weight c1_weight_mem (
  .clka(clk),    // input wire clka
  .ena(1'b1),
  .addra(c1_w_addr),  // input wire [2 : 0] addra
  .douta(c1_weight)  // output wire [199 : 0] douta
);
for(j=0;j<25;j=j+1) begin
    assign c1_weight_qx_zeropoint[WEIGHT_SIZE*j+:WEIGHT_SIZE] = c1_weight[8*j+:8] - scale_zero[3];
end

wire [4:0] c3_w_addr;
wire [3:0] c3_w_rom_addr;
wire [1199:0] c3_weight;
wire [WEIGHT_SIZE*6*25-1:0] c3_weight_qx_zeropoint;
assign c3_w_rom_addr = c3_w_addr[3:0];
blkmem_c3_weight c3_weight_mem (
  .clka(clk),    // input wire clka
  .ena(1'b1),
  .addra(c3_w_rom_addr),
  .douta(c3_weight)  // output wire [199 : 0] douta
);
for(j=0;j<25*6;j=j+1) begin
    assign c3_weight_qx_zeropoint[WEIGHT_SIZE*j+:WEIGHT_SIZE] = c3_weight[8*j+:8] - scale_zero[6];
end

wire [6:0] c5_w_addr;
wire [3199:0] c5_weight;
wire [WEIGHT_SIZE*16*25-1:0] c5_weight_qx_zeropoint;
blkmem_c5_weight c5_weight_mem (
  .clka(clk),    // input wire clka
  .ena(1'b1),
  .addra(c5_w_addr),  // input wire [2 : 0] addra
  .douta(c5_weight)  // output wire [199 : 0] douta
);
for(j=0;j<25*16;j=j+1) begin
    assign c5_weight_qx_zeropoint[WEIGHT_SIZE*j+:WEIGHT_SIZE] = c5_weight[8*j+:8] - scale_zero[9];
end

wire [6:0] f6_w_addr;
wire [959:0] f6_weight;
wire [WEIGHT_SIZE*120-1:0] f6_weight_qx_zeropoint;
blkmem_f6_weight f6_weight_mem (
  .clka(clk),    // input wire clka
  .ena(1'b1),
  .addra(f6_w_addr),  // input wire [2 : 0] addra
  .douta(f6_weight)  // output wire [199 : 0] douta
);
for(j=0;j<120;j=j+1) begin
    assign f6_weight_qx_zeropoint[WEIGHT_SIZE*j+:WEIGHT_SIZE] = f6_weight[8*j+:8] - scale_zero[12];
end

wire [3:0] op_w_addr;
wire [671:0] op_weight;
wire [WEIGHT_SIZE*84-1:0] op_weight_qx_zeropoint;
blkmem_output_weight op_weight_mem (
  .clka(clk),    // input wire clka
  .ena(1'b1),
  .addra(op_w_addr),  // input wire [2 : 0] addra
  .douta(op_weight)  // output wire [199 : 0] douta
);
for(j=0;j<84;j=j+1) begin
    assign op_weight_qx_zeropoint[WEIGHT_SIZE*j+:WEIGHT_SIZE] = op_weight[8*j+:8] - scale_zero[15];
end

//region 所有偏置RAM实例化
wire [2:0] c1_b_addr;
wire signed [31:0] c1_bias;
blkmem_c1_bias c1_bias_mem (
  .clka(clk),
  .ena(1'b1),
  .addra(c1_b_addr),
  .douta(c1_bias)
);

wire [4:0] c3_b_addr;
wire [3:0] c3_b_rom_addr;
wire signed [31:0] c3_bias;
assign c3_b_rom_addr = c3_b_addr[3:0];
blkmem_c3_bias c3_bias_mem (
  .clka(clk),
  .ena(1'b1),
  .addra(c3_b_rom_addr),
  .douta(c3_bias)
);

wire [6:0] c5_b_addr;
wire signed [31:0] c5_bias;
blkmem_c5_bias c5_bias_mem (
  .clka(clk),
  .ena(1'b1),
  .addra(c5_b_addr),
  .douta(c5_bias)
);

wire [6:0] f6_b_addr;
wire signed [31:0] f6_bias;
blkmem_f6_bias f6_bias_mem (
  .clka(clk),
  .ena(1'b1),
  .addra(f6_b_addr),
  .douta(f6_bias)
);

wire [3:0] op_b_addr;
wire signed [31:0] op_bias;
blkmem_output_bias op_bias_mem (
  .clka(clk),
  .ena(1'b1),
  .addra(op_b_addr),
  .douta(op_bias)
);

for (k = 1; k<=150; k=k+1) begin
    assign weight_minus_zeropoint_1[(k-1)*QUANT_SIZE+:QUANT_SIZE] = weight_1[k] - scale_zero[3];
end

//region输入数字2.img
initial idx <= 1;
always@(posedge clk)begin
        I_data_valid <= I_data_ready;
        O_data_ready <= 1;
        if( (idx < 33 && rstn && I_data_ready && I_data_valid) || (idx == 1 && rstn && I_data_ready))begin
            if(idx == 1 || idx == 2 || idx == 31 || idx == 32)begin
                DATA_LINE <= {0};
            end else begin
                DATA_LINE <= {  13'd0,      13'd0,                              image[(idx-3)*28+1+27],image[(idx-3)*28+1+26],
                                image[(idx-3)*28+1+25],image[(idx-3)*28+1+24],image[(idx-3)*28+1+23],image[(idx-3)*28+1+22],
                                image[(idx-3)*28+1+21],image[(idx-3)*28+1+20],image[(idx-3)*28+1+19],image[(idx-3)*28+1+18],
                                image[(idx-3)*28+1+17],image[(idx-3)*28+1+16],image[(idx-3)*28+1+15],image[(idx-3)*28+1+14],
                                image[(idx-3)*28+1+13],image[(idx-3)*28+1+12],image[(idx-3)*28+1+11],image[(idx-3)*28+1+10],
                                image[(idx-3)*28+1+9 ],image[(idx-3)*28+1+8 ],image[(idx-3)*28+1+7 ],image[(idx-3)*28+1+6 ],
                                image[(idx-3)*28+1+5 ],image[(idx-3)*28+1+4 ],image[(idx-3)*28+1+3 ],image[(idx-3)*28+1+2 ],
                                image[(idx-3)*28+1+1 ],image[(idx-3)*28+1+0 ],13'd0,      13'd0       };
            end
            idx <= idx + 1;
        end
end

//region第一层 卷积单元
wire [CHANNEL_O_1*QUANT_SIZE-1:0] conv1_out;
wire conv1_out_valid;
wire conv1_out_ready;

line_loader_plus#(
.QUANT_SIZE  ( QUANT_SIZE ), //量化步长
.WEIGHT_SIZE ( QUANT_SIZE ), //量化步长
.LINE_LEN    ( 32 ), //输入行长度
.LINE_LEN_O  ( 28 ), //输出行长度
.PADDING     ( 2  ), //padding长度
.PIPES       ( 5  ), //乘法打几拍
.CONV_CORE   ( 5  ),  //5*5卷积核
.CHANNEL_I   ( CHANNEL_I_1  ),  //5*5卷积核
.CHANNEL_O   ( CHANNEL_O_1  ),  //5*5卷积核
.ADDSIZE     ( 0            )
) conv1(
    .clk            (clk) ,
    .rstn           (rstn) ,
    .LOAD_INIT      (1'b1) ,
    .DATA_LINE      (DATA_LINE) ,
    // .WEIGHT_BLK     (weight_minus_zeropoint_1) ,
    .weight_input   (c1_weight_qx_zeropoint) ,
    .weight_addr    (c1_w_addr) ,
    .bias_input     (c1_bias) ,
    .bias_addr      (c1_b_addr) ,
    .SCALE          (scale_zero[1]) ,
    .SHIFT          (scale_zero[2]) ,
    .I_data_valid   (I_data_valid) ,
    .I_data_ready   (I_data_ready) ,
    .result_q       (conv1_out) ,
    .O_data_valid   (conv1_out_valid) ,
    .O_data_ready   (conv1_out_ready) 
);
//region第一层输出打印，可以调整宏来控制
integer conv1_out_idx;
integer conv1_out_file[0:5];
initial begin
    if(CONV_LOG_1 == 1)  begin
        conv1_out_idx = 1;
        conv1_out_file[0] = $fopen("./log/layer1/conv0_out.txt", "w"); 
        conv1_out_file[1] = $fopen("./log/layer1/conv1_out.txt", "w");
        conv1_out_file[2] = $fopen("./log/layer1/conv2_out.txt", "w");
        conv1_out_file[3] = $fopen("./log/layer1/conv3_out.txt", "w");
        conv1_out_file[4] = $fopen("./log/layer1/conv4_out.txt", "w");
        conv1_out_file[5] = $fopen("./log/layer1/conv5_out.txt", "w");
    end
end
always @(posedge clk) begin
    if(conv1_out_ready && conv1_out_valid && CONV_LOG_1 == 1)begin

        conv1_out_idx = conv1_out_idx + 1;
        for (e = 0; e<CHANNEL_O_1; e=e+1) begin
            $fwrite(conv1_out_file[e], "%4d ", $signed(conv1_out[e*QUANT_SIZE+:QUANT_SIZE]) ) ;
        end

        if(conv1_out_idx %28 == 1 && conv1_out_idx != 1 ) begin
            for (e = 0; e<CHANNEL_O_1; e=e+1) begin
                $fwrite(conv1_out_file[e], "\n") ;
            end
        end
        
        if(conv1_out_idx == 28*28+1) begin
            for (e = 0; e<CHANNEL_O_1; e=e+1) begin
                $fclose(conv1_out_file[e]) ;
            end
        end
    end
end
//region第二层 ReLu
wire [QUANT_SIZE*CHANNEL_O_1-1:0] relu1_out;
wire relu1_out_valid;
wire relu1_out_ready;

relu_plus#(
 .QUANT_SIZE ( QUANT_SIZE ),
 .LINE_LEN   ( 28 ), //28
 .CORE_NUMS  ( 6  )//28
) relu1(
    .clk            (clk)  ,
    .rstn           (rstn)  ,
    .data_in        (conv1_out)  ,
    .I_relu_valid   (conv1_out_valid)  ,
    .I_relu_ready   (conv1_out_ready)  ,
    .relu_out       (relu1_out)  ,
    .O_relu_valid   (relu1_out_valid)  ,
    .O_relu_ready   (relu1_out_ready)  
);

//region第二层输出打印，可以调整宏来控制
integer relu1_out_idx;
integer relu1_out_file[0:5];
initial begin
    if(RELU_LOG_1 == 1)  begin
        relu1_out_idx = 1;
        relu1_out_file[0] = $fopen("./log/layer1/relu0_out.txt", "w"); 
        relu1_out_file[1] = $fopen("./log/layer1/relu1_out.txt", "w");
        relu1_out_file[2] = $fopen("./log/layer1/relu2_out.txt", "w");
        relu1_out_file[3] = $fopen("./log/layer1/relu3_out.txt", "w");
        relu1_out_file[4] = $fopen("./log/layer1/relu4_out.txt", "w");
        relu1_out_file[5] = $fopen("./log/layer1/relu5_out.txt", "w");
    end
end
always @(posedge clk) begin
    if(relu1_out_valid && relu1_out_ready && RELU_LOG_1 == 1)begin

        relu1_out_idx = relu1_out_idx + 1;
        for (e = 0; e<CHANNEL_O_1; e=e+1) begin
            $fwrite(relu1_out_file[e], "%4d ", $signed(relu1_out[e*QUANT_SIZE+:QUANT_SIZE]) ) ;
        end

        if(relu1_out_idx %28 == 1 && relu1_out_idx != 1 ) begin
            for (e = 0; e<CHANNEL_O_1; e=e+1) begin
                $fwrite(relu1_out_file[e], "\n") ;
            end
        end
        
        if(relu1_out_idx == 28*28+1) begin
            for (e = 0; e<CHANNEL_O_1; e=e+1) begin
                $fclose(relu1_out_file[e]) ;
            end
        end
    end
end

//region第三层 池化
wire [QUANT_SIZE*CHANNEL_O_1-1:0] pool1_out;
wire pool1_out_valid;
wire pool1_out_ready;

average_pooling#(
.QUANT_SIZE ( QUANT_SIZE ),
.LINE_LEN   ( 28 ), 
.CORE_NUMS  ( 6  )   

) average_pooling_1(
.clk            (clk),
.rstn           (rstn),
.data_in        (relu1_out),
.I_data_valid   (relu1_out_valid),
.I_data_ready   (relu1_out_ready),
.pool_out       (pool1_out),
.O_data_valid   (pool1_out_valid),
.O_data_ready   (pool1_out_ready)
);

//region第三层输出打印，可以调整宏来控制
integer pool1_out_idx;
integer pool1_out_file[0:5];
initial begin
    if(POOL_LOG_1 == 1)  begin
        pool1_out_idx = 1;
        pool1_out_file[0] = $fopen("./log/layer1/pool0_out.txt", "w"); 
        pool1_out_file[1] = $fopen("./log/layer1/pool1_out.txt", "w");
        pool1_out_file[2] = $fopen("./log/layer1/pool2_out.txt", "w");
        pool1_out_file[3] = $fopen("./log/layer1/pool3_out.txt", "w");
        pool1_out_file[4] = $fopen("./log/layer1/pool4_out.txt", "w");
        pool1_out_file[5] = $fopen("./log/layer1/pool5_out.txt", "w");
    end
end
always @(posedge clk) begin
    if(pool1_out_valid && pool1_out_ready && POOL_LOG_1 == 1)begin

        pool1_out_idx = pool1_out_idx + 1;
        for (e = 0; e<CHANNEL_O_1; e=e+1) begin
            $fwrite(pool1_out_file[e], "%4d ", $signed(pool1_out[e*QUANT_SIZE+:QUANT_SIZE]) ) ;
        end

        if(pool1_out_idx %14 == 1 && pool1_out_idx != 1 ) begin
            for (e = 0; e<CHANNEL_O_1; e=e+1) begin
                $fwrite(pool1_out_file[e], "\n") ;
            end
        end
        
        if(pool1_out_idx == 14*14+1) begin
            for (e = 0; e<CHANNEL_O_1; e=e+1) begin
                $fclose(pool1_out_file[e]) ;
            end
        end
    end
end
//region中间层 行缓冲器 把输入 6*1*12缓冲成 6*14*12
wire line_cache1_valid;
wire line_cache1_ready;
wire [CHANNEL_O_1*14*QUANT_SIZE-1:0] line_cache_1;

Line_Cache2#(
.QUANT_SIZE( QUANT_SIZE ) ,
.LINE_LEN  ( 14 ) ,
.CORE_NUMS ( 6  )  
) line_cache1(
    .clk            (clk),
    .rstn           (rstn),
    .data_in        (pool1_out),
    .I_data_valid   (pool1_out_valid),
    .I_data_ready   (pool1_out_ready),
    .data_out       (line_cache_1),
    .O_data_valid   (line_cache1_valid),
    .O_data_ready   (line_cache1_ready)
);
//region第四层权重偏置输入
// initial
// begin
//    fid4 = $fopen("c3.weight.txt","r");
//     g = 1;
//    for(f=1;f<=96;f=f+1)
//        begin
//         if(f==1) begin
//            $fscanf(fid4,"tensor([[[[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d]],\n",
//           weight_2[g],weight_2[g+1],weight_2[g+2],weight_2[g+3],weight_2[g+4],
//           weight_2[g+5],weight_2[g+6],weight_2[g+7],weight_2[g+8],weight_2[g+9],
//           weight_2[g+10],weight_2[g+11],weight_2[g+12],weight_2[g+13],weight_2[g+14],
//           weight_2[g+15],weight_2[g+16],weight_2[g+17],weight_2[g+18],weight_2[g+19],
//           weight_2[g+20],weight_2[g+21],weight_2[g+22],weight_2[g+23],weight_2[g+24]
//           );
//           g = g + 25;
//         end else if((f%6 > 1) && (f%6 < 6)) begin
//            $fscanf(fid4,"[[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d]],\n",
//           weight_2[g],weight_2[g+1],weight_2[g+2],weight_2[g+3],weight_2[g+4],
//           weight_2[g+5],weight_2[g+6],weight_2[g+7],weight_2[g+8],weight_2[g+9],
//           weight_2[g+10],weight_2[g+11],weight_2[g+12],weight_2[g+13],weight_2[g+14],
//           weight_2[g+15],weight_2[g+16],weight_2[g+17],weight_2[g+18],weight_2[g+19],
//           weight_2[g+20],weight_2[g+21],weight_2[g+22],weight_2[g+23],weight_2[g+24]
//           );
//           g = g + 25;
//         end else if(f%6 == 0) begin
//            $fscanf(fid4,"[[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d]]],\n\n",
//           weight_2[g],weight_2[g+1],weight_2[g+2],weight_2[g+3],weight_2[g+4],
//           weight_2[g+5],weight_2[g+6],weight_2[g+7],weight_2[g+8],weight_2[g+9],
//           weight_2[g+10],weight_2[g+11],weight_2[g+12],weight_2[g+13],weight_2[g+14],
//           weight_2[g+15],weight_2[g+16],weight_2[g+17],weight_2[g+18],weight_2[g+19],
//           weight_2[g+20],weight_2[g+21],weight_2[g+22],weight_2[g+23],weight_2[g+24]
//           );
//           g = g + 25;
//         end else if(f%6 == 1) begin
//             $fscanf(fid4,"[[[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d]],\n",
//           weight_2[g],weight_2[g+1],weight_2[g+2],weight_2[g+3],weight_2[g+4],
//           weight_2[g+5],weight_2[g+6],weight_2[g+7],weight_2[g+8],weight_2[g+9],
//           weight_2[g+10],weight_2[g+11],weight_2[g+12],weight_2[g+13],weight_2[g+14],
//           weight_2[g+15],weight_2[g+16],weight_2[g+17],weight_2[g+18],weight_2[g+19],
//           weight_2[g+20],weight_2[g+21],weight_2[g+22],weight_2[g+23],weight_2[g+24]
//           );
//           g = g + 25;          
//         end
//        end
//    $fclose(fid4);
// end
// for (m = 1; m<=CHANNEL_O_1*CHANNEL_O_2*NUMS; m=m+1) begin
//     assign weight_minus_zeropoint_2[(m-1)*QUANT_SIZE+:QUANT_SIZE] = weight_2[m] - scale_zero[6];
// end

//region第四层 卷积单元
localparam ADDSIZE = 2;
wire conv2_out_valid;
wire conv2_out_ready;
wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_2-1:0]conv2_out;

line_loader_plus#(
.QUANT_SIZE  ( QUANT_SIZE ), //量化步长
.WEIGHT_SIZE ( QUANT_SIZE ), //量化步长
.LINE_LEN    ( 14 ), //输入行长度
.LINE_LEN_O  ( 10 ), //输出行长度
.PADDING     ( 0  ), //padding长度
.PIPES       ( 5  ), //乘法打几拍
.CONV_CORE   ( 5  ),  //5*5卷积核
.CHANNEL_I   ( CHANNEL_O_1  ),  //5*5卷积核
.CHANNEL_O   ( CHANNEL_O_2  ) ,  //5*5卷积核
.ADDSIZE     ( ADDSIZE      )
) conv2(
    .clk            (clk) ,
    .rstn           (rstn) ,
    .LOAD_INIT      (1'b1) ,
    .DATA_LINE      (line_cache_1) ,
    // .WEIGHT_BLK     (weight_minus_zeropoint_2) ,
    .weight_input   (c3_weight_qx_zeropoint) ,
    .weight_addr    (c3_w_addr) ,
    .bias_input     (c3_bias) ,
    .bias_addr      (c3_b_addr) ,
    .SCALE          (scale_zero[4]) ,
    .SHIFT          (scale_zero[5]) ,
    .I_data_valid   (line_cache1_valid) ,
    .I_data_ready   (line_cache1_ready) ,
    .result_q       (conv2_out) ,
    .O_data_valid   (conv2_out_valid) ,
    .O_data_ready   (conv2_out_ready) 
);
//region第四层输出打印，可以调整宏来控制
integer conv2_out_idx;
integer conv2_out_file[0:15];
initial begin
    if(CONV_LOG_2 == 1)  begin
        conv2_out_idx = 1;
        conv2_out_file[0] = $fopen("./log/layer2/conv0_out.txt", "w"); 
        conv2_out_file[1] = $fopen("./log/layer2/conv1_out.txt", "w");
        conv2_out_file[2] = $fopen("./log/layer2/conv2_out.txt", "w");
        conv2_out_file[3] = $fopen("./log/layer2/conv3_out.txt", "w");
        conv2_out_file[4] = $fopen("./log/layer2/conv4_out.txt", "w");
        conv2_out_file[5] = $fopen("./log/layer2/conv5_out.txt", "w");
        conv2_out_file[6] = $fopen("./log/layer2/conv6_out.txt", "w"); 
        conv2_out_file[7] = $fopen("./log/layer2/conv7_out.txt", "w");
        conv2_out_file[8] = $fopen("./log/layer2/conv8_out.txt", "w");
        conv2_out_file[9] = $fopen("./log/layer2/conv9_out.txt", "w");
        conv2_out_file[10] = $fopen("./log/layer2/conv10_out.txt", "w");
        conv2_out_file[11] = $fopen("./log/layer2/conv11_out.txt", "w");
        conv2_out_file[12] = $fopen("./log/layer2/conv12_out.txt", "w"); 
        conv2_out_file[13] = $fopen("./log/layer2/conv13_out.txt", "w");
        conv2_out_file[14] = $fopen("./log/layer2/conv14_out.txt", "w");
        conv2_out_file[15] = $fopen("./log/layer2/conv15_out.txt", "w");

    end
end
always @(posedge clk) begin
    if(conv2_out_ready && conv2_out_valid && CONV_LOG_2 == 1)begin

        conv2_out_idx = conv2_out_idx + 1;
        for (e = 0; e<CHANNEL_O_2; e=e+1) begin
            $fwrite(conv2_out_file[e], "%4d ", $signed(conv2_out[e*(QUANT_SIZE+ADDSIZE) +: (QUANT_SIZE+ADDSIZE) ]) ) ;
        end

        if(conv2_out_idx %10 == 1 && conv2_out_idx != 1 ) begin
            for (e = 0; e<CHANNEL_O_2; e=e+1) begin
                $fwrite(conv2_out_file[e], "\n") ;
            end
        end
        
        if(conv2_out_idx == 10*10+1) begin
            for (e = 0; e<CHANNEL_O_2; e=e+1) begin
                $fclose(conv2_out_file[e]) ;
            end
        end
    end
end
//region 第五层 ReLu
wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_2-1:0] relu2_out;
wire relu2_out_valid;
wire relu2_out_ready;

relu_plus#(
 .QUANT_SIZE ( QUANT_SIZE+ADDSIZE ),
 .LINE_LEN   ( 10 ), //28
 .CORE_NUMS  ( 16 )//28
) relu2(
    .clk            (clk)  ,
    .rstn           (rstn)  ,
    .data_in        (conv2_out)  ,
    .I_relu_valid   (conv2_out_valid)  ,
    .I_relu_ready   (conv2_out_ready)  ,
    .relu_out       (relu2_out)  ,
    .O_relu_valid   (relu2_out_valid)  ,
    .O_relu_ready   (relu2_out_ready)  
);

//region第五层输出打印，可以调整宏来控制
integer relu2_out_idx;
integer relu2_out_file[0:15];
initial begin
    if(RELU_LOG_2 == 1)  begin
        relu2_out_idx = 1;
        relu2_out_file[0]  = $fopen("./log/layer2/relu0_out.txt", "w"); 
        relu2_out_file[1]  = $fopen("./log/layer2/relu1_out.txt", "w");
        relu2_out_file[2]  = $fopen("./log/layer2/relu2_out.txt", "w");
        relu2_out_file[3]  = $fopen("./log/layer2/relu3_out.txt", "w");
        relu2_out_file[4]  = $fopen("./log/layer2/relu4_out.txt", "w");
        relu2_out_file[5]  = $fopen("./log/layer2/relu5_out.txt", "w");
        relu2_out_file[6]  = $fopen("./log/layer2/relu6_out.txt", "w"); 
        relu2_out_file[7]  = $fopen("./log/layer2/relu7_out.txt", "w");
        relu2_out_file[8]  = $fopen("./log/layer2/relu8_out.txt", "w");
        relu2_out_file[9]  = $fopen("./log/layer2/relu9_out.txt", "w");
        relu2_out_file[10] = $fopen("./log/layer2/relu10_out.txt", "w");
        relu2_out_file[11] = $fopen("./log/layer2/relu11_out.txt", "w");
        relu2_out_file[12] = $fopen("./log/layer2/relu12_out.txt", "w"); 
        relu2_out_file[13] = $fopen("./log/layer2/relu13_out.txt", "w");
        relu2_out_file[14] = $fopen("./log/layer2/relu14_out.txt", "w");
        relu2_out_file[15] = $fopen("./log/layer2/relu15_out.txt", "w");
    end
end
always @(posedge clk) begin
    if(relu2_out_valid && relu2_out_ready && RELU_LOG_2 == 1)begin

        relu2_out_idx = relu2_out_idx + 1;
        for (e = 0; e<CHANNEL_O_2; e=e+1) begin
            $fwrite(relu2_out_file[e], "%4d ", $signed(relu2_out[e*(QUANT_SIZE+ADDSIZE)+:(QUANT_SIZE+ADDSIZE)]) ) ;
        end

        if(relu2_out_idx %10 == 1 && relu2_out_idx != 1 ) begin
            for (e = 0; e<CHANNEL_O_2; e=e+1) begin
                $fwrite(relu2_out_file[e], "\n") ;
            end
        end
        
        if(relu2_out_idx == 10*10+1) begin
            for (e = 0; e<CHANNEL_O_2; e=e+1) begin
                $fclose(relu2_out_file[e]) ;
            end
        end
    end
end

//region第六层 池化
wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_2-1:0] pool2_out;
wire pool2_out_valid;
wire pool2_out_ready;

average_pooling#(
.QUANT_SIZE ( QUANT_SIZE+ADDSIZE ),
.LINE_LEN   ( 10 ), 
.CORE_NUMS  ( 16 )   

) average_pooling_2(
.clk            (clk),
.rstn           (rstn),
.data_in        (relu2_out),
.I_data_valid   (relu2_out_valid),
.I_data_ready   (relu2_out_ready),
.pool_out       (pool2_out),
.O_data_valid   (pool2_out_valid),
.O_data_ready   (pool2_out_ready)
);

//region第六层输出打印，可以调整宏来控制
integer pool2_out_idx;
integer pool2_out_file[0:15];
initial begin
    if(POOL_LOG_2 == 1)  begin
        pool2_out_idx = 1;
        pool2_out_file[0]  = $fopen("./log/layer2/pool0_out.txt", "w"); 
        pool2_out_file[1]  = $fopen("./log/layer2/pool1_out.txt", "w");
        pool2_out_file[2]  = $fopen("./log/layer2/pool2_out.txt", "w");
        pool2_out_file[3]  = $fopen("./log/layer2/pool3_out.txt", "w");
        pool2_out_file[4]  = $fopen("./log/layer2/pool4_out.txt", "w");
        pool2_out_file[5]  = $fopen("./log/layer2/pool5_out.txt", "w");
        pool2_out_file[6]  = $fopen("./log/layer2/pool6_out.txt", "w"); 
        pool2_out_file[7]  = $fopen("./log/layer2/pool7_out.txt", "w");
        pool2_out_file[8]  = $fopen("./log/layer2/pool8_out.txt", "w");
        pool2_out_file[9]  = $fopen("./log/layer2/pool9_out.txt", "w");
        pool2_out_file[10] = $fopen("./log/layer2/pool10_out.txt", "w");
        pool2_out_file[11] = $fopen("./log/layer2/pool11_out.txt", "w");
        pool2_out_file[12] = $fopen("./log/layer2/pool12_out.txt", "w"); 
        pool2_out_file[13] = $fopen("./log/layer2/pool13_out.txt", "w");
        pool2_out_file[14] = $fopen("./log/layer2/pool14_out.txt", "w");
        pool2_out_file[15] = $fopen("./log/layer2/pool15_out.txt", "w");
    end
end
always @(posedge clk) begin
    if(pool2_out_valid && pool2_out_ready && POOL_LOG_2 == 1)begin

        pool2_out_idx = pool2_out_idx + 1;
        for (e = 0; e<CHANNEL_O_2; e=e+1) begin
            $fwrite(pool2_out_file[e], "%4d ", $signed(pool2_out[e*(QUANT_SIZE+ADDSIZE)+:(QUANT_SIZE+ADDSIZE)]) ) ;
        end

        if(pool2_out_idx %5 == 1 && pool2_out_idx != 1 ) begin
            for (e = 0; e<CHANNEL_O_2; e=e+1) begin
                $fwrite(pool2_out_file[e], "\n") ;
            end
        end
        
        if(pool2_out_idx == 5*5+1) begin
            for (e = 0; e<CHANNEL_O_2; e=e+1) begin
                $fclose(pool2_out_file[e]) ;
            end
        end
    end
end
//region为了减少不必要的带宽，把从池化器里输出的减少2bit位宽。
wire [(QUANT_SIZE)*CHANNEL_O_2-1:0] pool2_out_low_bit;
for (o = 0; o < CHANNEL_O_2; o=o+1) begin
    assign pool2_out_low_bit[o*QUANT_SIZE+:QUANT_SIZE] = pool2_out[o*(QUANT_SIZE+ADDSIZE)+:QUANT_SIZE];
end
//region 中间层，行缓冲器
wire line_cache2_valid;
wire line_cache2_ready;
wire [CHANNEL_O_2*5*QUANT_SIZE-1:0] line_cache_2;

Line_Cache2#(
.QUANT_SIZE( QUANT_SIZE ) ,
.LINE_LEN  ( 5  ) ,
.CORE_NUMS ( 16 )  
) line_cache2(
    .clk            (clk),
    .rstn           (rstn),
    .data_in        (pool2_out_low_bit),
    .I_data_valid   (pool2_out_valid),
    .I_data_ready   (pool2_out_ready),
    .data_out       (line_cache_2),
    .O_data_valid   (line_cache2_valid),
    .O_data_ready   (line_cache2_ready)
);

//region第七层权重偏置输入
// initial
// begin
//    fid6 = $fopen("c5.weight.txt","r");
//     aa = 1;
//    for(bb=1;bb<=120*16;bb=bb+1)
//        begin
//         if(bb==1) begin
//              $fscanf(fid6,"tensor([[[[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d]],\n",
//           weight_3[aa],weight_3[aa+1],weight_3[aa+2],weight_3[aa+3],weight_3[aa+4],
//           weight_3[aa+5],weight_3[aa+6],weight_3[aa+7],weight_3[aa+8],weight_3[aa+9],
//           weight_3[aa+10],weight_3[aa+11],weight_3[aa+12],weight_3[aa+13],weight_3[aa+14],
//           weight_3[aa+15],weight_3[aa+16],weight_3[aa+17],weight_3[aa+18],weight_3[aa+19],
//           weight_3[aa+20],weight_3[aa+21],weight_3[aa+22],weight_3[aa+23],weight_3[aa+24]
//           );
//           aa = aa + 25;
//         end else if((bb%16 > 1) && (bb%16 < 16)) begin
//              $fscanf(fid6,"[[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d]],\n",
//           weight_3[aa],weight_3[aa+1],weight_3[aa+2],weight_3[aa+3],weight_3[aa+4],
//           weight_3[aa+5],weight_3[aa+6],weight_3[aa+7],weight_3[aa+8],weight_3[aa+9],
//           weight_3[aa+10],weight_3[aa+11],weight_3[aa+12],weight_3[aa+13],weight_3[aa+14],
//           weight_3[aa+15],weight_3[aa+16],weight_3[aa+17],weight_3[aa+18],weight_3[aa+19],
//           weight_3[aa+20],weight_3[aa+21],weight_3[aa+22],weight_3[aa+23],weight_3[aa+24]
//           );
//           aa = aa + 25;
//         end else if(bb%16 == 0) begin
//              $fscanf(fid6,"[[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d]]],\n\n",
//           weight_3[aa],weight_3[aa+1],weight_3[aa+2],weight_3[aa+3],weight_3[aa+4],
//           weight_3[aa+5],weight_3[aa+6],weight_3[aa+7],weight_3[aa+8],weight_3[aa+9],
//           weight_3[aa+10],weight_3[aa+11],weight_3[aa+12],weight_3[aa+13],weight_3[aa+14],
//           weight_3[aa+15],weight_3[aa+16],weight_3[aa+17],weight_3[aa+18],weight_3[aa+19],
//           weight_3[aa+20],weight_3[aa+21],weight_3[aa+22],weight_3[aa+23],weight_3[aa+24]
//           );
//           aa = aa + 25;
//         end else if(bb%16 == 1) begin
//              $fscanf(fid6,"[[[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d],[%d, %d, %d, %d, %d]],\n",
//           weight_3[aa],weight_3[aa+1],weight_3[aa+2],weight_3[aa+3],weight_3[aa+4],
//           weight_3[aa+5],weight_3[aa+6],weight_3[aa+7],weight_3[aa+8],weight_3[aa+9],
//           weight_3[aa+10],weight_3[aa+11],weight_3[aa+12],weight_3[aa+13],weight_3[aa+14],
//           weight_3[aa+15],weight_3[aa+16],weight_3[aa+17],weight_3[aa+18],weight_3[aa+19],
//           weight_3[aa+20],weight_3[aa+21],weight_3[aa+22],weight_3[aa+23],weight_3[aa+24]
//           );
//           aa = aa + 25;          
//         end
//        end
//    $fclose(fid6);
// end
for (mm = 1; mm<=CHANNEL_O_2*CHANNEL_O_3*NUMS; mm=mm+1) begin
    assign weight_minus_zeropoint_3[(mm-1)*QUANT_SIZE+:QUANT_SIZE] = weight_3[mm] - scale_zero[9];
end

//region第七层 卷积单元
wire conv3_out_valid;
wire conv3_out_ready;
wire [(QUANT_SIZE+ADDSIZE)*CHANNEL_O_3-1:0]conv3_out;

line_loader_plus#(
.QUANT_SIZE  ( QUANT_SIZE ), //量化步长
.WEIGHT_SIZE ( QUANT_SIZE ), //量化步长
.LINE_LEN    ( 5  ), //输入行长度
.LINE_LEN_O  ( 1  ), //输出行长度
.PADDING     ( 0  ), //padding长度
.PIPES       ( 5  ), //乘法打几拍
.CONV_CORE   ( 5  ),  //5*5卷积核
.CHANNEL_I   ( CHANNEL_O_2  ),  
.CHANNEL_O   ( CHANNEL_O_3  ), 
.ADDSIZE     ( ADDSIZE      )
) conv3(
    .clk            (clk) ,
    .rstn           (rstn) ,
    .LOAD_INIT      (1'b1) ,
    .DATA_LINE      (line_cache_2) ,
    // .WEIGHT_BLK     (weight_minus_zeropoint_3) ,
    .weight_input   (c5_weight_qx_zeropoint) ,
    .weight_addr    (c5_w_addr) ,
    .bias_input     (c5_bias) ,
    .bias_addr      (c5_b_addr) ,
    .SCALE          (scale_zero[7]) ,
    .SHIFT          (scale_zero[8]) ,
    .I_data_valid   (line_cache2_valid) ,
    .I_data_ready   (line_cache2_ready) ,
    .result_q       (conv3_out) ,
    .O_data_valid   (conv3_out_valid) ,
    .O_data_ready   (conv3_out_ready) 
);
//region第七层输出打印，可以调整宏来控制
integer conv3_out_idx;
integer conv3_out_file;
integer gen_idx;
initial begin
    if(CONV_LOG_3 == 1)  begin
        
        conv3_out_file = $fopen("./log/layer3/flatten_out.txt", "w"); 
        
        conv3_out_idx = 1;
    end
end
always @(posedge clk) begin
    if(conv3_out_ready && conv3_out_valid && CONV_LOG_3 == 1)begin

        conv3_out_idx = conv3_out_idx + 1;
        for (e = 0; e<CHANNEL_O_3; e=e+1) begin
            $fwrite(conv3_out_file, "%4d ", $signed(conv3_out[e*(QUANT_SIZE+ADDSIZE) +: (QUANT_SIZE+ADDSIZE) ]) ) ;
        end
        $fwrite(conv3_out_file, "\n") ;
        $fclose(conv3_out_file) ;
    end
end


//region第八层Flatten  但是这个操作比较简单，我们在第七层输出时其实已经flatten过了所以这层就不用特殊设计了


//region为了减少不必要的带宽，把从第三层卷积里输出的减少2bit位宽。
wire [(QUANT_SIZE)*CHANNEL_O_3-1:0] conv3_out_low_bit;
for (o = 0; o < CHANNEL_O_3; o=o+1) begin
    assign conv3_out_low_bit[o*QUANT_SIZE+:QUANT_SIZE] = conv3_out[o*(QUANT_SIZE+ADDSIZE)+:QUANT_SIZE];
end

//region第九层 Fullconnect
wire fc1_out_valid;
wire fc1_out_ready;
wire [CHANNEL_O_4*QUANT_SIZE-1:0] fc1_output;
fullconnect#(
.QUANT_SIZE ( QUANT_SIZE ), //量化步长
.WEIGHT_SIZE( WEIGHT_SIZE ), //量化步长
.LINE_LEN   ( 120), //输入行长度
.LINE_LEN_O ( 84 ), //输入行长度
.PIPES      ( 20 ), //乘法打几拍
.ADDSIZE    ( 0  )   //输出需要补充的大小
) fc1(
.clk            ( clk ),
.rstn           ( rstn ),
.DATA_LINE      ( conv3_out_low_bit ),
.weight_input   ( f6_weight_qx_zeropoint ),
.weight_addr    ( f6_w_addr ),
.bias_input     ( f6_bias ),
.bias_addr      ( f6_b_addr ),
.SCALE          (scale_zero[10]),
.SHIFT          (scale_zero[11]),
.I_data_valid   ( conv3_out_valid ),
.I_data_ready   ( conv3_out_ready ),
.result_q       ( fc1_output    ),
.O_data_valid   ( fc1_out_valid ),
.O_data_ready   ( fc1_out_ready ) 

);

//region第九层 Fullconnect
wire op_out_valid;
wire op_out_ready;
wire [CHANNEL_O_5*(QUANT_SIZE+2)-1:0] op_output;
fullconnect#(
.QUANT_SIZE ( QUANT_SIZE ), //量化步长
.WEIGHT_SIZE( WEIGHT_SIZE ), //量化步长
.LINE_LEN   ( 84 ), //输入行长度
.LINE_LEN_O ( 10 ), //输入行长度
.PIPES      ( 2  ), //乘法打几拍
.ADDSIZE    ( 2  )   //输出需要补充的大小
) op(
.clk            ( clk ),
.rstn           ( rstn ),
.DATA_LINE      ( fc1_output             ),
.weight_input   ( op_weight_qx_zeropoint ),
.weight_addr    ( op_w_addr ),
.bias_input     ( op_bias ),
.bias_addr      ( op_b_addr ),
.SCALE          (scale_zero[13]),
.SHIFT          (scale_zero[14]),
.I_data_valid   ( fc1_out_valid ),
.I_data_ready   ( fc1_out_ready ),
.result_q       ( op_output ),
.O_data_valid   ( op_out_valid ),
.O_data_ready   ( op_out_ready ) 

);

assign O_data_valid = op_out_valid;
assign op_out_ready = O_data_ready;
endmodule
