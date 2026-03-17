// tb_xtea_core.v
`timescale 1ns/1ps
module tb_xtea_core;
  reg clk=0, rst=1, start=0, enc=1;
  reg [127:0] key; reg [63:0] blk_in; wire [63:0] blk_out; wire done;
  xtea_core dut(.clk(clk), .rst(rst), .start(start), .enc(enc), .key(key), .block_in(blk_in), .block_out(blk_out), .done(done));
  always #5 clk=~clk;
  task run_vec(input [127:0] K, input [63:0] P, input [63:0] C);
    begin
      @(negedge clk); key=K; blk_in=P; enc=1; start=1; @(negedge clk); start=0; wait(done); @(negedge clk);
      if (blk_out!==C) begin $display("ENC FAIL: got %016h exp %016h", blk_out, C); $stop; end
      @(negedge clk); blk_in=C; enc=0; start=1; @(negedge clk); start=0; wait(done); @(negedge clk);
      if (blk_out!==P) begin $display("DEC FAIL: got %016h exp %016h", blk_out, P); $stop; end
    end
  endtask
  initial begin
    repeat(5) @(negedge clk); rst=0;
    // Vectors from widely used suites (see README)
    run_vec(128'h000102030405060708090A0B0C0D0E0F, 64'h4142434445464748, 64'h497df3d072612cb5);
    run_vec(128'h000102030405060708090A0B0C0D0E0F, 64'h4141414141414141, 64'he78f2d13744341d8);
    run_vec(128'h0,                                64'h4142434445464748, 64'ha0390589f8b8efa5);
    run_vec(128'h0,                                64'h4141414141414141, 64'hed23375a821a8c2d);
    $display("All XTEA tests passed.");
    $finish;
  end
endmodule
