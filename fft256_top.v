// =============================================================================
// fft256_top.v  —  256-Point Radix-2^2 SDF FFT  (Vivado-compatible)
// =============================================================================
//
// Cascades 4 × sdf_stage with twiddle_rom + cmul_q15 between stages 0-2.
//
// Timing alignment (critical):
//   sdf_stage outputs out_r/out_i/out_valid AND out_tw_addr at the SAME cycle T.
//   twiddle_rom has 1-cycle latency: tw_r/tw_i appear at T+1.
//   Therefore out_r/out_i/out_valid must be delayed 1 cycle (pipe_*) so that
//   the cmul_q15 sees aligned data and twiddle at cycle T+1.
//   cmul_q15 has 3-cycle pipeline → its output arrives at T+4.
//
// Pipeline:
//   Input → Stage0(L=256) → [1-cyc delay] → cmul0(3-cyc) → Stage1(L=64)
//          → [1-cyc delay] → cmul1(3-cyc) → Stage2(L=16)
//          → [1-cyc delay] → cmul2(3-cyc) → Stage3(L=4)  → Output
//
// Total pipeline latency ≈ 256 + 4 + 64 + 4 + 16 + 4 + 4 = ~352 clock cycles
// after the first valid input.
// =============================================================================
module fft256_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire signed [15:0] in_r,
    input  wire signed [15:0] in_i,

    output wire        out_valid,
    output wire signed [15:0] out_r,
    output wire signed [15:0] out_i
);

    // =========================================================================
    // Helper: 1-cycle pipeline register (data + valid)
    // =========================================================================
    // Used between each sdf_stage output and the corresponding cmul_q15 input
    // to absorb the twiddle_rom 1-cycle latency.

    // =========================================================================
    // Stage 0  (L=256, Q=64, STRIDE=1)
    // =========================================================================
    wire        s0_valid;
    wire signed [15:0] s0_r, s0_i;
    wire [7:0]  s0_tw_addr;
    wire        s0_tw_triv;
    wire [1:0]  s0_tw_sel;

    sdf_stage #(.L(256),.Q(64),.STRIDE(1),.HAS_TWIDDLE(1)) u_s0 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_r(in_r), .in_i(in_i),
        .out_valid(s0_valid), .out_r(s0_r), .out_i(s0_i),
        .out_tw_addr(s0_tw_addr), .out_tw_triv(s0_tw_triv), .out_tw_sel(s0_tw_sel)
    );

    // 1-cycle data delay to match twiddle_rom latency
    reg        p0_valid; reg signed [15:0] p0_r, p0_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin p0_valid<=0; p0_r<=0; p0_i<=0; end
        else begin p0_valid<=s0_valid; p0_r<=s0_r; p0_i<=s0_i; end
    end

    // Twiddle ROM 0 (address presented at same cycle as s0_tw_addr appears)
    wire signed [15:0] tw0_r, tw0_i;
    twiddle_rom u_tw0 (.clk(clk), .addr(s0_tw_addr), .tw_r(tw0_r), .tw_i(tw0_i));

    // 1-cycle delay for bypass control signals to match ROM latency
    reg        p0_triv; reg [1:0] p0_sel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin p0_triv<=1; p0_sel<=0; end
        else begin p0_triv<=s0_tw_triv; p0_sel<=s0_tw_sel; end
    end

    // cmul 0 — sees aligned data (p0_*) and twiddle (tw0_*) at the same cycle
    wire        c0_valid;
    wire signed [15:0] c0_r, c0_i;
    cmul_q15 u_cm0 (
        .clk(clk), .rst_n(rst_n), .in_valid(p0_valid),
        .br(p0_r), .bi(p0_i), .wr(tw0_r), .wi(tw0_i),
        .trivial_w(p0_triv), .tw_sel(p0_sel),
        .out_valid(c0_valid), .out_r(c0_r), .out_i(c0_i)
    );

    // =========================================================================
    // Stage 1  (L=64, Q=16, STRIDE=4)
    // =========================================================================
    wire        s1_valid;
    wire signed [15:0] s1_r, s1_i;
    wire [7:0]  s1_tw_addr;
    wire        s1_tw_triv;
    wire [1:0]  s1_tw_sel;

    sdf_stage #(.L(64),.Q(16),.STRIDE(4),.HAS_TWIDDLE(1)) u_s1 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(c0_valid), .in_r(c0_r), .in_i(c0_i),
        .out_valid(s1_valid), .out_r(s1_r), .out_i(s1_i),
        .out_tw_addr(s1_tw_addr), .out_tw_triv(s1_tw_triv), .out_tw_sel(s1_tw_sel)
    );

    reg        p1_valid; reg signed [15:0] p1_r, p1_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin p1_valid<=0; p1_r<=0; p1_i<=0; end
        else begin p1_valid<=s1_valid; p1_r<=s1_r; p1_i<=s1_i; end
    end

    wire signed [15:0] tw1_r, tw1_i;
    twiddle_rom u_tw1 (.clk(clk), .addr(s1_tw_addr), .tw_r(tw1_r), .tw_i(tw1_i));

    reg p1_triv; reg [1:0] p1_sel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin p1_triv<=1; p1_sel<=0; end
        else begin p1_triv<=s1_tw_triv; p1_sel<=s1_tw_sel; end
    end

    wire        c1_valid;
    wire signed [15:0] c1_r, c1_i;
    cmul_q15 u_cm1 (
        .clk(clk), .rst_n(rst_n), .in_valid(p1_valid),
        .br(p1_r), .bi(p1_i), .wr(tw1_r), .wi(tw1_i),
        .trivial_w(p1_triv), .tw_sel(p1_sel),
        .out_valid(c1_valid), .out_r(c1_r), .out_i(c1_i)
    );

    // =========================================================================
    // Stage 2  (L=16, Q=4, STRIDE=16)
    // =========================================================================
    wire        s2_valid;
    wire signed [15:0] s2_r, s2_i;
    wire [7:0]  s2_tw_addr;
    wire        s2_tw_triv;
    wire [1:0]  s2_tw_sel;

    sdf_stage #(.L(16),.Q(4),.STRIDE(16),.HAS_TWIDDLE(1)) u_s2 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(c1_valid), .in_r(c1_r), .in_i(c1_i),
        .out_valid(s2_valid), .out_r(s2_r), .out_i(s2_i),
        .out_tw_addr(s2_tw_addr), .out_tw_triv(s2_tw_triv), .out_tw_sel(s2_tw_sel)
    );

    reg        p2_valid; reg signed [15:0] p2_r, p2_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin p2_valid<=0; p2_r<=0; p2_i<=0; end
        else begin p2_valid<=s2_valid; p2_r<=s2_r; p2_i<=s2_i; end
    end

    wire signed [15:0] tw2_r, tw2_i;
    twiddle_rom u_tw2 (.clk(clk), .addr(s2_tw_addr), .tw_r(tw2_r), .tw_i(tw2_i));

    reg p2_triv; reg [1:0] p2_sel;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin p2_triv<=1; p2_sel<=0; end
        else begin p2_triv<=s2_tw_triv; p2_sel<=s2_tw_sel; end
    end

    wire        c2_valid;
    wire signed [15:0] c2_r, c2_i;
    cmul_q15 u_cm2 (
        .clk(clk), .rst_n(rst_n), .in_valid(p2_valid),
        .br(p2_r), .bi(p2_i), .wr(tw2_r), .wi(tw2_i),
        .trivial_w(p2_triv), .tw_sel(p2_sel),
        .out_valid(c2_valid), .out_r(c2_r), .out_i(c2_i)
    );

    // =========================================================================
    // Stage 3  (L=4, Q=1, no twiddle)
    // =========================================================================
    sdf_stage #(.L(4),.Q(1),.STRIDE(64),.HAS_TWIDDLE(0)) u_s3 (
        .clk(clk), .rst_n(rst_n),
        .in_valid(c2_valid), .in_r(c2_r), .in_i(c2_i),
        .out_valid(out_valid), .out_r(out_r), .out_i(out_i),
        .out_tw_addr(), .out_tw_triv(), .out_tw_sel()
    );

endmodule
