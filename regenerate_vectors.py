#!/usr/bin/env python3
"""
Regenerate all test vectors from scratch using the bit-accurate golden model.
Writes to tb/vectors/ so the testbench picks them up directly.

The hardware SDF pipeline streams out samples in BIT-REVERSED order.
The testbench compares against `noise_expected_sdf.hex` which must hold
the BIT-REVERSED (stream) order exactly matching what the RTL outputs.
"""

import sys, os
import numpy as np

# Locate repo root
script_dir = os.path.dirname(os.path.abspath(__file__))
root_dir   = os.path.dirname(script_dir)
sys.path.insert(0, script_dir)
sys.path.insert(0, root_dir)

from fft_golden import (float_to_q15, q15_to_float, to_hex32, bit_reverse_indices,
                        Q15_MIN, Q15_MAX)
from fft_r22_golden import fft_256_r22, make_signals, N

OUT_DIR = os.path.join(root_dir, 'tb', 'vectors')
os.makedirs(OUT_DIR, exist_ok=True)

def dump_hex(path, r_arr, i_arr, comment):
    with open(path, 'w') as f:
        f.write(f'// {comment}  [31:16]=imag [15:0]=real\n')
        for k in range(N):
            f.write(to_hex32(int(i_arr[k]), int(r_arr[k])) + '\n')
    print(f'  wrote {path}')

signals = make_signals()

for tag, x in signals.items():
    if tag not in ('single_tone', 'two_tone', 'noise'):
        continue

    in_r = float_to_q15(x).astype(np.int64)
    in_i = np.zeros(N, np.int64)

    res = fft_256_r22(in_r, in_i, 'trunc', three_mult=False)

    # Input (natural order, real input so imag=0)
    dump_hex(os.path.join(OUT_DIR, f'{tag}_input.hex'),
             in_r, in_i, f'Input natural-order: {tag}')

    # Expected SDF stream order (this is what the RTL outputs)
    dump_hex(os.path.join(OUT_DIR, f'{tag}_expected_sdf.hex'),
             res['stream_real'], res['stream_imag'],
             f'Expected SDF output: {tag}')

    # Expected natural order (after bit-reversal)
    dump_hex(os.path.join(OUT_DIR, f'{tag}_expected_nat.hex'),
             res['real'], res['imag'],
             f'Expected natural-order output: {tag}')

    # Print first 30 SDF-order bins for verification
    print(f'\n{tag} SDF stream order (bins 17-30):')
    for k in range(17, 30):
        print(f'  bin {k:3d}: ({res["stream_real"][k]:6d}, {res["stream_imag"][k]:6d})')

print('\nDone — all vectors regenerated.')
