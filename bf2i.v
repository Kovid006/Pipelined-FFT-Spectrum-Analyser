// =============================================================================
// bf2i.v  —  Radix-2^2 SDF Butterfly Type-I  (combinational)
// =============================================================================
// Computes the first butterfly in one radix-2^2 module.
// Operates on two pairs (x0,x2) and (x1,x3) separated by HALF=L/2 delay.
//
//   s0 = (x0 + x2) >>> 1      (arithmetic right-shift — truncation)
//   d0 = (x0 - x2) >>> 1
//   s1 = (x1 + x3) >>> 1
//   d1 = (x1 - x3) >>> 1
//
// No saturation needed: inputs are Q1.15 ∈ [−1, 1−2^-15], so the
// unscaled sum fits in 17 bits; >>1 brings it back to 16 bits.
//
// Matches golden model _shr1(a+b, rnd=False) with round_mode='trunc'.
// =============================================================================
module bf2i (
    input  wire signed [15:0] x0r, x0i,
    input  wire signed [15:0] x1r, x1i,
    input  wire signed [15:0] x2r, x2i,
    input  wire signed [15:0] x3r, x3i,

    output wire signed [15:0] s0r, s0i,
    output wire signed [15:0] d0r, d0i,
    output wire signed [15:0] s1r, s1i,
    output wire signed [15:0] d1r, d1i
);
    // 17-bit sign-extended sum/diff, then arithmetic >>1 = take bits [16:1]
    assign s0r = ({x0r[15], x0r} + {x2r[15], x2r}) >>> 1;
    assign s0i = ({x0i[15], x0i} + {x2i[15], x2i}) >>> 1;
    assign d0r = ({x0r[15], x0r} - {x2r[15], x2r}) >>> 1;
    assign d0i = ({x0i[15], x0i} - {x2i[15], x2i}) >>> 1;
    assign s1r = ({x1r[15], x1r} + {x3r[15], x3r}) >>> 1;
    assign s1i = ({x1i[15], x1i} + {x3i[15], x3i}) >>> 1;
    assign d1r = ({x1r[15], x1r} - {x3r[15], x3r}) >>> 1;
    assign d1i = ({x1i[15], x1i} - {x3i[15], x3i}) >>> 1;
endmodule
