// lcd_text.v
// Drive the DE2-115 16x2 LCD in 8-bit mode; continually refresh two 16-char lines.

module lcd_text (
  input  wire       clk,     // 50 MHz
  input  wire       rst,
  input  wire [127:0] line1, // 16 ASCII chars, [127:120]=char0 .. [7:0]=char15
  input  wire [127:0] line2,
  output reg        LCD_ON,
  output reg        LCD_BLON,
  output reg        LCD_EN,
  output reg        LCD_RS,
  output reg        LCD_RW,
  output reg [7:0]  LCD_DATA
);

  reg [5:0] div;  // ~1us tick
  wire tick = (div==6'd49);
  always @(posedge clk) begin
    if (rst) div <= 6'd0; else div <= tick ? 6'd0 : (div+1'b1);
  end

  localparam INIT_WAIT=4'd0, INIT_FUNC=4'd1, INIT_ON=4'd2, INIT_CLR=4'd3, INIT_EMS=4'd4,
             IDLE=4'd5, SET_L1=4'd6, PUT_L1=4'd7, SET_L2=4'd8, PUT_L2=4'd9;

  reg [3:0]  st; reg [7:0] cnt; reg [4:0] idx;

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
      st<=INIT_WAIT; cnt<=0; idx<=0;
      LCD_ON<=1'b1; LCD_BLON<=1'b1; LCD_EN<=1'b0; LCD_RS<=1'b0; LCD_RW<=1'b0; LCD_DATA<=8'h00;
    end else if (tick) begin
      LCD_EN<=1'b0;
      case (st)
        INIT_WAIT: begin cnt<=cnt+1'b1; if (cnt==8'd200) st<=INIT_FUNC; end
        INIT_FUNC: begin send_cmd(8'h38); st<=INIT_ON; end
        INIT_ON:   begin send_cmd(8'h0C); st<=INIT_CLR; end
        INIT_CLR:  begin send_cmd(8'h01); st<=INIT_EMS; end
        INIT_EMS:  begin send_cmd(8'h06); st<=IDLE; end
        IDLE:      st<=SET_L1;
        SET_L1:    begin send_cmd(8'h80); idx<=0; st<=PUT_L1; end
        PUT_L1:    begin send_dat(l1_char); idx<=idx+1'b1; if (idx==5'd15) st<=SET_L2; end
        SET_L2:    begin send_cmd(8'hC0); idx<=0; st<=PUT_L2; end
        PUT_L2:    begin send_dat(l2_char); idx<=idx+1'b1; if (idx==5'd15) st<=IDLE; end
        default:   st<=INIT_WAIT;
      endcase
    end
  end
endmodule
