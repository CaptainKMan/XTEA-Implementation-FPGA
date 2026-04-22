// ps2_keyboard.v
// PS/2 keyboard receiver for Set-2 scan codes. Converts a useful subset to ASCII:
// - Digits '0'..'9'
// - Uppercase 'A'..'Z'
// - Space ' '
// - Punctuation: ',' '.' '-' '/'
// - Enter -> '\r' (0x0D), Backspace -> '\b' (0x08)
// Also passes 'E','D','K','P','C','M','H','A','T' for UI control.
// References for scan codes (Set-2): public tables.

module ps2_keyboard (
  input  wire clk,          // 50 MHz
  input  wire rst,
  input  wire ps2_clk,
  input  wire ps2_dat,
  output reg  ascii_valid,
  output reg  [7:0] ascii
);

  // Synchronize PS2 clock and detect falling edge
  reg [2:0] ps2c_sync;
  always @(posedge clk) ps2c_sync <= {ps2c_sync[1:0], ps2_clk};
  wire fall = (ps2c_sync[2:1]==2'b10);

  reg [10:0] shifter;
  reg [3:0]  bitcnt;
  reg        in_frame;
  reg        got_code;
  reg [7:0]  code;
  reg        break_next;

  always @(posedge clk) begin
    if (rst) begin
      in_frame <= 1'b0; bitcnt<=0; got_code<=1'b0; code<=8'd0;
    end else begin
      got_code <= 1'b0;
      if (fall) begin
        if (!in_frame) begin
          in_frame <= 1'b1; bitcnt<=0;
        end else begin
          shifter <= {ps2_dat, shifter[10:1]};
          bitcnt  <= bitcnt + 1'b1;
          if (bitcnt==4'd10) begin
            in_frame <= 1'b0; code <= shifter[8:1]; got_code<=1'b1;
          end
        end
      end
    end
  end

  // Map Set-2 make codes to ASCII (subset)
  always @(posedge clk) begin
    ascii_valid <= 1'b0;
    if (rst) begin
      break_next <= 1'b0;
    end else if (got_code) begin
      if (code==8'hF0) begin
        break_next <= 1'b1; // ignore break
      end else if (code==8'hE0) begin
        // ignore extended prefix
      end else if (break_next) begin
        break_next <= 1'b0;
      end else begin
        case (code)
          // Digits
          8'h45: begin ascii<="0"; ascii_valid<=1'b1; end
          8'h16: begin ascii<="1"; ascii_valid<=1'b1; end
          8'h1E: begin ascii<="2"; ascii_valid<=1'b1; end
          8'h26: begin ascii<="3"; ascii_valid<=1'b1; end
          8'h25: begin ascii<="4"; ascii_valid<=1'b1; end
          8'h2E: begin ascii<="5"; ascii_valid<=1'b1; end
          8'h36: begin ascii<="6"; ascii_valid<=1'b1; end
          8'h3D: begin ascii<="7"; ascii_valid<=1'b1; end
          8'h3E: begin ascii<="8"; ascii_valid<=1'b1; end
          8'h46: begin ascii<="9"; ascii_valid<=1'b1; end
          // Letters A..Z (uppercase)
          8'h1C: begin ascii<="A"; ascii_valid<=1'b1; end
          8'h32: begin ascii<="B"; ascii_valid<=1'b1; end
          8'h21: begin ascii<="C"; ascii_valid<=1'b1; end
          8'h23: begin ascii<="D"; ascii_valid<=1'b1; end
          8'h24: begin ascii<="E"; ascii_valid<=1'b1; end
          8'h2B: begin ascii<="F"; ascii_valid<=1'b1; end
          8'h34: begin ascii<="G"; ascii_valid<=1'b1; end
          8'h33: begin ascii<="H"; ascii_valid<=1'b1; end
          8'h43: begin ascii<="I"; ascii_valid<=1'b1; end
          8'h3B: begin ascii<="J"; ascii_valid<=1'b1; end
          8'h42: begin ascii<="K"; ascii_valid<=1'b1; end
          8'h4B: begin ascii<="L"; ascii_valid<=1'b1; end
          8'h3A: begin ascii<="M"; ascii_valid<=1'b1; end
          8'h31: begin ascii<="N"; ascii_valid<=1'b1; end
          8'h44: begin ascii<="O"; ascii_valid<=1'b1; end
          8'h4D: begin ascii<="P"; ascii_valid<=1'b1; end
          8'h15: begin ascii<="Q"; ascii_valid<=1'b1; end
          8'h2D: begin ascii<="R"; ascii_valid<=1'b1; end
          8'h1B: begin ascii<="S"; ascii_valid<=1'b1; end
          8'h2C: begin ascii<="T"; ascii_valid<=1'b1; end
          8'h3C: begin ascii<="U"; ascii_valid<=1'b1; end
          8'h2A: begin ascii<="V"; ascii_valid<=1'b1; end
          8'h1D: begin ascii<="W"; ascii_valid<=1'b1; end
          8'h22: begin ascii<="X"; ascii_valid<=1'b1; end
          8'h35: begin ascii<="Y"; ascii_valid<=1'b1; end
          8'h1A: begin ascii<="Z"; ascii_valid<=1'b1; end
          // Space and punctuation used
          8'h29: begin ascii<=8'h20; ascii_valid<=1'b1; end // space
          8'h41: begin ascii<=","; ascii_valid<=1'b1; end
          8'h49: begin ascii<="."; ascii_valid<=1'b1; end
          8'h4E: begin ascii<="-"; ascii_valid<=1'b1; end
          8'h4A: begin ascii<="/"; ascii_valid<=1'b1; end
          // Control
          8'h5A: begin ascii<=8'h0D; ascii_valid<=1'b1; end // Enter
          8'h66: begin ascii<=8'h08; ascii_valid<=1'b1; end // Backspace
          default: ;
        endcase
      end
    end
  end
endmodule