// =============================================================================
// sdf_stage.v  — Radix-2^2 Single-Path Delay-Feedback (SDF) Stage
//                Vivado / Verilog-2001 compatible
// =============================================================================
// Architecture:
//   For a block of L=4Q samples, arriving one per clock when in_valid=1:
//
//     Quarter 0 [0..Q-1]    : store x0 → bfi0 RAM
//     Quarter 1 [Q..2Q-1]   : store x1 → bfi1 RAM
//     Quarter 2 [2Q..3Q-1]  : BF2I(bfi0[k], x2) → s0,d0  stored in bfii RAM
//     Quarter 3 [3Q..4Q-1]  : BF2I(bfi1[k], x3) → s1,d1
//                             BF2II(s0,d0, s1,d1) → y0,y2,y1,y3
//                             → written into active output bank
//
//   After each complete block, the write bank flips and the output FSM streams
//   the JUST-WRITTEN bank out at one sample per clock.
//
// Key fix vs. prior version:
//   rb_lat is captured as ~wb (before toggle) so it always points to the
//   bank that was just finished writing, not the now-active write bank.
//
// Parameters:
//   L           : block length  {256, 64, 16, 4}
//   Q           : L/4           {64, 16, 4, 1}
//   STRIDE      : 256/L         {1, 4, 16, 64}
//   HAS_TWIDDLE : 1 for stages 0-2, 0 for stage 3
// =============================================================================
`timescale 1ns/1ps
module sdf_stage #(
    parameter integer L           = 256,
    parameter integer Q           = 64,
    parameter integer STRIDE      = 1,
    parameter integer HAS_TWIDDLE = 1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,

    input  wire signed [15:0] in_r,
    input  wire signed [15:0] in_i,

    output reg         out_valid,
    output reg  signed [15:0] out_r,
    output reg  signed [15:0] out_i,

    output reg  [7:0]  out_tw_addr,
    output reg         out_tw_triv,
    output reg  [1:0]  out_tw_sel
);

    // =========================================================================
    // Safe width parameters
    //   AW = $clog2(L) — bits needed to count 0..L-1
    //   QW = $clog2(Q) but minimum 1 (protects against Q=1 / stage-3)
    // =========================================================================
    localparam integer AW  = (L  > 1) ? $clog2(L)  : 1;
    localparam integer QW  = (Q  > 1) ? $clog2(Q)  : 1;

    // Last count value = L-1, computed as a constant
    // We use L-1 directly (Verilog integer arithmetic, then truncate)
    localparam integer L_MINUS1 = L - 1;
    localparam integer Q_MINUS1 = Q - 1;

    // =========================================================================
    // Block sample counter  0 .. L-1
    // =========================================================================
    reg [AW-1:0] cnt;
    wire cnt_last = (cnt == L_MINUS1[AW-1:0]);

    always @(posedge clk or negedge rst_n)
        if (!rst_n)        cnt <= {AW{1'b0}};
        else if (in_valid) cnt <= cnt_last ? {AW{1'b0}} : cnt + 1'b1;

    // Quarter index within block (Q samples per quarter) — bottom QW bits.
    // Special case for Q=1 (Stage 3, L=4, AW=2, QW=1):
    //   quarter uses cnt[1:0] (all bits), so there are NO bits left for q_idx.
    //   With Q=1 there is exactly 1 sample per quarter, so q_idx must be 0.
    //   For Q>1: AW = 2+QW, so quarter uses cnt[AW-1:AW-2] and q_idx
    //   uses cnt[QW-1:0] with no overlap.
    localparam Q_IS_1 = (Q <= 1) ? 1 : 0;
    wire [QW-1:0] q_idx = Q_IS_1 ? {QW{1'b0}} : cnt[QW-1:0];

    // Which of the 4 quarters (top 2 bits of AW-bit counter)
    wire [1:0] quarter = cnt[AW-1:AW-2];

    // =========================================================================
    // BF2I delay memories
    // =========================================================================
    reg signed [15:0] bfi0_r [0:Q-1];
    reg signed [15:0] bfi0_i [0:Q-1];
    reg signed [15:0] bfi1_r [0:Q-1];
    reg signed [15:0] bfi1_i [0:Q-1];

    always @(posedge clk) begin
        if (in_valid) begin
            if (quarter == 2'b00) begin
                bfi0_r[q_idx] <= in_r;
                bfi0_i[q_idx] <= in_i;
            end
            if (quarter == 2'b01) begin
                bfi1_r[q_idx] <= in_r;
                bfi1_i[q_idx] <= in_i;
            end
        end
    end

    // =========================================================================
    // BF2I butterfly  (active during quarters 2 and 3)
    // =========================================================================
    wire bfi_active = (quarter == 2'b10) || (quarter == 2'b11);
    wire use_slot1  = quarter[0];  // 0=use bfi0, 1=use bfi1

    wire signed [15:0] stored_r = use_slot1 ? bfi1_r[q_idx] : bfi0_r[q_idx];
    wire signed [15:0] stored_i = use_slot1 ? bfi1_i[q_idx] : bfi0_i[q_idx];

    // s = (stored + in) >>> 1,   d = (stored - in) >>> 1  (truncation)
    wire signed [16:0] bfi_sum_r17  = {stored_r[15], stored_r} + {in_r[15], in_r};
    wire signed [16:0] bfi_sum_i17  = {stored_i[15], stored_i} + {in_i[15], in_i};
    wire signed [16:0] bfi_diff_r17 = {stored_r[15], stored_r} - {in_r[15], in_r};
    wire signed [16:0] bfi_diff_i17 = {stored_i[15], stored_i} - {in_i[15], in_i};

    wire signed [15:0] bfi_s_r = bfi_sum_r17[16:1];
    wire signed [15:0] bfi_s_i = bfi_sum_i17[16:1];
    wire signed [15:0] bfi_d_r = bfi_diff_r17[16:1];
    wire signed [15:0] bfi_d_i = bfi_diff_i17[16:1];

    // =========================================================================
    // BF2II delay memories — save (s0,d0) from quarter 2
    // =========================================================================
    reg signed [15:0] bfii_s0r [0:Q-1], bfii_s0i [0:Q-1];
    reg signed [15:0] bfii_d0r [0:Q-1], bfii_d0i [0:Q-1];

    always @(posedge clk) begin
        if (in_valid && bfi_active && !use_slot1) begin
            bfii_s0r[q_idx] <= bfi_s_r;
            bfii_s0i[q_idx] <= bfi_s_i;
            bfii_d0r[q_idx] <= bfi_d_r;
            bfii_d0i[q_idx] <= bfi_d_i;
        end
    end

    // =========================================================================
    // BF2II butterfly  (quarter 3 only)
    // =========================================================================
    wire bfii_active = (quarter == 2'b11);

    wire signed [15:0] s0r = bfii_s0r[q_idx];
    wire signed [15:0] s0i = bfii_s0i[q_idx];
    wire signed [15:0] d0r = bfii_d0r[q_idx];
    wire signed [15:0] d0i = bfii_d0i[q_idx];
    wire signed [15:0] s1r = bfi_s_r;
    wire signed [15:0] s1i = bfi_s_i;
    wire signed [15:0] d1r = bfi_d_r;
    wire signed [15:0] d1i = bfi_d_i;

    // -j * d1 = (d1i, -d1r)
    wire signed [15:0] nj_r =  d1i;
    wire signed [15:0] nj_i = -d1r;

    wire signed [16:0] y0r17 = {s0r[15],s0r} + {s1r[15],s1r};
    wire signed [16:0] y0i17 = {s0i[15],s0i} + {s1i[15],s1i};
    wire signed [16:0] y2r17 = {s0r[15],s0r} - {s1r[15],s1r};
    wire signed [16:0] y2i17 = {s0i[15],s0i} - {s1i[15],s1i};
    wire signed [16:0] y1r17 = {d0r[15],d0r} + {nj_r[15],nj_r};
    wire signed [16:0] y1i17 = {d0i[15],d0i} + {nj_i[15],nj_i};
    wire signed [16:0] y3r17 = {d0r[15],d0r} - {nj_r[15],nj_r};
    wire signed [16:0] y3i17 = {d0i[15],d0i} - {nj_i[15],nj_i};

    wire signed [15:0] y0r = y0r17[16:1];  wire signed [15:0] y0i = y0i17[16:1];
    wire signed [15:0] y2r = y2r17[16:1];  wire signed [15:0] y2i = y2i17[16:1];
    wire signed [15:0] y1r = y1r17[16:1];  wire signed [15:0] y1i = y1i17[16:1];
    wire signed [15:0] y3r = y3r17[16:1];  wire signed [15:0] y3i = y3i17[16:1];

    // =========================================================================
    // Ping-pong output banks (A and B)
    // The write bank (wb=0→A, wb=1→B) receives one complete block of Q samples
    // per sub-block (y0,y2,y1,y3) during quarter 3 of the INPUT.
    // The READ bank is always the OPPOSITE: the block just finished.
    //
    // FIX: wb is toggled AT the last-sample edge. rb_lat is captured as
    //      ~wb (old value = bank that was written) so the output FSM always
    //      reads from the correct bank.
    // =========================================================================
    reg signed [15:0] a_y0r [0:Q-1], a_y0i [0:Q-1];
    reg signed [15:0] a_y2r [0:Q-1], a_y2i [0:Q-1];
    reg signed [15:0] a_y1r [0:Q-1], a_y1i [0:Q-1];
    reg signed [15:0] a_y3r [0:Q-1], a_y3i [0:Q-1];

    reg signed [15:0] b_y0r [0:Q-1], b_y0i [0:Q-1];
    reg signed [15:0] b_y2r [0:Q-1], b_y2i [0:Q-1];
    reg signed [15:0] b_y1r [0:Q-1], b_y1i [0:Q-1];
    reg signed [15:0] b_y3r [0:Q-1], b_y3i [0:Q-1];

    reg wb;  // Current WRITE bank: 0→A, 1→B

    // Toggle write bank after each complete block (at the last sample)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wb <= 1'b0;
        else if (in_valid && cnt_last) wb <= ~wb;
    end

    // Write y0..y3 into active write bank during quarter 3
    always @(posedge clk) begin
        if (in_valid && bfii_active) begin
            if (!wb) begin
                a_y0r[q_idx]<=y0r; a_y0i[q_idx]<=y0i;
                a_y2r[q_idx]<=y2r; a_y2i[q_idx]<=y2i;
                a_y1r[q_idx]<=y1r; a_y1i[q_idx]<=y1i;
                a_y3r[q_idx]<=y3r; a_y3i[q_idx]<=y3i;
            end else begin
                b_y0r[q_idx]<=y0r; b_y0i[q_idx]<=y0i;
                b_y2r[q_idx]<=y2r; b_y2i[q_idx]<=y2i;
                b_y1r[q_idx]<=y1r; b_y1i[q_idx]<=y1i;
                b_y3r[q_idx]<=y3r; b_y3i[q_idx]<=y3i;
            end
        end
    end

    // =========================================================================
    // Output stream FSM: streams [y0|y2|y1|y3], one sample/clock.
    //
    // Two start paths:
    //   COLD START  — FSM idle (o_en=0), block_pending=1 → start from scratch.
    //   SEAMLESS    — FSM at last sample (o_sub=3, o_last_idx), block_pending=1
    //                 → restart immediately, keep o_en=1, no gap cycle.
    //
    // WHY SEAMLESS?  The output mux adds 1 reg stage (out_valid <= o_en).
    // A cold-start takes 2 cycles before out_valid rises, creating a 1-cycle
    // gap between blocks.  For small L (Stage 3, L=4), input blocks arrive
    // every 4 cycles but output blocks would take 5 (4 data + 1 gap).  After
    // several blocks the FSM falls a full block behind, and ~wb reads the
    // wrong ping-pong bank.  Seamless restart removes the gap entirely.
    // =========================================================================
    reg [1:0]    o_sub;
    reg [QW-1:0] o_idx;
    reg          o_en;

    wire o_last_idx    = (o_idx == Q_MINUS1[QW-1:0]);
    wire o_last_sample = o_en && o_last_idx && (o_sub == 2'd3);

    // ---- block_pending: sticky flag, cleared on cold-start OR seamless ------
    reg block_pending;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) block_pending <= 1'b0;
        else begin
            if (in_valid && cnt_last)
                block_pending <= 1'b1;
            else if ((!o_en && block_pending) ||
                     (o_last_sample && block_pending))
                block_pending <= 1'b0;
        end
    end

    // ---- FSM ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_sub <= 2'd0; o_idx <= {QW{1'b0}}; o_en <= 1'b0;
        end else begin
            if (!o_en && block_pending) begin
                // Cold start
                o_en  <= 1'b1;
                o_sub <= 2'd0;
                o_idx <= {QW{1'b0}};
            end else if (o_en) begin
                if (o_last_idx) begin
                    o_idx <= {QW{1'b0}};
                    if (o_sub == 2'd3) begin
                        o_sub <= 2'd0;
                        if (block_pending)
                            o_en <= 1'b1;   // seamless restart — no gap
                        else
                            o_en <= 1'b0;   // normal termination
                    end else begin
                        o_sub <= o_sub + 2'd1;
                    end
                end else begin
                    o_idx <= o_idx + 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Read bank selector: captured on cold-start or seamless restart.
    //   wb has ALREADY been toggled at the last-sample edge, so ~wb always
    //   points to the bank that was just finished writing.
    // =========================================================================
    reg rb_lat;   // 0 → read bank A, 1 → read bank B

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rb_lat <= 1'b0;
        else if ((!o_en && block_pending) ||
                 (o_last_sample && block_pending))
            rb_lat <= ~wb;
    end

    // =========================================================================
    // Output data mux (registered — out_valid/out_r/out_i appear together)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0; out_r <= 16'sd0; out_i <= 16'sd0;
        end else begin
            out_valid <= o_en;
            if (o_en) begin
                case (o_sub)
                    2'd0: begin
                        out_r <= rb_lat ? b_y0r[o_idx] : a_y0r[o_idx];
                        out_i <= rb_lat ? b_y0i[o_idx] : a_y0i[o_idx];
                    end
                    2'd1: begin
                        out_r <= rb_lat ? b_y2r[o_idx] : a_y2r[o_idx];
                        out_i <= rb_lat ? b_y2i[o_idx] : a_y2i[o_idx];
                    end
                    2'd2: begin
                        out_r <= rb_lat ? b_y1r[o_idx] : a_y1r[o_idx];
                        out_i <= rb_lat ? b_y1i[o_idx] : a_y1i[o_idx];
                    end
                    2'd3: begin
                        out_r <= rb_lat ? b_y3r[o_idx] : a_y3r[o_idx];
                        out_i <= rb_lat ? b_y3i[o_idx] : a_y3i[o_idx];
                    end
                    default: begin out_r <= 16'sd0; out_i <= 16'sd0; end
                endcase
            end
        end
    end

    // =========================================================================
    // Twiddle address generation  (HAS_TWIDDLE=1 only)
    // =========================================================================
    generate
    if (HAS_TWIDDLE) begin : gen_tw

        reg [7:0] tw_addr_next;
        reg       tw_triv_next;
        reg [1:0] tw_sel_next;

        always @(*) begin
            case (o_sub)
                2'd0: begin  // y0: exponent = 0 × n × STRIDE — always trivial
                    tw_addr_next = 8'h00;
                    tw_triv_next = 1'b1;
                    tw_sel_next  = 2'b00;
                end
                2'd1: begin  // y2: exponent = 2 × n × STRIDE
                    tw_addr_next = (8'd2 * {{(8-QW){1'b0}}, o_idx} * STRIDE[7:0]) & 8'hFF;
                    tw_triv_next = ((tw_addr_next & 8'h3F) == 8'h00);
                    tw_sel_next  = tw_addr_next[7:6];
                end
                2'd2: begin  // y1: exponent = 1 × n × STRIDE
                    tw_addr_next = ({{(8-QW){1'b0}}, o_idx} * STRIDE[7:0]) & 8'hFF;
                    tw_triv_next = ((tw_addr_next & 8'h3F) == 8'h00);
                    tw_sel_next  = tw_addr_next[7:6];
                end
                2'd3: begin  // y3: exponent = 3 × n × STRIDE
                    tw_addr_next = (8'd3 * {{(8-QW){1'b0}}, o_idx} * STRIDE[7:0]) & 8'hFF;
                    tw_triv_next = ((tw_addr_next & 8'h3F) == 8'h00);
                    tw_sel_next  = tw_addr_next[7:6];
                end
                default: begin
                    tw_addr_next = 8'h00;
                    tw_triv_next = 1'b1;
                    tw_sel_next  = 2'b00;
                end
            endcase
        end

        // Register to align with the registered out_r/out_i
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                out_tw_addr <= 8'h00; out_tw_triv <= 1'b1; out_tw_sel <= 2'b00;
            end else begin
                out_tw_addr <= tw_addr_next;
                out_tw_triv <= tw_triv_next;
                out_tw_sel  <= tw_sel_next;
            end
        end

    end else begin : gen_notw

        // Stage 3: no twiddle — tie off outputs (registered for consistency)
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                out_tw_addr <= 8'h00; out_tw_triv <= 1'b1; out_tw_sel <= 2'b00;
            end else begin
                out_tw_addr <= 8'h00; out_tw_triv <= 1'b1; out_tw_sel <= 2'b00;
            end
        end

    end
    endgenerate

endmodule
