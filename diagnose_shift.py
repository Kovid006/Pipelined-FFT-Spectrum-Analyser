#!/usr/bin/env python3
"""
Diagnose the 4-sample shift in NOISE output.

Theory: the hardware outputs in a DIFFERENT order than the golden model predicts.
Let's compute what the ACTUAL hardware output order should be by tracing
the sdf_stage output sequence through all 4 stages.

The sdf_stage outputs: for each block of L samples, it emits sub-blocks:
  [y0[0..Q-1], y2[0..Q-1], y1[0..Q-1], y3[0..Q-1]]

The golden model (fft_r22_golden.py) reshapes: yr = stack([y0, y2, y1, y3], axis=1)
Then re-shapes: re = yr.reshape(-1)
This interleaves as: y0[0],y2[0],y1[0],y3[0], y0[1],y2[1],y1[1],y3[1], ...
  (because stack(axis=1) gives shape (nblk, 4, Q), then reshape(-1) goes fastest on Q)

But the HARDWARE streams: y0[0..Q-1] contiguous, then y2[0..Q-1], then y1, then y3.
So the hardware output per block = y0[0],y0[1],...,y0[Q-1], y2[0],...,y2[Q-1], y1[0],...,y3[Q-1]

This is DIFFERENT from the golden model's reshape(-1) which interleaves!

Let me trace what the actual hardware stream order is.
"""

import sys, os
import numpy as np

script_dir = os.path.dirname(os.path.abspath(__file__))
root_dir   = os.path.dirname(script_dir)
sys.path.insert(0, script_dir)
sys.path.insert(0, root_dir)

from fft_golden import float_to_q15, to_hex32, bit_reverse_indices, Q15_MIN, Q15_MAX
from fft_r22_golden import make_signals, N, _shr1, _sat, cmul_q15

# Q1.15 twiddles
_W = np.exp(-2j * np.pi * np.arange(N) / N)
TW_R = float_to_q15(_W.real).astype(np.int64)
TW_I = float_to_q15(_W.imag).astype(np.int64)

MODULES = 4

def apply_twiddles(yr, yi, L):
    """Apply twiddle multipliers to [y0, y2, y1, y3] row arrangement."""
    Q = L // 4
    stride = N // L
    for row, mult in ((1, 2), (2, 1), (3, 3)):
        n = np.arange(Q)
        e = (mult * n * stride) % N
        triv = (e % 64) == 0
        xr, xi = yr[:, row, :], yi[:, row, :]
        
        tr = (xr * TW_R[e] - xi * TW_I[e]) >> 15
        ti = (xr * TW_I[e] + xi * TW_R[e]) >> 15
        tr, ti = np.clip(tr, Q15_MIN, Q15_MAX), np.clip(ti, Q15_MIN, Q15_MAX)
        
        # Exact bypass for trivial twiddles
        conds = [e == 0, e == 64, e == 128, e == 192]
        ex_r = np.select(conds, [xr, xi, -xr, -xi])
        ex_i = np.select(conds, [xi, -xr, -xi, xr])
        yr[:, row, :] = np.where(triv, np.clip(ex_r, Q15_MIN, Q15_MAX), tr)
        yi[:, row, :] = np.where(triv, np.clip(ex_i, Q15_MIN, Q15_MAX), ti)


def fft_256_r22_hw_stream(xr_in, xi_in=None):
    """
    Trace the FFT computing the EXACT hardware stream order.
    
    The hardware sdf_stage outputs sub-blocks contiguously:
      [y0[0..Q-1], y2[0..Q-1], y1[0..Q-1], y3[0..Q-1]]
    for each input block.
    
    So for stage m with n_blocks blocks of Q samples each:
      hardware_stream = [y0_blk0, y2_blk0, y1_blk0, y3_blk0,
                         y0_blk1, y2_blk1, y1_blk1, y3_blk1, ...]
    which in numpy is: stack([y0,y2,y1,y3], axis=1).reshape(-1)  -- same as golden!
    
    Wait... stack(axis=1) gives (nblk, 4, Q).reshape(-1) goes in order:
      blk0_y0[0], blk0_y0[1]... blk0_y0[Q-1],
      blk0_y2[0]... blk0_y2[Q-1],
      blk0_y1[0]... blk0_y1[Q-1],
      blk0_y3[0]... blk0_y3[Q-1],
      blk1_y0[0]...
    
    That IS contiguous sub-blocks! So the golden model stream order = hardware stream order.
    
    Then why the 4-sample shift? Let me check the actual stage-by-stage pass-through.
    """
    rnd = False
    re = np.asarray(xr_in, np.int64).copy()
    im = np.zeros(N, np.int64) if xi_in is None else np.asarray(xi_in, np.int64).copy()
    
    stage_outputs = []  # (stream_r, stream_i) after each module
    
    for m in range(MODULES):
        L = N >> (2 * m)
        Q = L // 4
        nblk = N // L  # number of blocks at this stage's input
        
        r = re.reshape(nblk, 4, Q)
        i = im.reshape(nblk, 4, Q)
        x0r, x1r, x2r, x3r = r[:, 0], r[:, 1], r[:, 2], r[:, 3]
        x0i, x1i, x2i, x3i = i[:, 0], i[:, 1], i[:, 2], i[:, 3]
        
        # BF2I
        s0r = _shr1(x0r + x2r, rnd); s0i = _shr1(x0i + x2i, rnd)
        d0r = _shr1(x0r - x2r, rnd); d0i = _shr1(x0i - x2i, rnd)
        s1r = _shr1(x1r + x3r, rnd); s1i = _shr1(x1i + x3i, rnd)
        d1r = _shr1(x1r - x3r, rnd); d1i = _shr1(x1i - x3i, rnd)
        
        # BF2II
        tr_ = d1i; ti_ = -d1r
        y0r = _shr1(s0r + s1r, rnd); y0i = _shr1(s0i + s1i, rnd)
        y2r = _shr1(s0r - s1r, rnd); y2i = _shr1(s0i - s1i, rnd)
        y1r = _shr1(d0r + tr_, rnd); y1i = _shr1(d0i + ti_, rnd)
        y3r = _shr1(d0r - tr_, rnd); y3i = _shr1(d0i - ti_, rnd)
        
        yr = np.stack([y0r, y2r, y1r, y3r], axis=1)  # (nblk, 4, Q)
        yi = np.stack([y0i, y2i, y1i, y3i], axis=1)
        
        # Twiddle
        if L > 4:
            apply_twiddles(yr, yi, L)
        
        # Hardware stream from this stage: yr.reshape(-1) in block-major order
        hw_stream_r = yr.reshape(-1).astype(np.int16)
        hw_stream_i = yi.reshape(-1).astype(np.int16)
        stage_outputs.append((hw_stream_r.copy(), hw_stream_i.copy()))
        
        re = yr.reshape(-1).astype(np.int64)
        im = yi.reshape(-1).astype(np.int64)
    
    return stage_outputs, re.astype(np.int16), im.astype(np.int16)


if __name__ == '__main__':
    signals = make_signals()
    x = signals['noise']
    in_r = float_to_q15(x).astype(np.int64)
    in_i = np.zeros(N, np.int64)
    
    stage_outs, final_r, final_i = fft_256_r22_hw_stream(in_r, in_i)
    
    print("Final stage output (what hardware streams, bins 17-30):")
    for k in range(17, 30):
        print(f"  hw stream bin {k:3d}: ({final_r[k]:6d}, {final_i[k]:6d})")
    
    print()
    # Apply bit-reversal to get natural order
    rev = bit_reverse_indices(N)
    nat_r = final_r[rev]
    nat_i = final_i[rev]
    print("Natural order (after bit-reversal of hw stream, bins 17-30):")
    for k in range(17, 30):
        print(f"  nat bin {k:3d}: ({nat_r[k]:6d}, {nat_i[k]:6d})")
    
    # Load current expected_sdf.hex to compare
    print()
    print("Current noise_expected_sdf.hex bins 17-30:")
    with open(os.path.join(root_dir, 'tb', 'vectors', 'noise_expected_sdf.hex')) as f:
        lines = [l.strip() for l in f if not l.startswith('//')]
    for k in range(17, 30):
        h = lines[k]
        def h2s(x):
            v = int(x, 16)
            return v - 65536 if v >= 32768 else v
        r_ = h2s(h[4:8]); i_ = h2s(h[0:4])
        match = "✓" if (r_ == final_r[k] and i_ == final_i[k]) else "✗"
        print(f"  bin {k:3d}: ({r_:6d}, {i_:6d})  hw:({final_r[k]:6d},{final_i[k]:6d}) {match}")
