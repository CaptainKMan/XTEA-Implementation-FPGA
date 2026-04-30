// top_xtea_ps2_lcd.v
// Integrates PS/2 keyboard input, ASCII/HEX plaintext entry, XTEA core, and LCD output.
//
// Input mode is toggled by KEY[3] (active-low pushbutton):
//   PS/2 mode  — keyboard drives all entry as before.
//   Switch mode — SW[3:0] sets hex nibble; buttons confirm/control entry:
//                   KEY[0] = enter nibble / confirm action
//                   KEY[1] = toggle key field vs block field
//                   KEY[2] = encrypt (SW[4]=0) or decrypt (SW[4]=1)
//                   SW[17] = 1 clears all fields (hold, then release KEY[0])
//                 Line 1 shows current nibble on SW[3:0] as preview.

module top_xtea_ps2_lcd (
  input  wire        CLOCK_50,
  input  wire        RESET_N,
  input  wire        PS2_KBCLK,
  input  wire        PS2_KBDAT,
  input  wire [17:0] SW,       // SW[3:0]=nibble, SW[4]=dec mode, SW[17]=clear
  input  wire [3:0]  KEY,      // active-low: KEY[3]=mode toggle, KEY[2]=enc/dec,
                               //             KEY[1]=field sel, KEY[0]=enter nibble
  output wire        LCD_ON,
  output wire        LCD_EN,
  output wire        LCD_RS,
  output wire        LCD_RW,
  output wire [7:0]  LCD_DATA
);

  // ------------------------------------------------------------------
  // Power-on reset: hold rst high for ~10ms then release
  // ------------------------------------------------------------------
  reg [19:0] por_cnt = 20'd0;
  wire rst = ~por_cnt[19];
  always @(posedge CLOCK_50)
    if (!por_cnt[19]) por_cnt <= por_cnt + 1'b1;

  // ------------------------------------------------------------------
  // PS/2 keyboard
  // ------------------------------------------------------------------
  wire k_valid; wire [7:0] k_ascii;
  ps2_keyboard kbd(.clk(CLOCK_50), .rst(rst), .ps2_clk(PS2_KBCLK), .ps2_dat(PS2_KBDAT),
                   .ascii_valid(k_valid), .ascii(k_ascii));

  // ASCII->nibble for PS/2 hex entry
  wire [3:0] nib; wire nib_ok;
  ascii_hex_nibble ah(.a(k_ascii), .h(nib), .valid(nib_ok));

  // ------------------------------------------------------------------
  // Button edge detection (all KEY inputs are active-low)
  // Produces a single-cycle pulse on the rising edge of the debounced press.
  // ------------------------------------------------------------------
  reg [3:0] key_r0, key_r1, key_r2; // two-stage sync + previous
  always @(posedge CLOCK_50) begin
    key_r0 <= ~KEY;          // invert so 1=pressed
    key_r1 <= key_r0;
    key_r2 <= key_r1;
  end
  // rising edge pulse: was 0 last cycle, is 1 this cycle (after 2-stage sync)
  wire [3:0] key_press = key_r1 & ~key_r2;

  // Convenience aliases
  wire btn_enter  = key_press[0]; // KEY[0]: enter nibble
  wire btn_field  = key_press[1]; // KEY[1]: toggle key/block field
  wire btn_encdec = key_press[2]; // KEY[2]: trigger encrypt or decrypt
  wire btn_mode   = key_press[3]; // KEY[3]: toggle PS/2 vs switch input mode

  // ------------------------------------------------------------------
  // Input mode: 0 = PS/2, 1 = switch
  // ------------------------------------------------------------------
  reg sw_mode; // 0 = PS/2 mode, 1 = switch mode
  always @(posedge CLOCK_50) begin
    if (rst)         sw_mode <= 1'b0;
    else if (btn_mode) sw_mode <= ~sw_mode;
  end

  // ------------------------------------------------------------------
  // Entry buffers (shared between both input paths)
  // ------------------------------------------------------------------
  reg [127:0] key_buf; reg [63:0] block;
  reg [5:0]   key_count;       // nibbles entered into key field 0..32
  reg [4:0]   blk_hex_count;   // hex nibbles entered into block 0..16
  reg [3:0]   blk_ascii_count; // ascii chars entered into block 0..8
  reg         sel_key;         // 1 = editing key field, 0 = editing block
  reg         ascii_mode;      // 1 = ASCII block entry, 0 = HEX block entry
  reg         do_enc, do_dec;

  // ------------------------------------------------------------------
  // PS/2 input path (identical to original logic)
  // ------------------------------------------------------------------
  always @(posedge CLOCK_50) begin
    if (rst) begin
      key_buf<=0; block<=0; key_count<=0; blk_hex_count<=0; blk_ascii_count<=0;
      sel_key<=1'b0; ascii_mode<=1'b0; do_enc<=1'b0; do_dec<=1'b0;
    end else if (!sw_mode && k_valid) begin
      // PS/2 mode: handle keyboard ASCII
      do_enc<=1'b0; do_dec<=1'b0;
      case (k_ascii)
        8'h01: sel_key<=1'b1;           // F1 = select KEY field
        8'h02: sel_key<=1'b0;           // F2 = select BLOCK field
        8'h05: ascii_mode<=~ascii_mode; // F5 = toggle ASCII/HEX
        
        
        8'h03: if (key_count==6'd32 && ((ascii_mode && blk_ascii_count==4'd8) || // F3 = Encrypt
                 (!ascii_mode && blk_hex_count==5'd16))) do_enc<=1'b1;
        8'h04: if (key_count==6'd32 && ((ascii_mode && blk_ascii_count==4'd8) || // F4 = Decrypt
                 (!ascii_mode && blk_hex_count==5'd16))) do_dec<=1'b1;
        8'h06: begin // F6 = Clear
                 key_buf<=0; key_count<=0; block<=0; blk_hex_count<=0; blk_ascii_count<=0;
               end
        8'h08: begin // Backspace
          if (sel_key && key_count>0) begin
            key_count<=key_count-1'b1; key_buf<={key_buf[123:0],4'h0};
          end else if (!sel_key) begin
            if (ascii_mode && blk_ascii_count>0) begin
              blk_ascii_count<=blk_ascii_count-1'b1; block<={block[55:0],8'h00};
            end else if (!ascii_mode && blk_hex_count>0) begin
              blk_hex_count<=blk_hex_count-1'b1; block<={block[59:0],4'h0};
            end
          end
        end
        8'h0D: ; // Enter ignored
        default: begin
          if (sel_key) begin
            if (nib_ok && key_count<6'd32) begin
              key_buf<={key_buf[123:0], nib}; key_count<=key_count+1'b1;
            end
          end else begin
            if (ascii_mode) begin
              if (blk_ascii_count<4'd8) begin
                block<={block[55:0], k_ascii}; blk_ascii_count<=blk_ascii_count+1'b1;
              end
            end else begin
              if (nib_ok && blk_hex_count<5'd16) begin
                block<={block[59:0], nib}; blk_hex_count<=blk_hex_count+1'b1;
              end
            end
          end
        end
      endcase
    end else if (sw_mode) begin
      // Switch mode: buttons drive entry
      do_enc<=1'b0; do_dec<=1'b0;

      if (SW[17] && btn_enter) begin
        // SW[17] held + KEY[0] = clear all fields
        key_buf<=0; key_count<=0; block<=0; blk_hex_count<=0; blk_ascii_count<=0;

      end else if (btn_field) begin
        // KEY[1] toggles key vs block field; also clears ascii_mode in key field
        sel_key <= ~sel_key;

      end else if (btn_enter && !SW[17]) begin
        // KEY[0] enters the nibble on SW[3:0] into the selected field
        if (sel_key) begin
          if (key_count < 6'd32) begin
            key_buf  <= {key_buf[123:0], SW[3:0]};
            key_count <= key_count + 1'b1;
          end
        end else begin
          // block field is always HEX in switch mode
          if (blk_hex_count < 5'd16) begin
            block        <= {block[59:0], SW[3:0]};
            blk_hex_count <= blk_hex_count + 1'b1;
          end
        end

      end else if (btn_encdec) begin
        // KEY[2] triggers encrypt (SW[4]=0) or decrypt (SW[4]=1)
        if (key_count==6'd32 && blk_hex_count==5'd16) begin
          if (SW[4]) do_dec<=1'b1;
          else       do_enc<=1'b1;
        end
      end

    end else begin
      // Neither input active this cycle: clear one-shot triggers, capture result
      do_enc<=1'b0; do_dec<=1'b0;
      if (done) block<=result;
    end
  end

  // ------------------------------------------------------------------
  // XTEA core
  // ------------------------------------------------------------------
  reg start; reg enc; wire done; wire [63:0] result;
  xtea_core core(.clk(CLOCK_50), .rst(rst), .start(start), .enc(enc),
                 .key(key_buf), .block_in(block), .block_out(result), .done(done));
  always @(posedge CLOCK_50) begin
    if (rst) begin start<=1'b0; enc<=1'b1; end
    else begin
      start<=1'b0;
      if (do_enc) begin enc<=1'b1; start<=1'b1; end
      else if (do_dec) begin enc<=1'b0; start<=1'b1; end
    end
  end

  // ------------------------------------------------------------------
  // LCD formatting — each concat must total exactly 16 chars (128 bits).
  // Verilog truncates from the LEFT if the concat is too wide.
  // In switch mode line 1 appends the current nibble preview and SW mode tag.
  // ------------------------------------------------------------------
  reg [127:0] l1, l2;
  wire [127:0] hex_line; hex64_to_ascii16 fmt(.x(block), .s(hex_line));

  function [7:0] d2a; input [3:0] d; begin d2a = 8'h30 + d; end endfunction
  // hex nibble to ASCII for the switch preview character
  function [7:0] nib2a;
    input [3:0] n;
    begin nib2a = (n < 4'd10) ? (8'h30 + n) : (8'h41 + n - 4'd10); end
  endfunction

  always @(posedge CLOCK_50) begin
    if (rst) begin
      l1 <= "XTEA READY      "; // 16 chars exactly
      l2 <= "0000000000000000"; // 16 chars exactly
    end else if (sw_mode) begin
      // Switch mode line 1: field tag + count + nibble preview + "SW" marker
      // Format: "K"/"B" + count(2) + "/" + max(2) + " >" + nibble_preview + " SW  " = 16
      if (sel_key)
        // "KEY " (4) + nn (2) + "/32 >" (5) + nibble (1) + " SW" (3) + " " (1) = 16
        l1 <= {"KEY ", d2a(key_count/10), d2a(key_count%10), "/32 >",
               nib2a(SW[3:0]), " SW "};
      else
        // "BLK " (4) + nn (2) + "/16 >" (5) + nibble (1) + " SW" (3) + " " (1) = 16
        l1 <= {"BLK ", d2a(blk_hex_count/10), d2a(blk_hex_count%10), "/16 >",
               nib2a(SW[3:0]), " SW "};
      l2 <= hex_line;
    end else begin
      // PS/2 mode line 1
      if (sel_key)
        // "KEY " (4) + digit (1) + digit (1) + "/32" (3) + " A"/" H" (2) + "     " (5) = 16
        l1 <= {"KEY ", d2a(key_count/10), d2a(key_count%10), "/32",
               (ascii_mode?" A":" H"), "     "};
      else begin
        if (ascii_mode)
          // "ASCII " (6) + digit (1) + digit (1) + "/8 " (3) + "     " (5) = 16
          l1 <= {"ASCII ", d2a(blk_ascii_count/10), d2a(blk_ascii_count%10), "/8 ", "     "};
        else
          // "HEX " (4) + digit (1) + digit (1) + "/16" (3) + "       " (7) = 16
          l1 <= {"HEX ", d2a(blk_hex_count/10), d2a(blk_hex_count%10), "/16", "       "};
      end
      l2 <= hex_line;
    end
  end

  lcd_text lcd(.clk(CLOCK_50), .rst(rst), .line1(l1), .line2(l2),
    .LCD_ON(LCD_ON), .LCD_EN(LCD_EN), .LCD_RS(LCD_RS), .LCD_RW(LCD_RW), .LCD_DATA(LCD_DATA));

endmodule