// hex_ascii.v
module hex_nibble_to_ascii(input [3:0] h, output [7:0] a);
  assign a = (h<4'd10) ? (8'h30 + h[3:0]) : (8'h41 + (h[3:0]-4'd10));
endmodule

module ascii_hex_nibble(input [7:0] a, output reg [3:0] h, output reg valid);
  always @* begin
    valid = 1'b1;
    if (a>="0" && a<="9") h = a - "0";
    else if (a>="A" && a<="F") h = 4'd10 + (a-"A");
    else if (a>="a" && a<="f") h = 4'd10 + (a-"a");
    else valid = 1'b0;
  end
endmodule
