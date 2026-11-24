// =============================================================================
// cmul_q15.v  —  Q1.15 Complex Multiplier  (3-real-multiplier / Karatsuba form)
// =============================================================================
// Pipelined, 3-cycle latency. Maps directly to 3 × DSP48E2.
//
// 3-multiplier form (bit-identical to 4-multiplier, proven by golden model):
//   k1 = wr × (br + bi)
//   k2 = br × (wi − wr)
//   k3 = bi × (wr + wi)
//   re  = (k1 − k3) >> 15
//   im  = (k1 + k2) >> 15
//
// Trivial-twiddle bypass (tw_sel encodes which of {1, −j, −1, +j}):
//   The bypass output is registered with the same 3-cycle latency so the
//   downstream stage never needs to know the multiplier is not running.
//
// Stage 1: pre-adders     (reg)
// Stage 2: 3 × DSP mult   (reg)
// Stage 3: post-add, >>15, saturate  (reg)
//
// out_valid pulses high 3 cycles after in_valid is asserted.
// =============================================================================
module cmul_q15 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         in_valid,

    // Data — Q1.15
    input  wire signed [15:0] br, bi,
    input  wire signed [15:0] wr, wi,

    // Bypass control — registered with same latency as multiply path
    // trivial_w : bypass the multiplier entirely
    // tw_sel    : 2'b00=×1  01=×(−j)  10=×(−1)  11=×(+j)
    input  wire         trivial_w,
    input  wire  [1:0]  tw_sel,

    output reg          out_valid,
    output reg  signed [15:0] out_r,
    output reg  signed [15:0] out_i
);

    // ---- Stage 1: pre-adders ------------------------------------------------
    reg signed [16:0] pa, pb, pc;   // br+bi, wi−wr, wr+wi  (17-bit to hold carry)
    reg signed [15:0] wr1, br1, bi1;
    reg               triv1;
    reg  [1:0]        sel1;
    reg signed [15:0] bpr1, bpi1;  // bypass pipe
    reg               vld1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pa <= 0; pb <= 0; pc <= 0;
            wr1<= 0; br1<= 0; bi1<= 0;
            triv1<=0; sel1<=0;
            bpr1<=0; bpi1<=0; vld1<=0;
        end else begin
            pa   <= $signed({br[15],br}) + $signed({bi[15],bi});
            pb   <= $signed({wi[15],wi}) - $signed({wr[15],wr});
            pc   <= $signed({wr[15],wr}) + $signed({wi[15],wi});
            wr1  <= wr; br1 <= br; bi1 <= bi;
            triv1<= trivial_w; sel1 <= tw_sel;
            bpr1 <= br; bpi1 <= bi;
            vld1 <= in_valid;
        end
    end

    // ---- Stage 2: three DSP multiplies --------------------------------------
    // Product width: 16 × 17 = 33 bits (signed)
    reg signed [32:0] k1, k2, k3;
    reg               triv2;
    reg  [1:0]        sel2;
    reg signed [15:0] bpr2, bpi2;
    reg               vld2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k1<=0; k2<=0; k3<=0;
            triv2<=0; sel2<=0;
            bpr2<=0; bpi2<=0; vld2<=0;
        end else begin
            k1   <= $signed(wr1) * $signed(pa);   // wr × (br+bi)
            k2   <= $signed(br1) * $signed(pb);   // br × (wi−wr)
            k3   <= $signed(bi1) * $signed(pc);   // bi × (wr+wi)
            triv2<= triv1; sel2 <= sel1;
            bpr2 <= bpr1; bpi2 <= bpi1;
            vld2 <= vld1;
        end
    end

    // ---- Stage 3: post-add, >>15, saturate ----------------------------------
    // acc_r = k1 − k3,  acc_i = k1 + k2  (up to 34 bits)
    wire signed [33:0] acc_r = $signed(k1) - $signed(k3);
    wire signed [33:0] acc_i = $signed(k1) + $signed(k2);

    // Arithmetic >>15: take bits [33:15], which is a 19-bit signed value
    wire signed [18:0] sh_r = acc_r[33:15];
    wire signed [18:0] sh_i = acc_i[33:15];

    // Saturate to 16-bit signed
    function signed [15:0] sat16;
        input signed [18:0] x;
        begin
            if      (x >  19'sd32767) sat16 =  16'sd32767;
            else if (x < -19'sd32768) sat16 = -16'sd32768;
            else                      sat16 = x[15:0];
        end
    endfunction

    // Trivial bypass rotation
    reg signed [15:0] tr_r, tr_i;
    always @(*) begin
        case (sel2)
            2'b00: begin tr_r =  bpr2; tr_i =  bpi2; end  // ×1
            2'b01: begin tr_r =  bpi2; tr_i = -bpr2; end  // ×(−j)
            2'b10: begin tr_r = -bpr2; tr_i = -bpi2; end  // ×(−1)
            2'b11: begin tr_r = -bpi2; tr_i =  bpr2; end  // ×(+j)
            default: begin tr_r = bpr2; tr_i = bpi2; end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_r <= 0; out_i <= 0; out_valid <= 0;
        end else begin
            out_valid <= vld2;
            if (triv2) begin
                out_r <= tr_r;
                out_i <= tr_i;
            end else begin
                out_r <= sat16(sh_r);
                out_i <= sat16(sh_i);
            end
        end
    end

endmodule
