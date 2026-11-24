// =============================================================================
// bf2ii.v  —  Radix-2^2 SDF Butterfly Type-II  (combinational)
// =============================================================================
// Computes the second butterfly in one radix-2^2 module.
// The trivial −j rotation is applied to d1 before the butterfly.
//
//   −j · d1  :  real' =  d1i,   imag' = −d1r     (exact, no multiplier)
//
//   y0 = (s0 + s1)       >>> 1
//   y2 = (s0 − s1)       >>> 1
//   y1 = (d0 + (−j·d1))  >>> 1
//   y3 = (d0 − (−j·d1))  >>> 1
//
// Output block order:  [y0 | y2 | y1 | y3]
// (matches golden: np.stack([y0r,y2r,y1r,y3r], axis=1).reshape(−1))
//
// All I/O are Q1.15 signed 16-bit.
// =============================================================================
module bf2ii (
    input  wire signed [15:0] s0r, s0i,
    input  wire signed [15:0] d0r, d0i,
    input  wire signed [15:0] s1r, s1i,
    input  wire signed [15:0] d1r, d1i,

    output wire signed [15:0] y0r, y0i,
    output wire signed [15:0] y2r, y2i,
    output wire signed [15:0] y1r, y1i,
    output wire signed [15:0] y3r, y3i
);
    // −j · d1 = ( d1i, −d1r ) — exact, no overflow (d1i is already Q1.15)
    wire signed [15:0] tr =  d1i;
    wire signed [15:0] ti = -d1r;   // -(-32768) = +32768 saturates — but
                                     // d1r ∈ (−32767..32767] after BF2I >>1,
                                     // so this is safe (max magnitude 32767).

    assign y0r = ({s0r[15],s0r} + {s1r[15],s1r}) >>> 1;
    assign y0i = ({s0i[15],s0i} + {s1i[15],s1i}) >>> 1;
    assign y2r = ({s0r[15],s0r} - {s1r[15],s1r}) >>> 1;
    assign y2i = ({s0i[15],s0i} - {s1i[15],s1i}) >>> 1;
    assign y1r = ({d0r[15],d0r} + {tr[15],tr})    >>> 1;
    assign y1i = ({d0i[15],d0i} + {ti[15],ti})    >>> 1;
    assign y3r = ({d0r[15],d0r} - {tr[15],tr})    >>> 1;
    assign y3i = ({d0i[15],d0i} - {ti[15],ti})    >>> 1;
endmodule
