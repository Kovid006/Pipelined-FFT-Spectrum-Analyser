#!/usr/bin/env python3
"""
Bit-accurate 256-point radix-2^2 SDF (DIF) fixed-point FFT golden model (Q1.15)
===============================================================================

Architecture being modelled (matches the P10 brief):
    - 8 radix-2 stages grouped into 4 radix-2^2 modules.
    - Each module = BF2I -> BF2II (trivial -j) -> twiddle multiplier.
      The last module (L = 4) has no multiplier, so the design has 3 complex
      multipliers (9 real multipliers with the 4->3 transformation).
    - Natural-order input, BIT-REVERSED output (this is what the SDF streams
      out; the ping-pong buffer does the bit-reversed read-out).
    - 1/2 scaling after every butterfly stage (8 stages -> total 1/256).
    - Twiddles that are exactly 1, -j, -1, +j bypass the multiplier
      (trivial-twiddle detection), so they are exact.

Per-module dataflow for a block of length L, quarters x0..x3 (spacing L/4):
    BF2I : s0 = x0 + x2   d0 = x0 - x2   s1 = x1 + x3   d1 = x1 - x3      (>>1)
    BF2II: y0 = s0 + s1   y2 = s0 - s1   y1 = d0 + (-j)d1   y3 = d0 - (-j)d1 (>>1)
    TWID : y1 *= W_L^n    y2 *= W_L^2n   y3 *= W_L^3n      (n = 0 .. L/4-1)
    Block order after the module: [y0 | y2 | y1 | y3], each L/4 long, and each
    sub-block is processed recursively by the next module.

Reuses helpers from the radix-2 baseline (fft_golden.py, same folder).
"""

import os
import numpy as np

from fft_golden import (float_to_q15, q15_to_float, to_hex32, bit_reverse_indices,
                        compute_sqnr, fft_reference_float, fft_256_fixed,
                        Q15_MIN, Q15_MAX)

N = 256
MODULES = 4

# ------------------------------------------------------------------------------
# Twiddle ROM (full 256-entry table; hardware can fold this to a quarter wave,
# which gives identical values because sin(x) = cos(pi/2 - x) is quantized the
# same way). Entries at multiples of 64 are never used by the multiplier.
# ------------------------------------------------------------------------------
_W = np.exp(-2j * np.pi * np.arange(N) / N)
TW_R = float_to_q15(_W.real).astype(np.int64)
TW_I = float_to_q15(_W.imag).astype(np.int64)


def _shr1(x, rnd):
    """Divide by 2: floor (trunc) or round-half-up (add 1 before the shift)."""
    return (x + 1) >> 1 if rnd else x >> 1


def _sat(x):
    return np.clip(x, Q15_MIN, Q15_MAX)


def cmul_q15(br, bi, wr, wi, rnd=False, three_mult=False):
    """
    Q1.15 complex multiply B*W, returns pre-saturation Q1.15 integers.
    three_mult=True uses the 4->3 real-multiplier form; with full-width
    intermediates it is mathematically identical to the 4-multiplier form.
        k1 = wr*(br+bi)   k2 = br*(wi-wr)   k3 = bi*(wr+wi)
        re = k1 - k3      im = k1 + k2
    """
    if three_mult:
        k1 = wr * (br + bi)
        k2 = br * (wi - wr)
        k3 = bi * (wr + wi)
        acc_r, acc_i = k1 - k3, k1 + k2
    else:
        acc_r = br * wr - bi * wi
        acc_i = br * wi + bi * wr
    if rnd:
        acc_r = acc_r + (1 << 14)
        acc_i = acc_i + (1 << 14)
    return acc_r >> 15, acc_i >> 15


def _twiddle_rows(y_r, y_i, L, rnd, three_mult, stats):
    """Apply the module's twiddle multiplier to rows [y0, y2, y1, y3]."""
    Q = L // 4
    stride = N // L
    n = np.arange(Q)
    # row -> twiddle multiple of n:  y2 -> 2n, y1 -> 1n, y3 -> 3n
    for row, mult in ((1, 2), (2, 1), (3, 3)):
        e = (mult * n * stride) % N          # exponent of W_256
        triv = (e % 64) == 0                 # W in {1, -j, -1, +j}
        xr, xi = y_r[:, row, :], y_i[:, row, :]

        tr, ti = cmul_q15(xr, xi, TW_R[e], TW_I[e], rnd, three_mult)
        over = (tr > Q15_MAX) | (tr < Q15_MIN) | (ti > Q15_MAX) | (ti < Q15_MIN)
        stats['saturations'] += int(np.sum(over & ~triv))
        tr, ti = _sat(tr), _sat(ti)

        # exact bypass for trivial twiddles
        conds = [e == 0, e == 64, e == 128, e == 192]
        ex_r = np.select(conds, [xr, xi, -xr, -xi])
        ex_i = np.select(conds, [xi, -xr, -xi, xr])
        tr = np.where(triv, _sat(ex_r), tr)
        ti = np.where(triv, _sat(ex_i), ti)

        y_r[:, row, :], y_i[:, row, :] = tr, ti
        nblk = xr.shape[0]
        stats['mult_nontrivial'] += int(np.sum(~triv)) * nblk
        stats['mult_bypassed'] += int(np.sum(triv)) * nblk


def fft_256_r22(xr_in, xi_in=None, round_mode='trunc', three_mult=False):
    """
    Bit-accurate radix-2^2 SDF FFT.
    Returns dict with:
        stream_real/imag : int16, in SDF output order (bit-reversed)
        real/imag        : int16, natural order (bit-reversal applied)
        complex_float    : natural-order output / 32768
        stage_history    : list of (re, im) int arrays, one per radix-2 stage,
                           in SDF stream order (after BF2I and after BF2II+twiddle)
        stats            : multiplier / bypass / saturation counts
    """
    rnd = (round_mode == 'round')

    def _as_q15(a):
        a = np.asarray(a)
        return float_to_q15(a) if np.issubdtype(a.dtype, np.floating) else a.astype(np.int16)

    xr = _as_q15(xr_in).astype(np.int64)
    xi = np.zeros(N, np.int64) if xi_in is None else _as_q15(xi_in).astype(np.int64)
    assert len(xr) == N and len(xi) == N

    stats = {'mult_nontrivial': 0, 'mult_bypassed': 0, 'saturations': 0}
    hist = []
    re, im = xr.copy(), xi.copy()

    for m in range(MODULES):
        L = N >> (2 * m)
        Q = L // 4
        r = re.reshape(-1, 4, Q)
        i = im.reshape(-1, 4, Q)
        x0r, x1r, x2r, x3r = r[:, 0], r[:, 1], r[:, 2], r[:, 3]
        x0i, x1i, x2i, x3i = i[:, 0], i[:, 1], i[:, 2], i[:, 3]

        # ---- BF2I (stage 2m): no twiddle, scale by 1/2 --------------------
        s0r, s0i = _shr1(x0r + x2r, rnd), _shr1(x0i + x2i, rnd)
        d0r, d0i = _shr1(x0r - x2r, rnd), _shr1(x0i - x2i, rnd)
        s1r, s1i = _shr1(x1r + x3r, rnd), _shr1(x1i + x3i, rnd)
        d1r, d1i = _shr1(x1r - x3r, rnd), _shr1(x1i - x3i, rnd)
        hist.append((np.stack([s0r, s1r, d0r, d1r], 1).reshape(-1),
                     np.stack([s0i, s1i, d0i, d1i], 1).reshape(-1)))

        # ---- BF2II (stage 2m+1): trivial -j on d1, scale by 1/2 -----------
        tr_, ti_ = d1i, -d1r                       # (-j) * d1
        y0r, y0i = _shr1(s0r + s1r, rnd), _shr1(s0i + s1i, rnd)
        y2r, y2i = _shr1(s0r - s1r, rnd), _shr1(s0i - s1i, rnd)
        y1r, y1i = _shr1(d0r + tr_, rnd), _shr1(d0i + ti_, rnd)
        y3r, y3i = _shr1(d0r - tr_, rnd), _shr1(d0i - ti_, rnd)

        yr = np.stack([y0r, y2r, y1r, y3r], 1)      # block order [y0|y2|y1|y3]
        yi = np.stack([y0i, y2i, y1i, y3i], 1)

        # ---- twiddle multiplier (none after the last module) --------------
        if L > 4:
            _twiddle_rows(yr, yi, L, rnd, three_mult, stats)

        re, im = yr.reshape(-1), yi.reshape(-1)
        hist.append((re.copy(), im.copy()))

    stream_r, stream_i = re.astype(np.int16), im.astype(np.int16)
    rev = bit_reverse_indices(N)
    nat_r, nat_i = stream_r[rev], stream_i[rev]
    return {
        'stream_real': stream_r, 'stream_imag': stream_i,
        'real': nat_r, 'imag': nat_i,
        'complex_float': (nat_r.astype(np.float64) + 1j * nat_i) / 32768.0,
        'stage_history': hist, 'stats': stats,
    }


# ------------------------------------------------------------------------------
# Float structural check (proves the radix-2^2 decomposition itself is right)
# ------------------------------------------------------------------------------
def fft_r22_float(x):
    x = np.asarray(x, dtype=np.complex128).copy()
    for m in range(MODULES):
        L = N >> (2 * m)
        Q = L // 4
        a = x.reshape(-1, 4, Q)
        s0, d0 = a[:, 0] + a[:, 2], a[:, 0] - a[:, 2]
        s1, d1 = a[:, 1] + a[:, 3], a[:, 1] - a[:, 3]
        t = -1j * d1
        n, st = np.arange(Q), N // L
        y = np.stack([s0 + s1,
                      (s0 - s1) * _W[(2 * n * st) % N],
                      (d0 + t) * _W[(n * st) % N],
                      (d0 - t) * _W[(3 * n * st) % N]], axis=1)
        x = y.reshape(-1)
    return x[bit_reverse_indices(N)]


# ------------------------------------------------------------------------------
# Magnitude approximation + peak finder (reference for the RV32 / VGA path)
# ------------------------------------------------------------------------------
def mag_approx(re, im):
    """|z| ~ max + 3/8*min  (shifts and adds only; max/min select = the BDD block)."""
    a = np.abs(np.asarray(re, dtype=np.int64))
    b = np.abs(np.asarray(im, dtype=np.int64))
    hi, lo = np.maximum(a, b), np.minimum(a, b)
    return hi + (lo >> 2) + (lo >> 3)


def find_peak(mag):
    """Dominant bin of a real-input spectrum: search bins 1..N/2-1 (skip DC)."""
    return 1 + int(np.argmax(mag[1:N // 2]))


# ------------------------------------------------------------------------------
# Test signals, SQNR comparison, vector export
# ------------------------------------------------------------------------------
def make_signals():
    n = np.arange(N)
    rng = np.random.default_rng(42)
    return {
        'single_tone': 0.85 * np.cos(2 * np.pi * 32 * n / N),
        'two_tone':    0.45 * np.cos(2 * np.pi * 32 * n / N) + 0.45 * np.cos(2 * np.pi * 96 * n / N),
        'noise':       np.clip(rng.normal(0, 0.22, N), -0.95, 0.95),      # real-valued
        'offbin_tone': 0.85 * np.cos(2 * np.pi * 40.37 * n / N),          # non-coherent
    }


def export_vectors(out_dir, tag, in_r, in_i, res):
    os.makedirs(out_dir, exist_ok=True)

    def dump(name, r, i, note):
        with open(os.path.join(out_dir, f"{tag}_{name}.hex"), 'w') as f:
            f.write(f"// {note}; [31:16]=imag, [15:0]=real (Q1.15)\n")
            for k in range(N):
                f.write(to_hex32(i[k], r[k]) + "\n")

    dump('input', in_r, in_i, 'input, natural order')
    dump('expected_stream', res['stream_real'], res['stream_imag'], 'expected SDF output, bit-reversed order')
    dump('expected_natural', res['real'], res['imag'], 'expected output after bit-reversed read-out')


def run_r22_tests(out_dir=None):
    if out_dir is None:
        out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data_r22")

    # 1) algorithm check in floating point
    rng = np.random.default_rng(0)
    z = rng.normal(size=N) + 1j * rng.normal(size=N)
    err = np.max(np.abs(fft_r22_float(z) - np.fft.fft(z)))
    print(f"float radix-2^2 structure vs np.fft.fft: max |err| = {err:.2e}")
    assert err < 1e-9

    # 2) fixed-point SQNR: radix-2 baseline vs radix-2^2
    print(f"\n{'signal':<12}{'r2 trunc':>10}{'r22 trunc':>11}{'r22 round':>11}{'peak':>6}")
    for key, x in make_signals().items():
        in_r = float_to_q15(x)
        in_i = np.zeros(N, np.int16)
        ref = fft_reference_float(q15_to_float(in_r) + 0j, scale_by_n=True)

        base = fft_256_fixed(in_r, in_i, 'trunc')
        a = fft_256_r22(in_r, in_i, 'trunc', three_mult=False)
        b = fft_256_r22(in_r, in_i, 'trunc', three_mult=True)
        c = fft_256_r22(in_r, in_i, 'round')

        assert np.array_equal(a['real'], b['real']) and np.array_equal(a['imag'], b['imag']), \
            "4-mult and 3-mult results must be bit-identical"

        s = lambda o: compute_sqnr(ref, o['complex_float'])
        pk = find_peak(mag_approx(a['real'], a['imag']))
        print(f"{key:<12}{s(base):>9.1f} {s(a):>10.1f} {s(c):>10.1f}{pk:>6}")
        export_vectors(out_dir, key, in_r, in_i, a)

    st = a['stats']
    print(f"\nmultiplier usage per FFT: {st['mult_nontrivial']} non-trivial complex mults, "
          f"{st['mult_bypassed']} bypassed (trivial twiddle), {st['saturations']} saturations")
    print(f"vectors written to {out_dir}")


if __name__ == '__main__':
    run_r22_tests()
