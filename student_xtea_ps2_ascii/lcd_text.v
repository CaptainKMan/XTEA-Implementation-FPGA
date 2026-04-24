// lcd_text.v
// HD44780-compatible 16x2 LCD controller for the DE2-115.
// 8-bit parallel interface; LCD_RW is tied low (write-only).
// Sends the HD44780 initialization sequence on power-up, then
// continuously refreshes both lines from the line1 / line2 inputs.

module lcd_text (
  input  wire         clk,       // 50 MHz system clock
  input  wire         rst,       // synchronous active-high reset
  input  wire [127:0] line1,     // 16 ASCII characters, char 0 at bits [127:120]
  input  wire [127:0] line2,     // 16 ASCII characters, char 0 at bits [127:120]
  output reg          LCD_ON,    // LCD power enable  (active HIGH on this board)
  output reg          LCD_BLON,  // backlight enable  (active high)
  output reg          LCD_EN,    // enable strobe
  output reg          LCD_RS,    // 0 = command, 1 = data
  output wire         LCD_RW,    // 0 = write (always)
  output reg  [7:0]   LCD_DATA   // 8-bit parallel data bus
);

  // LCD_RW is permanently low: we only ever write to the display
  assign LCD_RW = 1'b0;

  // ------------------------------------------------------------------
  // Timing constants  (50 MHz clock -> 20 ns per cycle)
  // ------------------------------------------------------------------
  localparam T_PWRON  = 20'd750_000; // 15 ms  - HD44780 power-on delay
  localparam T_SETUP  = 20'd50;      //  1 us  - RS/DATA setup before E rises
  localparam T_EPULSE = 20'd50;      //  1 us  - E high pulse width
  localparam T_INIT1  = 20'd205_000; //  4.1 ms - post-delay after first Function Set
  localparam T_SHORT  = 20'd5_000;   //  100 us - post-delay for most init commands
  localparam T_CLEAR  = 20'd100_000; //  2 ms  - post-delay after Clear Display
  localparam T_WRITE  = 20'd2_500;   //  50 us  - post-delay after each character write

  // ------------------------------------------------------------------
  // FSM state encoding
  // ------------------------------------------------------------------
  localparam [3:0]
    S_PWRON = 4'd0,   // wait for HD44780 power-on delay
    S_FUNC  = 4'd1,   // send Function Set   (0x38: 8-bit, 2-line, 5x8)
    S_DISP  = 4'd2,   // send Display ON     (0x0C: on, cursor off, blink off)
    S_CLR   = 4'd3,   // send Clear Display  (0x01)
    S_ENTRY = 4'd4,   // send Entry Mode Set (0x06: increment, no shift)
    S_ADDR1 = 4'd5,   // set DDRAM address 0x00 (start of line 1)
    S_WRL1  = 4'd6,   // write 16 characters to line 1
    S_ADDR2 = 4'd7,   // set DDRAM address 0x40 (start of line 2)
    S_WRL2  = 4'd8;   // write 16 characters to line 2, then loop to S_ADDR1

  // E-strobe phases used by every command/data state.
  // LCD_EN is active LOW on the DE2-115: idle = 1, pulse = 0.
  localparam [1:0]
    PH_SETUP  = 2'd0,  // hold RS and DATA stable, count setup time  (EN idle = 1)
    PH_EPULSE = 2'd1,  // drive EN = 0 (active-low pulse to the display)
    PH_ELOW   = 2'd2;  // drive EN = 1 (return idle), count post-command delay

  // ------------------------------------------------------------------
  // Registers
  // ------------------------------------------------------------------
  reg [3:0]  state;
  reg [1:0]  phase;
  reg [19:0] cnt;       // countdown timer (clock cycles)
  reg [3:0]  char_cnt;  // which character we are sending (0..15)

  // ------------------------------------------------------------------
  // Extract one ASCII byte from a 128-bit line vector.
  // Character 0 occupies bits [127:120]; character 15 occupies [7:0].
  // Uses concatenation-shift trick to avoid width overflow in synthesis.
  // ------------------------------------------------------------------
  function [7:0] get_char;
    input [127:0] ln;
    input [3:0]   idx;
    reg   [6:0]   base;
    begin
      base     = {(4'd15 - idx), 3'b000}; // (15-idx)*8: char0->120, char15->0
      get_char = ln[base +: 8];
    end
  endfunction

  // ------------------------------------------------------------------
  // FSM
  // ------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst) begin
      state    <= S_PWRON;
      phase    <= PH_SETUP;
      cnt      <= T_PWRON;
      char_cnt <= 4'd0;
      LCD_ON   <= 1'b1;    // active LOW on DE2-115: drive 0 to enable the display
      LCD_BLON <= 1'b1;    // backlight is active high; assert immediately
      LCD_EN   <= 1'b1;    // EN idle state is HIGH (active-low strobe)
      LCD_RS   <= 1'b0;
      LCD_DATA <= 8'h00;
    end else begin
      case (state)

        // ----------------------------------------------------------------
        // Power-on delay: no bus activity, just let the HD44780 boot
        // ----------------------------------------------------------------
        S_PWRON: begin
          LCD_EN <= 1'b1;  // EN idles high (active-low); no strobe during power-on wait
          if (cnt == 20'd0) begin
            state <= S_FUNC;
            phase <= PH_SETUP;
            cnt   <= T_SETUP;
          end else begin
            cnt <= cnt - 1'b1;
          end
        end

        // ----------------------------------------------------------------
        // All command / data states share the same 3-phase E strobe.
        // ----------------------------------------------------------------
        default: begin
          case (phase)

            // -- Setup phase: drive RS and DATA, keep EN = 1 (idle), then wait T_SETUP --
            PH_SETUP: begin
              LCD_EN <= 1'b1;  // EN remains idle (high) while data settles
              case (state)
                S_FUNC:  begin LCD_RS <= 1'b0; LCD_DATA <= 8'h38; end // Function Set
                S_DISP:  begin LCD_RS <= 1'b0; LCD_DATA <= 8'h0C; end // Display ON
                S_CLR:   begin LCD_RS <= 1'b0; LCD_DATA <= 8'h01; end // Clear Display
                S_ENTRY: begin LCD_RS <= 1'b0; LCD_DATA <= 8'h06; end // Entry Mode
                S_ADDR1: begin LCD_RS <= 1'b0; LCD_DATA <= 8'h80; end // DDRAM 0x00
                S_ADDR2: begin LCD_RS <= 1'b0; LCD_DATA <= 8'hC0; end // DDRAM 0x40
                S_WRL1:  begin LCD_RS <= 1'b1; LCD_DATA <= get_char(line1, char_cnt); end
                S_WRL2:  begin LCD_RS <= 1'b1; LCD_DATA <= get_char(line2, char_cnt); end
                default: begin LCD_RS <= 1'b0; LCD_DATA <= 8'h00; end
              endcase
              if (cnt == 20'd0) begin
                phase <= PH_EPULSE;
                cnt   <= T_EPULSE;
              end else begin
                cnt <= cnt - 1'b1;
              end
            end

            // -- Pulse phase: drive EN = 0 (active-low strobe to HD44780) ----
            PH_EPULSE: begin
              LCD_EN <= 1'b0;  // active-low pulse; HD44780 latches on rising edge (our EN going back to 1)
              if (cnt == 20'd0) begin
                LCD_EN <= 1'b1; // end pulse: EN returns idle-high
                phase  <= PH_ELOW;
                // Each command has its own required post-delay
                case (state)
                  S_FUNC:          cnt <= T_INIT1; // 4.1 ms after Function Set
                  S_CLR:           cnt <= T_CLEAR; // 2 ms after Clear Display
                  S_WRL1, S_WRL2:  cnt <= T_WRITE; // 50 us after each char
                  default:         cnt <= T_SHORT;  // 100 us otherwise
                endcase
              end else begin
                cnt <= cnt - 1'b1;
              end
            end

            // -- Post-delay phase: EN stays idle (1), wait, then advance state --
            PH_ELOW: begin
              LCD_EN <= 1'b1;  // EN idle during post-command delay
              if (cnt == 20'd0) begin
                phase <= PH_SETUP;
                cnt   <= T_SETUP;
                case (state)
                  S_FUNC:  state <= S_DISP;
                  S_DISP:  state <= S_CLR;
                  S_CLR:   state <= S_ENTRY;
                  S_ENTRY: begin state <= S_ADDR1; char_cnt <= 4'd0; end
                  S_ADDR1: begin state <= S_WRL1;  char_cnt <= 4'd0; end
                  S_WRL1: begin
                    if (char_cnt == 4'd15) begin
                      state <= S_ADDR2; // done with line 1
                    end else begin
                      char_cnt <= char_cnt + 1'b1; // next char
                    end
                  end
                  S_ADDR2: begin state <= S_WRL2; char_cnt <= 4'd0; end
                  S_WRL2: begin
                    if (char_cnt == 4'd15) begin
                      state    <= S_ADDR1; // refresh: loop back to line 1
                      char_cnt <= 4'd0;
                    end else begin
                      char_cnt <= char_cnt + 1'b1; // next char
                    end
                  end
                  default: state <= S_ADDR1;
                endcase
              end else begin
                cnt <= cnt - 1'b1;
              end
            end

            default: phase <= PH_SETUP;
          endcase
        end

      endcase
    end
  end

endmodule