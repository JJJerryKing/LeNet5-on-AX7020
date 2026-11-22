
`timescale 1 ns / 1 ps

  module resize_and_gray_mkbM_DSP48_5(a, b, p);
input signed [20 - 1 : 0] a; // synthesis attribute keep a "true"
input [8 - 1 : 0] b; // synthesis attribute keep b "true"
output signed [28 - 1 : 0] p; // synthesis attribute keep p "true"

assign p = $signed (a) * $signed ({1'b0, b});

endmodule

`timescale 1 ns / 1 ps
module resize_and_gray_mkbM(
    din0,
    din1,
    dout);

parameter ID = 32'd1;
parameter NUM_STAGE = 32'd1;
parameter din0_WIDTH = 32'd1;
parameter din1_WIDTH = 32'd1;
parameter dout_WIDTH = 32'd1;
input[din0_WIDTH - 1:0] din0;
input[din1_WIDTH - 1:0] din1;
output[dout_WIDTH - 1:0] dout;



resize_and_gray_mkbM_DSP48_5 resize_and_gray_mkbM_DSP48_5_U(
    .a( din0 ),
    .b( din1 ),
    .p( dout ));

endmodule

