`timescale 1ns / 1ps

module tb_PL;

parameter DATA_WIDTH     = 32;
parameter QUANT_SIZE     = 13;
parameter LINE_LEN       = 28;
parameter LINE_NUMS      = 28;
parameter CLK_PERIOD     = 10;
parameter TIMEOUT_CYCLES = 5000000;
parameter IMAGE_FILE     = "D:/Users/hjx91/Project/FPGA/AX7020/LeNet5/LeNet5.sim/sim_1/behav/xsim/ori0.txt";

localparam IMAGE_PIXELS = LINE_LEN*LINE_NUMS;

reg                         clk;
reg                         rstn;
reg  [DATA_WIDTH-1:0]       bram_data;
wire [9:0]                  bram_addr;
wire                        bram_en;
reg                         I_data_valid;
wire                        I_data_ready;
wire [9:0]                  result_q;
wire                        O_data_valid;
reg                         O_data_ready;

reg [DATA_WIDTH-1:0] image_bram[0:IMAGE_PIXELS-1];

integer image_file;
integer image_idx;
integer read_status;
integer cycle_cnt;

PL #(
    .DATA_WIDTH(DATA_WIDTH),
    .QUANT_SIZE(QUANT_SIZE),
    .LINE_LEN(LINE_LEN),
    .LINE_NUMS(LINE_NUMS)
) dut (
    .clk(clk),
    .rstn(rstn),
    .bram_data(bram_data),
    .bram_addr(bram_addr),
    .bram_en(bram_en),
    .I_data_valid(I_data_valid),
    .I_data_ready(I_data_ready),
    .result_q(result_q),
    .O_data_valid(O_data_valid),
    .O_data_ready(O_data_ready)
);

/*
 * 100 MHz clock. The period can be changed through CLK_PERIOD without
 * changing the remaining stimulus timing.
 */
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

/*
 * Synchronous BRAM model with one clock of read latency. This is the same
 * timing assumed by bram_en_delay1 inside image_reader.
 */
always @(posedge clk) begin
    if(!rstn)
        bram_data <= {DATA_WIDTH{1'b0}};
    else if(bram_en)
        bram_data <= image_bram[bram_addr];
end

always @(posedge clk) begin
    if(!rstn)
        cycle_cnt <= 0;
    else
        cycle_cnt <= cycle_cnt + 1;
end

/*
 * Load one 28 x 28 image and issue one input transaction. Keep the final
 * output blocked first, then release it after checking that valid is held.
 */
initial begin
    rstn        = 1'b0;
    bram_data   = {DATA_WIDTH{1'b0}};
    I_data_valid = 1'b0;
    O_data_ready = 1'b0;
    cycle_cnt    = 0;

    for(image_idx=0; image_idx<IMAGE_PIXELS; image_idx=image_idx+1)
        image_bram[image_idx] = {DATA_WIDTH{1'b0}};

    image_file = $fopen(IMAGE_FILE, "r");
    if(image_file == 0) begin
        $display("ERROR: cannot open image file: %s", IMAGE_FILE);
        $stop;
    end

    for(image_idx=0; image_idx<IMAGE_PIXELS; image_idx=image_idx+1) begin
        read_status = $fscanf(image_file, "%d", image_bram[image_idx]);
        if(read_status != 1) begin
            $display("ERROR: image file contains fewer than %0d pixels; stopped at pixel %0d.",
                     IMAGE_PIXELS, image_idx);
            $fclose(image_file);
            $stop;
        end
    end
    $fclose(image_file);

    repeat(10) @(posedge clk);
    @(negedge clk);
    rstn = 1'b1;

    wait(I_data_ready == 1'b1);
    @(negedge clk);
    I_data_valid = 1'b1;
    @(negedge clk);
    I_data_valid = 1'b0;

    $display("[%0t ns] One inference request has been accepted.", $time);

    wait(O_data_valid == 1'b1);
    $display("[%0t ns] O_data_valid is high; keep O_data_ready low for 5 cycles.",
             $time);
    repeat(5) begin
        @(posedge clk);
        #1;
        if(O_data_valid != 1'b1) begin
            $display("ERROR: O_data_valid did not remain high while O_data_ready was low.");
            $stop;
        end
    end

    @(negedge clk);
    O_data_ready = 1'b1;
    $display("[%0t ns] O_data_valid stayed high; O_data_ready is now asserted.",
             $time);

    @(posedge clk);
    #1;
    $display("[%0t ns] Inference complete: result_q = %0d, cycles = %0d.",
             $time, result_q, cycle_cnt);
end

/* Prevent a stalled design from making the simulation run forever. */
initial begin
    wait(rstn == 1'b1);
    repeat(TIMEOUT_CYCLES) @(posedge clk);
    $display("ERROR: inference timed out after %0d cycles.", TIMEOUT_CYCLES);
    $stop;
end

endmodule
