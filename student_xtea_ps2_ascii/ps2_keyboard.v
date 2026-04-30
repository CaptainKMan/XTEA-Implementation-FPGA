// ps2_keyboard.v
// PS/2 keyboard receiver for Set-2 scan codes. Converts a useful subset to ASCII:
// - Digits '0'..'9'
// - Uppercase 'A'..'Z'
// - Space ' '
// - Punctuation: ',' '.' '-' '/'
// - Enter -> '\r' (0x0D), Backspace -> '\b' (0x08)
// Function keys mapped to private-use control bytes (0x01..0x08):
//   F1=0x01 (sel key), F2=0x02 (sel block), F3=0x03 (encrypt),
//   F4=0x04 (decrypt), F5=0x05 (toggle mode), F6=0x06 (clear)
// References for scan codes (Set-2): public tables.
//
// Receiver core based on proven textbook implementation (Yamin Li,
// "Computer Principles and Design in Verilog HDL", Wiley).
// Uses 4-stage PS2 clock synchronizer (pattern 1100 = falling edge),
// counts all 11 bits including start, validates stop bit and odd parity.

module ps2_keyboard (
  input  wire clk,          // 50 MHz
  input  wire rst,
  input  wire ps2_clk,
  input  wire ps2_dat,
  output reg  ascii_valid,
  output reg  [7:0] ascii
);

  // ---------------------------------------------------------------
  // 4-stage synchronizer on PS/2 clock; detect falling edge pattern 1100
  // ---------------------------------------------------------------
  reg [3:0] ps2c_sync;
  always @(posedge clk)
    ps2c_sync <= {ps2c_sync[2:0], ps2_clk};

  // Falling edge: two highs followed by two lows
  wire sampling = ps2c_sync[3] & ps2c_sync[2] & ~ps2c_sync[1] & ~ps2c_sync[0];

  // ---------------------------------------------------------------
  // Bit receiver: counts all 11 bits (start + 8 data + parity + stop)
  // buffer[0]   = start bit (must be 0)
  // buffer[8:1] = data byte (LSB first)
  // buffer[9]   = parity bit
  // stop bit is ps2_dat when count==10
  // ---------------------------------------------------------------
  reg [9:0] buffer;
  reg [3:0] count;
  reg       got_code;
  reg [7:0] code;

  always @(posedge clk) begin
    if (rst) begin
      count    <= 4'd0;
      got_code <= 1'b0;
    end else begin
      got_code <= 1'b0;
      if (sampling) begin
        if (count == 4'd10) begin
          // Full frame received; validate start bit, stop bit, odd parity
          if ((buffer[0] == 1'b0) &&        // start bit must be 0
              (ps2_dat   == 1'b1) &&         // stop bit must be 1
              (^buffer[9:1]      )) begin    // odd parity: XOR of data+parity = 1
            code     <= buffer[8:1];         // data byte
            got_code <= 1'b1;
          end
          count <= 4'd0;                     // reset for next frame regardless
        end else begin
          buffer[count] <= ps2_dat;          // store bit into its slot
          count         <= count + 4'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------------
  // Map Set-2 make codes to ASCII; handle break (0xF0) and
  // extended prefix (0xE0) for function keys F1-F6.
  // F-keys use private-use bytes 0x01-0x06 as control signals.
  // ---------------------------------------------------------------
  reg break_next;
  reg ext_next;    // 1 = last code was 0xE0 (extended prefix)

  always @(posedge clk) begin
    ascii_valid <= 1'b0;
    if (rst) begin
      break_next <= 1'b0;
      ext_next   <= 1'b0;
    end else if (got_code) begin
      if (code == 8'hF0) begin
        break_next <= 1'b1;           // next code is a break — ignore it
      end else if (code == 8'hE0) begin
        ext_next <= 1'b1;             // extended prefix — next code is E0-prefixed
      end else if (break_next) begin
        break_next <= 1'b0;           // discard the break make-code
        ext_next   <= 1'b0;
      end else if (ext_next) begin
        // Extended (E0-prefixed) make codes — only F-keys we care about land here
        ext_next <= 1'b0;
        // F1-F12 extended scan codes (Set 2):
        // NOTE: F1..F4 are NOT E0-prefixed in Set2; they are single-byte.
        // Only F5..F12 etc are single-byte too. All F-keys are single-byte in Set2.
        // E0-prefix codes are cursor keys, numpad, etc. We ignore them here.
        ; // ignore all extended codes (cursor keys, ins, del, etc.)
      end else begin
        // Single-byte make codes
        case (code)
          // ---- Function keys (Set-2 single-byte, no E0 prefix) ----
          // F1=0x05  F2=0x06  F3=0x04  F4=0x0C
          // F5=0x03  F6=0x0B  F7=0x83  F8=0x0A
          8'h05: begin ascii <= 8'h01; ascii_valid <= 1'b1; end // F1 = select KEY field
          8'h06: begin ascii <= 8'h02; ascii_valid <= 1'b1; end // F2 = select BLOCK field
          8'h04: begin ascii <= 8'h03; ascii_valid <= 1'b1; end // F3 = Encrypt
          8'h0C: begin ascii <= 8'h04; ascii_valid <= 1'b1; end // F4 = Decrypt
          8'h03: begin ascii <= 8'h05; ascii_valid <= 1'b1; end // F5 = toggle ASCII/HEX
          8'h0B: begin ascii <= 8'h06; ascii_valid <= 1'b1; end // F6 = Clear
          // ---- Digits ----
          8'h45: begin ascii <= "0"; ascii_valid <= 1'b1; end
          8'h16: begin ascii <= "1"; ascii_valid <= 1'b1; end
          8'h1E: begin ascii <= "2"; ascii_valid <= 1'b1; end
          8'h26: begin ascii <= "3"; ascii_valid <= 1'b1; end
          8'h25: begin ascii <= "4"; ascii_valid <= 1'b1; end
          8'h2E: begin ascii <= "5"; ascii_valid <= 1'b1; end
          8'h36: begin ascii <= "6"; ascii_valid <= 1'b1; end
          8'h3D: begin ascii <= "7"; ascii_valid <= 1'b1; end
          8'h3E: begin ascii <= "8"; ascii_valid <= 1'b1; end
          8'h46: begin ascii <= "9"; ascii_valid <= 1'b1; end
          // ---- Letters A..Z ----
          8'h1C: begin ascii <= "A"; ascii_valid <= 1'b1; end
          8'h32: begin ascii <= "B"; ascii_valid <= 1'b1; end
          8'h21: begin ascii <= "C"; ascii_valid <= 1'b1; end
          8'h23: begin ascii <= "D"; ascii_valid <= 1'b1; end
          8'h24: begin ascii <= "E"; ascii_valid <= 1'b1; end
          8'h2B: begin ascii <= "F"; ascii_valid <= 1'b1; end
          8'h34: begin ascii <= "G"; ascii_valid <= 1'b1; end
          8'h33: begin ascii <= "H"; ascii_valid <= 1'b1; end
          8'h43: begin ascii <= "I"; ascii_valid <= 1'b1; end
          8'h3B: begin ascii <= "J"; ascii_valid <= 1'b1; end
          8'h42: begin ascii <= "K"; ascii_valid <= 1'b1; end
          8'h4B: begin ascii <= "L"; ascii_valid <= 1'b1; end
          8'h3A: begin ascii <= "M"; ascii_valid <= 1'b1; end
          8'h31: begin ascii <= "N"; ascii_valid <= 1'b1; end
          8'h44: begin ascii <= "O"; ascii_valid <= 1'b1; end
          8'h4D: begin ascii <= "P"; ascii_valid <= 1'b1; end
          8'h15: begin ascii <= "Q"; ascii_valid <= 1'b1; end
          8'h2D: begin ascii <= "R"; ascii_valid <= 1'b1; end
          8'h1B: begin ascii <= "S"; ascii_valid <= 1'b1; end
          8'h2C: begin ascii <= "T"; ascii_valid <= 1'b1; end
          8'h3C: begin ascii <= "U"; ascii_valid <= 1'b1; end
          8'h2A: begin ascii <= "V"; ascii_valid <= 1'b1; end
          8'h1D: begin ascii <= "W"; ascii_valid <= 1'b1; end
          8'h22: begin ascii <= "X"; ascii_valid <= 1'b1; end
          8'h35: begin ascii <= "Y"; ascii_valid <= 1'b1; end
          8'h1A: begin ascii <= "Z"; ascii_valid <= 1'b1; end
          // ---- Space and punctuation ----
          8'h29: begin ascii <= 8'h20; ascii_valid <= 1'b1; end // space
          8'h41: begin ascii <= ",";   ascii_valid <= 1'b1; end
          8'h49: begin ascii <= ".";   ascii_valid <= 1'b1; end
          8'h4E: begin ascii <= "-";   ascii_valid <= 1'b1; end
          8'h4A: begin ascii <= "/";   ascii_valid <= 1'b1; end
          // ---- Control ----
          8'h5A: begin ascii <= 8'h0D; ascii_valid <= 1'b1; end // Enter
          8'h66: begin ascii <= 8'h08; ascii_valid <= 1'b1; end // Backspace
          default: ;
        endcase
      end
    end
  end

endmodule