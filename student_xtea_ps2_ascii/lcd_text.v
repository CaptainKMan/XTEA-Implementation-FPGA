// lcd_text.v
// Drive the DE2-115 16x2 LCD in 8-bit mode; continually refresh two 16-char lines.
// Uses a 50us tick so every state transition naturally satisfies HD44780 timing.
// Implements the mandatory triple Function Set power-on sequence per the datasheet.

module lcd_text (
  input  wire         clk,      // 50 MHz
  input  wire         rst,
  input  wire [127:0] line1,    // 16 ASCII chars, [127:120]=char0 .. [7:0]=char15
  input  wire [127:0] line2,
  output reg          LCD_ON,
  output reg          LCD_BLON,
  output reg          LCD_EN,
  output reg          LCD_RS,
  output reg          LCD_RW,
  output reg  [7:0]   LCD_DATA
);

  // 50 us tick from 50 MHz: count 0..2499
  reg [11:0] div;
  wire tick = (div == 12'd2499);
  always @(posedge clk) begin
    if (rst) div <= 12'd0;
    else     div <= tick ? 12'd0 : div + 1'b1;
  end

  localparam
    S_INIT_WAIT  = 4'd0,   // 20ms power-on wait (400 ticks)
    S_INIT_FS1   = 4'd1,   // Function Set #1
    S_INIT_FS1_W = 4'd2,   // wait >4.1ms (82 ticks)
    S_INIT_FS2   = 4'd3,   // Function Set #2
    S_INIT_FS2_W = 4'd4,   // wait >100us (2 ticks)
    S_INIT_FS3   = 4'd5,   // Function Set #3 (sets 2-line, 5x8 for real)
    S_INIT_ON    = 4'd6,   // Display ON (cursor off, blink off)
    S_INIT_CLR   = 4'd7,   // Clear Display
    S_INIT_CLR_W = 4'd8,   // wait >1.52ms (40 ticks at 50us each = 2ms)
    S_INIT_EMS   = 4'd9,   // Entry Mode Set
    S_IDLE       = 4'd10,
    S_SET_L1     = 4'd11,
    S_PUT_L1     = 4'd12,
    S_SET_L2     = 4'd13,
    S_PUT_L2     = 4'd14;

  reg [3:0]  st;
  reg [8:0]  cnt;    // up to 511 ticks for waits
  reg [4:0]  idx;

  task send_cmd(input [7:0] v);
    begin LCD_RS<=1'b0; LCD_RW<=1'b0; LCD_DATA<=v; LCD_EN<=1'b1; end
  endtask
  task send_dat(input [7:0] v);
    begin LCD_RS<=1'b1; LCD_RW<=1'b0; LCD_DATA<=v; LCD_EN<=1'b1; end
  endtask

  wire [7:0] l1_char = line1[127 - 8*idx -: 8];
  wire [7:0] l2_char = line2[127 - 8*idx -: 8];

  always @(posedge clk) begin
    if (rst) begin
      st<=S_INIT_WAIT; cnt<=0; idx<=0;
      LCD_ON<=1'b1; LCD_BLON<=1'b1; LCD_EN<=1'b0;
      LCD_RS<=1'b0; LCD_RW<=1'b0; LCD_DATA<=8'h00;
    end else if (tick) begin
      LCD_EN <= 1'b0; // pulled low each tick; send_cmd/dat overrides below

      case (st)

        // Wait 20ms (400 x 50us) for LCD power-on reset to complete
        S_INIT_WAIT:
          begin
            cnt <= cnt + 1'b1;
            if (cnt == 9'd399) begin cnt<=0; st<=S_INIT_FS1; end
          end

        // Function Set #1: 8-bit mode. HD44780 may still be resetting internally.
        S_INIT_FS1:   begin send_cmd(8'h38); cnt<=0; st<=S_INIT_FS1_W; end
        // Wait >4.1ms = 82 ticks x 50us
        S_INIT_FS1_W: begin cnt<=cnt+1'b1; if (cnt==9'd81) begin cnt<=0; st<=S_INIT_FS2; end end

        // Function Set #2: 8-bit mode again.
        S_INIT_FS2:   begin send_cmd(8'h38); cnt<=0; st<=S_INIT_FS2_W; end
        // Wait >100us = 2 ticks x 50us
        S_INIT_FS2_W: begin cnt<=cnt+1'b1; if (cnt==9'd1) begin cnt<=0; st<=S_INIT_FS3; end end

        // Function Set #3: now sets actual operating parameters (8-bit, 2-line, 5x8).
        // From here the HD44780 is fully awake; each subsequent command waits one tick (50us).
        S_INIT_FS3:  begin send_cmd(8'h38); st<=S_INIT_ON; end

        // Display ON: display on, cursor off, blink off
        S_INIT_ON:   begin send_cmd(8'h0C); st<=S_INIT_CLR; end

        // Clear Display: fills DDRAM with spaces, resets cursor. Takes up to 1.52ms.
        S_INIT_CLR:  begin send_cmd(8'h01); cnt<=0; st<=S_INIT_CLR_W; end
        // Wait 2ms = 40 ticks x 50us
        S_INIT_CLR_W: begin cnt<=cnt+1'b1; if (cnt==9'd39) begin cnt<=0; st<=S_INIT_EMS; end end

        // Entry Mode Set: cursor moves right, no display shift
        S_INIT_EMS:  begin send_cmd(8'h06); st<=S_IDLE; end

        // --- Continuous refresh loop ---
        S_IDLE:   st <= S_SET_L1;

        // Set cursor to line 1, position 0 (DDRAM address 0x00)
        S_SET_L1: begin send_cmd(8'h80); idx<=0; st<=S_PUT_L1; end

        // Write 16 characters to line 1. Each write waits one tick (50us) before the next.
        S_PUT_L1:
          begin
            send_dat(l1_char);
            idx <= idx + 1'b1;
            if (idx == 5'd15) st <= S_SET_L2;
          end

        // Set cursor to line 2, position 0 (DDRAM address 0x40)
        S_SET_L2: begin send_cmd(8'hC0); idx<=0; st<=S_PUT_L2; end

        // Write 16 characters to line 2.
        S_PUT_L2:
          begin
            send_dat(l2_char);
            idx <= idx + 1'b1;
            if (idx == 5'd15) st <= S_IDLE;
          end

        default: st <= S_INIT_WAIT;
      endcase
    end
  end
endmodule