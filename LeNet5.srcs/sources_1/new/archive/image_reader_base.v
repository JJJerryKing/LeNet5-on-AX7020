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
input                                               O_data_ready
);

localparam IMAGE_PIXELS = LINE_LEN*LINE_NUMS;
localparam ADDR_WIDTH   = clogb2(IMAGE_PIXELS);
localparam COUNT_WIDTH  = clogb2(IMAGE_PIXELS+1);
localparam INDEX_WIDTH  = clogb2(LINE_NUMS);
localparam COL_WIDTH    = clogb2(LINE_LEN);

localparam IDLE         = 2'd0;
localparam LOAD_IMAGE   = 2'd1;
localparam OUTPUT_IMAGE = 2'd2;

wire I_data_Fire;
wire O_data_Fire;

reg [1:0] CURRENT_STATE;
reg [COUNT_WIDTH-1:0] load_cnt;
reg [INDEX_WIDTH-1:0] store_row_cnt;
reg [COL_WIDTH-1:0] store_col_cnt;
reg bram_en_delay1;
reg [INDEX_WIDTH-1:0] idx;
reg [QUANT_SIZE-1:0] image[0:LINE_NUMS-1][0:LINE_LEN-1];

assign I_data_Fire = I_data_valid && I_data_ready;
assign O_data_Fire = O_data_valid && O_data_ready;

assign I_data_ready = (CURRENT_STATE == IDLE);
assign O_data_valid = (CURRENT_STATE == OUTPUT_IMAGE);

assign bram_en   = (CURRENT_STATE == LOAD_IMAGE) &&
                   (load_cnt < IMAGE_PIXELS);
assign bram_addr = load_cnt[ADDR_WIDTH-1:0];

always @(posedge clk) begin
    if(!rstn)
        CURRENT_STATE <= IDLE;
    else if((CURRENT_STATE == IDLE) && I_data_Fire)
        CURRENT_STATE <= LOAD_IMAGE;
    else if((CURRENT_STATE == LOAD_IMAGE) && bram_en_delay1 &&
            (store_row_cnt == LINE_NUMS-1) &&
            (store_col_cnt == LINE_LEN-1))
        CURRENT_STATE <= OUTPUT_IMAGE;
    else if((CURRENT_STATE == OUTPUT_IMAGE) && O_data_Fire &&
            (idx == LINE_NUMS-1))
        CURRENT_STATE <= IDLE;
end

always @(posedge clk) begin
    if(!rstn)
        load_cnt <= 'd0;
    else if(CURRENT_STATE != LOAD_IMAGE)
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

always @(posedge clk) begin
    if(!rstn) begin
        store_row_cnt <= 'd0;
        store_col_cnt <= 'd0;
    end else if(CURRENT_STATE != LOAD_IMAGE) begin
        store_row_cnt <= 'd0;
        store_col_cnt <= 'd0;
    end
    else if(bram_en_delay1) begin
        if(store_col_cnt == LINE_LEN-1) begin
            store_col_cnt <= 'd0;
            if(store_row_cnt == LINE_NUMS-1)
                store_row_cnt <= 'd0;
            else
                store_row_cnt <= store_row_cnt + 1'b1;
        end else begin
            store_col_cnt <= store_col_cnt + 1'b1;
        end
    end
end

always @(posedge clk) begin
    if((CURRENT_STATE == LOAD_IMAGE) && bram_en_delay1)
        image[store_row_cnt][store_col_cnt] <=
            bram_data[QUANT_SIZE-1:0];
end

always @(posedge clk) begin
    if(!rstn)
        idx <= 'd0;
    else if(CURRENT_STATE != OUTPUT_IMAGE)
        idx <= 'd0;
    else if(O_data_Fire) begin
        if(idx == LINE_NUMS-1)
            idx <= 'd0;
        else
            idx <= idx + 1'b1;
    end
end

genvar col_i;
generate
    for(col_i=0; col_i<LINE_LEN; col_i=col_i+1) begin: OUTPUT_LINE
        assign DATA_LINE[col_i*QUANT_SIZE+:QUANT_SIZE] = image[idx][col_i];
    end
endgenerate

function integer clogb2(input integer bit_depth);
integer depth;
begin
    depth = bit_depth - 1;
    for(clogb2=0; depth>0; clogb2=clogb2+1)
        depth = depth >> 1;
end
endfunction

endmodule
