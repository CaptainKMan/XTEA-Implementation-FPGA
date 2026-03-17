// xtea_core.v
// Synthesizable XTEA (64-bit block, 128-bit key), 32 cycles iterative.
// enc=1: encrypt, enc=0: decrypt. One block per ~34 cycles (init+32+done).
// Algorithm per widely used reference: 32 cycles (64 Feistel rounds),
// delta = 0x9E3779B9, key selection by sum&3 and (sum>>11)&3.

module xtea_core (
  input  wire        clk,
  input  wire        rst,      // synchronous, active-high
  input  wire        start,    // pulse to start one block
  input  wire        enc,      // 1=encrypt, 0=decrypt
  input  wire [127:0] key,     // k[127:96], k[95:64], k[63:32], k[31:0]
  input  wire [63:0]  block_in,// v0|v1 (MSB..LSB) -> {v0[31:0], v1[31:0]}
  output reg  [63:0]  block_out,
  output reg         done
);

  localparam [31:0] DELTA = 32'h9E37_79B9;

  // Unpack key
  wire [31:0] k0 = key[127:96];
  wire [31:0] k1 = key[95:64];
  wire [31:0] k2 = key[63:32];
  wire [31:0] k3 = key[31:0];

  // FSM
  localparam S_IDLE=2'd0, S_RUN=2'd1, S_DONE=2'd2;
  reg [1:0] state;

  // datapath
  reg [31:0] v0, v1, sum;
  reg [5:0]  round; // 0..31

  // key select helpers
  wire [31:0] key_low  = (sum[1:0]==2'd0)?k0:(sum[1:0]==2'd1)?k1:(sum[1:0]==2'd2)?k2:k3;
  wire [31:0] key_high = ((sum[12:11])==2'b00)?k0:((sum[12:11])==2'b01)?k1:((sum[12:11])==2'b10)?k2:k3;

  // round functions for encrypt
  wire [31:0] f0_enc = (((v1 << 4) ^ (v1 >> 5)) + v1) ^ (sum + key_low);
  wire [31:0] f1_enc;
  assign f1_enc = ((((v0 + f0_enc) << 4) ^ ((v0 + f0_enc) >> 5)) + (v0 + f0_enc)) ^ ((sum + DELTA) + key_high);

  // For decrypt compute in reverse
  wire [31:0] key_high_d = ((sum[12:11])==2'b00)?k0:((sum[12:11])==2'b01)?k1:((sum[12:11])==2'b10)?k2:k3;
  wire [31:0] f1_dec = (((v0 << 4) ^ (v0 >> 5)) + v0) ^ (sum + key_high_d);
  wire [31:0] v1_prev = v1 - f1_dec;
  wire [31:0] key_low_d = (((sum - DELTA)[1:0])==2'd0)?k0:(((sum - DELTA)[1:0])==2'd1)?k1:(((sum - DELTA)[1:0])==2'd2)?k2:k3;
  wire [31:0] f0_dec = ((((v1_prev) << 4) ^ ((v1_prev) >> 5)) + (v1_prev)) ^ ((sum - DELTA) + key_low_d);

  always @(posedge clk) begin
    if (rst) begin
      state <= S_IDLE;
      done  <= 1'b0;
      round <= 6'd0;
      v0    <= 32'd0;
      v1    <= 32'd0;
      sum   <= 32'd0;
      block_out <= 64'd0;
    end else begin
      done <= 1'b0;
      case (state)
        S_IDLE: begin
          if (start) begin
            v0  <= block_in[63:32];
            v1  <= block_in[31:0];
            round <= 6'd0;
            if (enc) begin
              sum   <= 32'd0;
            end else begin
              sum   <= DELTA * 32; // sum = delta * num_rounds
            end
            state <= S_RUN;
          end
        end

        S_RUN: begin
          if (enc) begin
            v0  <= v0 + f0_enc;
            sum <= sum + DELTA;
            v1  <= v1 + f1_enc;
            round <= round + 1'b1;
            if (round == 6'd31) begin
              block_out <= {v0 + f0_enc, v1 + f1_enc};
              state <= S_DONE;
            end
          end else begin
            v1  <= v1_prev;
            sum <= sum - DELTA;
            v0  <= v0 - f0_dec;
            round <= round + 1'b1;
            if (round == 6'd31) begin
              block_out <= {v0 - f0_dec, v1_prev};
              state <= S_DONE;
            end
          end
        end

        S_DONE: begin
          done  <= 1'b1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
