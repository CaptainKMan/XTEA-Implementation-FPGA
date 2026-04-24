// top_xtea_ps2_lcd.v
// Integrates PS/2 keyboard input, ASCII/HEX plaintext entry, XTEA core, and LCD output.

module top_xtea_ps2_lcd (
  input  wire        CLOCK_50,
  input  wire        RESET_N,
  input  wire        PS2_KBCLK,
  input  wire        PS2_KBDAT,
  output wire        LCD_ON,
  output wire        LCD_BLON,
  output wire        LCD_EN,
  output wire        LCD_RS,
  output wire        LCD_RW,
  output wire [7:0]  LCD_DATA
);
  wire rst = ~RESET_N;

  // Keyboard
  wire k_valid; wire [7:0] k_ascii;
  ps2_keyboard kbd(.clk(CLOCK_50), .rst(rst), .ps2_clk(PS2_KBCLK), .ps2_dat(PS2_KBDAT), .ascii_valid(k_valid), .ascii(k_ascii));

  // Entry buffers
  reg [127:0] key; reg [63:0] block;
  reg [5:0]   key_count; // nibbles 0..32
  reg [4:0]   blk_hex_count; // hex nibbles 0..16
  reg [3:0]   blk_ascii_count; // ascii bytes 0..8
  reg         sel_key;     // selecting key vs block fields
  reg         ascii_mode;  // 1 = ASCII plaintext entry (8 chars), 0 = HEX (16 nibbles)

  // UI triggers
  reg do_enc, do_dec;

  // ASCII->nibble for hex entry
  wire [3:0] nib; wire nib_ok;
  ascii_hex_nibble ah(.a(k_ascii), .h(nib), .valid(nib_ok));

  // UI handling
  always @(posedge CLOCK_50) begin
    if (rst) begin
      key<=0; block<=0; key_count<=0; blk_hex_count<=0; blk_ascii_count<=0; sel_key<=1'b0; ascii_mode<=1'b0; do_enc<=1'b0; do_dec<=1'b0;
    end else if (k_valid) begin
      do_enc<=1'b0; do_dec<=1'b0; // pulse
      case (k_ascii)
        // Field selection
        "K": sel_key<=1'b1;           // key field (hex-only)
        "P": sel_key<=1'b0;           // block field
        "M": ascii_mode<=~ascii_mode; // toggle ASCII/HEX for block
        "A": ascii_mode<=1'b1;        // force ASCII mode
        "H": ascii_mode<=1'b0;        // force HEX mode

        // Actions
        "E": if (key_count==6'd32 && ((ascii_mode && blk_ascii_count==4'd8) || (!ascii_mode && blk_hex_count==5'd16))) do_enc<=1'b1;
        "D": if (key_count==6'd32 && ((ascii_mode && blk_ascii_count==4'd8) || (!ascii_mode && blk_hex_count==5'd16))) do_dec<=1'b1;
        "C": begin key<=0; key_count<=0; block<=0; blk_hex_count<=0; blk_ascii_count<=0; end
        8'h08: begin // Backspace
                 if (sel_key && key_count>0) begin
                   key_count<=key_count-1'b1; key<={key[127-4:0],4'h0};
                 end else if (!sel_key) begin
                   if (ascii_mode && blk_ascii_count>0) begin
                     blk_ascii_count<=blk_ascii_count-1'b1; block<={block[55:0],8'h00};
                   end else if (!ascii_mode && blk_hex_count>0) begin
                     blk_hex_count<=blk_hex_count-1'b1; block<={block[59:0],4'h0};
                   end
                 end
               end
        8'h0D: ; // Enter ignored (optional confirm)
        default: begin
          if (sel_key) begin
            if (nib_ok && key_count<6'd32) begin key<={key[123:0], nib}; key_count<=key_count+1'b1; end
          end else begin
            if (ascii_mode) begin
              if (blk_ascii_count<4'd8) begin block<={block[55:0], k_ascii}; blk_ascii_count<=blk_ascii_count+1'b1; end
            end else begin
              if (nib_ok && blk_hex_count<5'd16) begin block<={block[59:0], nib}; blk_hex_count<=blk_hex_count+1'b1; end
            end
          end
        end
      endcase
    end else begin
      do_enc<=1'b0; do_dec<=1'b0; if (done) block<=result;
    end
  end

  // XTEA core
  reg start; reg enc; wire done; wire [63:0] result;
  xtea_core core(.clk(CLOCK_50), .rst(rst), .start(start), .enc(enc), .key(key), .block_in(block), .block_out(result), .done(done));
  always @(posedge CLOCK_50) begin
    if (rst) begin start<=1'b0; enc<=1'b1; end
    else begin
      start<=1'b0;
      if (do_enc) begin enc<=1'b1; start<=1'b1; end else if (do_dec) begin enc<=1'b0; start<=1'b1; end
    end
  end

  // LCD formatting
  reg [127:0] l1, l2;
  wire [127:0] hex_line; hex64_to_ascii16 fmt(.x(block), .s(hex_line));

  function [7:0] d2a; input [3:0] d; begin d2a = 8'h30 + d; end endfunction

  always @(posedge CLOCK_50) begin
    if (rst) begin
      l1 <= "XTEA READY     ";
      l2 <= "0000000000000000";
    end else begin
      if (sel_key) begin
        l1 <= {"KEY ", d2a(key_count/10), d2a(key_count%10), "/32", (ascii_mode?" A":" H"), "         "};
      end else begin
        if (ascii_mode)
          l1 <= {"ASCII ", d2a(blk_ascii_count/10), d2a(blk_ascii_count%10), "/8 ", "           "};
        else
          l1 <= {"HEX ", d2a(blk_hex_count/10), d2a(blk_hex_count%10), "/16", "           "};
      end
      l2 <= hex_line; // show block in hex on second line
    end
  end

  lcd_text lcd(.clk(CLOCK_50), .rst(rst), .line1("HELLO WORLD     "), .line2("1234567890ABCDEF"),
    .LCD_ON(LCD_ON), .LCD_BLON(LCD_BLON), .LCD_EN(LCD_EN), .LCD_RS(LCD_RS), .LCD_RW(LCD_RW), .LCD_DATA(LCD_DATA));
endmodule