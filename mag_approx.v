// =============================================================================
// mag_approx.v  —  Q1.15 Magnitude Approximation (2-stage Pipelined)
// =============================================================================
// Computes |z| ≈ max(|re|,|im|) + 3/8 · min(|re|,|im|)
// using only shifts and adds — no multiplier.
//   3/8 ≈ 1/4 + 1/8  =  >>2 + >>3
//
// Matches golden model mag_approx() in fft_r22_golden.py.
//
// Pipelined into 2 stages to close timing at 125 MHz (8.0 ns):
//   Stage 1: Compute absolute values of re and im (negate if sign bit set)
//   Stage 2: Compare, select max/min, shift-add and final sum -> output register
//
// Latency: 2 clock cycles.
// =============================================================================
module mag_approx (
    input  wire               clk,
    input  wire               rst_n,
    input  wire signed [15:0] re,
    input  wire signed [15:0] im,
    output reg         [16:0] mag    // 17-bit unsigned magnitude (registered)
);
    // -------------------------------------------------------------------------
    // Stage 1: Absolute values (16-bit complementer)
    // -------------------------------------------------------------------------
    reg [15:0] abs_re_r, abs_im_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            abs_re_r <= 16'd0;
            abs_im_r <= 16'd0;
        end else begin
            abs_re_r <= re[15] ? (~re + 1'b1) : re;
            abs_im_r <= im[15] ? (~im + 1'b1) : im;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: max/min select and 3/8 · lo addition
    // -------------------------------------------------------------------------
    wire [15:0] hi = (abs_re_r >= abs_im_r) ? abs_re_r : abs_im_r;
    wire [15:0] lo = (abs_re_r >= abs_im_r) ? abs_im_r : abs_re_r;

    // 3/8 · lo = (lo >> 2) + (lo >> 3)
    wire [15:0] three_eights_lo = (lo >> 2) + (lo >> 3);

    // Final sum registered
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mag <= 17'd0;
        end else begin
            mag <= {1'b0, hi} + {1'b0, three_eights_lo};
        end
    end

endmodule
