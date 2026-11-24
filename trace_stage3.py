#!/usr/bin/env python3
"""
Trace Stage 3 input vs output to find where the 4-sample shift occurs.
Specifically: what should Stage 3 receive at its inputs at samples 20-27?
And what does the hardware compute as Stage 2 output?
"""

import sys, os
import numpy as np

script_dir = os.path.dirname(os.path.abspath(__file__))
root_dir   = os.path.dirname(script_dir)
sys.path.insert(0, script_dir)
sys.path.insert(0, root_dir)

from fft_golden import float_to_q15, to_hex32, bit_reverse_indices, Q15_MIN, Q15_MAX
from fft_r22_golden import make_signals, N, _shr1, _sat

_W = np.exp(-2j * np.pi * np.arange(N) / N)
TW_R = float_to_q15(_W.real).astype(np.int64)
TW_I = float_to_q15(_W.imag).astype(np.int64)

MODULES = 4

def apply_twiddles(yr, yi, L):
    Q = L // 4
    stride = N // L
    for row, mult in ((1, 2), (2, 1), (3, 3)):
        n = np.arange(Q)
        e = (mult * n * stride) % N
        triv = (e % 64) == 0
        xr, xi = yr[:, row, :], yi[:, row, :]
        tr = np.clip((xr * TW_R[e] - xi * TW_I[e]) >> 15, Q15_MIN, Q15_MAX)
        ti = np.clip((xr * TW_I[e] + xi * TW_R[e]) >> 15, Q15_MIN, Q15_MAX)
        conds = [e == 0, e == 64, e == 128, e == 192]
        ex_r = np.select(conds, [xr, xi, -xr, -xi])
        ex_i = np.select(conds, [xi, -xr, -xi, xr])
        yr[:, row, :] = np.where(triv, np.clip(ex_r, Q15_MIN, Q15_MAX), tr)
        yi[:, row, :] = np.where(triv, np.clip(ex_i, Q15_MIN, Q15_MAX), ti)

signals = make_signals()
x = signals['noise']
in_r = float_to_q15(x).astype(np.int64)
in_i = np.zeros(N, np.int64)
re, im = in_r.copy(), in_i.copy()

for m in range(MODULES):
    L = N >> (2 * m)
    Q = L // 4
    nblk = N // L
    
    r = re.reshape(nblk, 4, Q)
    i = im.reshape(nblk, 4, Q)
    x0r, x1r, x2r, x3r = r[:, 0], r[:, 1], r[:, 2], r[:, 3]
    x0i, x1i, x2i, x3i = i[:, 0], i[:, 1], i[:, 2], i[:, 3]
    
    s0r = _shr1(x0r + x2r, False); s0i = _shr1(x0i + x2i, False)
    d0r = _shr1(x0r - x2r, False); d0i = _shr1(x0i - x2i, False)
    s1r = _shr1(x1r + x3r, False); s1i = _shr1(x1i + x3i, False)
    d1r = _shr1(x1r - x3r, False); d1i = _shr1(x1i - x3i, False)
    
    tr_ = d1i; ti_ = -d1r
    y0r = _shr1(s0r + s1r, False); y0i = _shr1(s0i + s1i, False)
    y2r = _shr1(s0r - s1r, False); y2i = _shr1(s0i - s1i, False)
    y1r = _shr1(d0r + tr_, False); y1i = _shr1(d0i + ti_, False)
    y3r = _shr1(d0r - tr_, False); y3i = _shr1(d0i - ti_, False)
    
    yr = np.stack([y0r, y2r, y1r, y3r], axis=1)
    yi = np.stack([y0i, y2i, y1i, y3i], axis=1)
    
    if m == 2:  # Stage 2 output = Stage 3 input (before cmul2)
        stage2_out_r = yr.reshape(-1).astype(np.int16)
        stage2_out_i = yi.reshape(-1).astype(np.int16)
        
        print(f"Stage 2 (L=16, Q=4) output stream (what Stage 3 should receive):")
        print(f"Block structure: {nblk} blocks of L=16, each outputs [y0[4], y2[4], y1[4], y3[4]]")
        print()
        for k in range(32):
            blk = k // 16
            pos_in_blk = k % 16
            sub = pos_in_blk // 4
            q_idx = pos_in_blk % 4
            sub_names = ['y0', 'y2', 'y1', 'y3']
            print(f"  Stage2_out[{k:3d}] (blk{blk} {sub_names[sub]}[{q_idx}]): "
                  f"({stage2_out_r[k]:6d}, {stage2_out_i[k]:6d})")
        
        print()
        print("Stage 3 blocks (each 4 samples = one L=4 block):")
        for blk3 in range(8):
            start = blk3 * 4
            print(f"  Stage3 block {blk3} = Stage2_out[{start}..{start+3}]: "
                  f"{[(int(stage2_out_r[start+j]), int(stage2_out_i[start+j])) for j in range(4)]}")
    
    if L > 4:
        apply_twiddles(yr, yi, L)
    
    re = yr.reshape(-1).astype(np.int64)
    im = yi.reshape(-1).astype(np.int64)

# Final output (what Stage 3 produces)
final_r = re.astype(np.int16)
final_i = im.astype(np.int16)
print()
print("Stage 3 output stream (final FFT stream, bins 0-31):")
for k in range(32):
    print(f"  out[{k:3d}]: ({final_r[k]:6d}, {final_i[k]:6d})")
