// hex64_to_ascii16.v
module hex64_to_ascii16(input [63:0] x, output [127:0] s);
  genvar i; generate
    for (i=0;i<16;i=i+1) begin: nibs
      wire [3:0] h = x[63-4*i -: 4];
      hex_nibble_to_ascii conv(.h(h), .a(s[127-8*i -: 8]));
    end
  endgenerate
endmodule
