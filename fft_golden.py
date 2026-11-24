#!/usr/bin/env python3
"""
Bit-Accurate 256-Point Radix-2 DIT Fixed-Point FFT Golden Model
================================================================

This module implements a bit-accurate 256-point Radix-2 Decimation-in-Time (DIT)
Fast Fourier Transform (FFT) in Q1.15 fixed-point format, matching hardware RTL
implementation targets (e.g. FPGA DSP slices and block RAMs).

Key Features:
-------------
- Format: Q1.15 fixed-point (16-bit signed, range [-1.0, +1.0 - 2^-15])
- Scaling: Per-stage right shift by 1 after each butterfly (total scale = 1/256)
- Twiddles: Computed and quantized to Q1.15
- Comparison: Compared with double-precision numpy.fft.fft
- Metric: Signal-to-Quantization-Noise Ratio (SQNR) in dB:
            SQNR = 10 * log10(signal_power / noise_power)
- Hardware Debug: Provides intermediate stage outputs for RTL step-by-step verification
- File Generation: Exports RTL expected output vectors ($readmemh format)

Author: FPGA DSP RTL Design Engineer
"""

import os
import sys
import numpy as np
import matplotlib.pyplot as plt

# ==============================================================================
# Fixed-Point Helper Functions (Q1.15)
# ==============================================================================

Q15_MIN = -32768
Q15_MAX = 32767
Q15_SCALE = 32768.0


def float_to_q15(x: np.ndarray) -> np.ndarray:
    """
    Convert floating point array to Q1.15 signed 16-bit integers.
    Saturates to [-32768, 32767].
    """
    scaled = np.round(np.asarray(x, dtype=np.float64) * Q15_SCALE)
    clipped = np.clip(scaled, Q15_MIN, Q15_MAX)
    return clipped.astype(np.int16)


def q15_to_float(x: np.ndarray) -> np.ndarray:
    """
    Convert Q1.15 signed 16-bit integers to floating point numbers.
    """
    return np.asarray(x, dtype=np.float64) / Q15_SCALE


def to_hex32(imag_q15: int, real_q15: int) -> str:
    """
    Pack 16-bit imaginary and 16-bit real Q1.15 into a 32-bit hex string:
    [31:16] = imag, [15:0] = real.
    """
    u_imag = int(imag_q15) & 0xFFFF
    u_real = int(real_q15) & 0xFFFF
    val32 = (u_imag << 16) | u_real
    return f"{val32:08X}"


def to_hex16(val_q15: int) -> str:
    """Convert 16-bit signed integer to 4-character hex string."""
    return f"{int(val_q15) & 0xFFFF:04X}"


def from_hex16(hex_str: str) -> int:
    """Convert 4-character hex string to 16-bit signed integer."""
    val = int(hex_str, 16)
    if val >= 0x8000:
        val -= 0x10000
    return val


def bit_reverse(val: int, bits: int = 8) -> int:
    """Reverse the bit ordering of an integer within `bits` width."""
    res = 0
    for _ in range(bits):
        res = (res << 1) | (val & 1)
        val >>= 1
    return res


def bit_reverse_indices(n_points: int = 256) -> np.ndarray:
    """Generate array of bit-reversed indices for length n_points."""
    bits = int(np.log2(n_points))
    return np.array([bit_reverse(i, bits) for i in range(n_points)], dtype=np.int32)


# ==============================================================================
# Twiddle Factor Generation
# ==============================================================================

def compute_twiddles(n_points: int = 256):
    """
    Compute complex twiddle factors W_N^k = exp(-j * 2 * pi * k / N).
    Returns:
        twiddle_float: complex128 array of length n_points // 2
        twiddle_re_q15: int16 array of real parts
        twiddle_im_q15: int16 array of imaginary parts
    """
    k = np.arange(n_points // 2)
    theta = -2.0 * np.pi * k / n_points
    twiddle_float = np.cos(theta) + 1j * np.sin(theta)

    twiddle_re_q15 = float_to_q15(np.real(twiddle_float))
    twiddle_im_q15 = float_to_q15(np.imag(twiddle_float))

    return twiddle_float, twiddle_re_q15, twiddle_im_q15


# ==============================================================================
# Bit-Accurate Radix-2 Complex Multiplier and Butterfly
# ==============================================================================

def complex_mult_q15(br: int, bi: int, wr: int, wi: int, round_mode: str = 'trunc') -> tuple:
    """
    Bit-accurate Q1.15 complex multiplication: T = B * W
    T_r = (br * wr - bi * wi) >> 15
    T_i = (br * wi + bi * wr) >> 15

    Parameters:
        br, bi: Real and Imaginary parts of B (int16 range)
        wr, wi: Real and Imaginary parts of W (int16 range)
        round_mode: 'trunc' for standard arithmetic shift right (>> 15)
                    'round' for convergent/nearest rounding (+ 0x4000 >> 15)

    Returns:
        (tr, ti): Q1.15 integers saturated to [-32768, 32767]
    """
    # 32-bit products (Q2.30)
    p_rr = int(br) * int(wr)
    p_ii = int(bi) * int(wi)
    p_ri = int(br) * int(wi)
    p_ir = int(bi) * int(wr)

    # Accumulator (33-bit signed in hardware)
    acc_r = p_rr - p_ii
    acc_i = p_ri + p_ir

    if round_mode == 'round':
        acc_r += 0x4000
        acc_i += 0x4000

    # Arithmetic right shift by 15 to return to Q1.15
    tr = acc_r >> 15
    ti = acc_i >> 15

    # Saturation in case of transient +1.0 * +1.0 edge cases
    tr = max(Q15_MIN, min(Q15_MAX, tr))
    ti = max(Q15_MIN, min(Q15_MAX, ti))

    return tr, ti


def butterfly_q15(ar: int, ai: int, br: int, bi: int, wr: int, wi: int,
                  scale: bool = True, round_mode: str = 'trunc') -> tuple:
    """
    Execute one Radix-2 DIT Butterfly:
    Upper: A' = (A + B * W) / 2
    Lower: B' = (A - B * W) / 2

    Parameters:
        ar, ai: Upper input Q1.15
        br, bi: Lower input Q1.15
        wr, wi: Twiddle factor Q1.15
        scale: If True, right shift by 1 (per-stage scaling)
        round_mode: 'trunc' or 'round'

    Returns:
        (a_next_r, a_next_i, b_next_r, b_next_i) in Q1.15
    """
    tr, ti = complex_mult_q15(br, bi, wr, wi, round_mode=round_mode)

    sum_r = int(ar) + tr
    sum_i = int(ai) + ti
    diff_r = int(ar) - tr
    diff_i = int(ai) - ti

    if scale:
        if round_mode == 'round':
            sum_r += 1 if sum_r >= 0 else 0
            sum_i += 1 if sum_i >= 0 else 0
            diff_r += 1 if diff_r >= 0 else 0
            diff_i += 1 if diff_i >= 0 else 0

        # Hardware arithmetic shift right by 1
        a_next_r = sum_r >> 1
        a_next_i = sum_i >> 1
        b_next_r = diff_r >> 1
        b_next_i = diff_i >> 1
    else:
        a_next_r = sum_r
        a_next_i = sum_i
        b_next_r = diff_r
        b_next_i = diff_i

    # Saturate to 16 bits signed
    a_next_r = max(Q15_MIN, min(Q15_MAX, a_next_r))
    a_next_i = max(Q15_MIN, min(Q15_MAX, a_next_i))
    b_next_r = max(Q15_MIN, min(Q15_MAX, b_next_r))
    b_next_i = max(Q15_MIN, min(Q15_MAX, b_next_i))

    return a_next_r, a_next_i, b_next_r, b_next_i


# ==============================================================================
# Complete 256-Point Fixed-Point FFT Core
# ==============================================================================

def fft_256_fixed(xr_in: np.ndarray, xi_in: np.ndarray = None,
                  round_mode: str = 'trunc', scale_stages: bool = True) -> dict:
    """
    Bit-accurate 256-point Radix-2 DIT FFT in Q1.15 fixed point.

    Parameters:
        xr_in: Real input array (length 256), in Q1.15 int16 or float in [-1, 1]
        xi_in: Imaginary input array (length 256). Defaults to zeros if None.
        round_mode: 'trunc' (RTL simple shift) or 'round' (nearest round)
        scale_stages: If True, scale by 1/2 at each of the 8 stages (total 1/256).

    Returns:
        dict containing:
            'real': int16 numpy array of output real components
            'imag': int16 numpy array of output imag components
            'complex_q15': complex array (real + 1j*imag) as integers
            'complex_float': output normalized to float [-1.0, 1.0]
            'magnitude': float array of complex magnitude
            'stage_history': list of intermediate arrays after each stage (for RTL debug)
    """
    n_points = 256
    n_stages = int(np.log2(n_points))  # 8 stages

    # Convert inputs to int16 Q1.15 if provided as floats
    if np.issubdtype(np.asarray(xr_in).dtype, np.floating):
        xr = float_to_q15(xr_in)
    else:
        xr = np.asarray(xr_in, dtype=np.int16).copy()

    if xi_in is None:
        xi = np.zeros(n_points, dtype=np.int16)
    elif np.issubdtype(np.asarray(xi_in).dtype, np.floating):
        xi = float_to_q15(xi_in)
    else:
        xi = np.asarray(xi_in, dtype=np.int16).copy()

    assert len(xr) == n_points and len(xi) == n_points, "Input length must be 256"

    # Precompute Q1.15 twiddle factors
    _, tw_r, tw_i = compute_twiddles(n_points)

    # 1. Bit-Reversal Permutation
    rev_idx = bit_reverse_indices(n_points)
    buf_r = xr[rev_idx].astype(np.int32)
    buf_i = xi[rev_idx].astype(np.int32)

    stage_history = []
    stage_history.append((buf_r.copy(), buf_i.copy()))

    # 2. 8 Butterfly Stages
    for stage in range(n_stages):
        sub_fft_len = 1 << (stage + 1)   # 2, 4, 8, ..., 256
        half_len = sub_fft_len >> 1       # 1, 2, 4, ..., 128
        tw_stride = n_points // sub_fft_len  # 128, 64, ..., 1

        next_r = buf_r.copy()
        next_i = buf_i.copy()

        for group in range(0, n_points, sub_fft_len):
            for k in range(half_len):
                u = group + k
                v = group + k + half_len

                tw_idx = k * tw_stride
                wr = int(tw_r[tw_idx])
                wi = int(tw_i[tw_idx])

                ar = buf_r[u]
                ai = buf_i[u]
                br = buf_r[v]
                bi = buf_i[v]

                a_next_r, a_next_i, b_next_r, b_next_i = butterfly_q15(
                    ar, ai, br, bi, wr, wi,
                    scale=scale_stages, round_mode=round_mode
                )

                next_r[u] = a_next_r
                next_i[u] = a_next_i
                next_r[v] = b_next_r
                next_i[v] = b_next_i

        buf_r = next_r
        buf_i = next_i
        stage_history.append((buf_r.copy(), buf_i.copy()))

    out_r = buf_r.astype(np.int16)
    out_i = buf_i.astype(np.int16)
    out_c_float = (out_r.astype(np.float64) + 1j * out_i.astype(np.float64)) / Q15_SCALE
    out_mag = np.abs(out_c_float)

    return {
        'real': out_r,
        'imag': out_i,
        'complex_q15': out_r.astype(np.float64) + 1j * out_i.astype(np.float64),
        'complex_float': out_c_float,
        'magnitude': out_mag,
        'stage_history': stage_history
    }


# ==============================================================================
# Reference Floating-Point Model & SQNR Computation
# ==============================================================================

def fft_reference_float(x_complex: np.ndarray, scale_by_n: bool = True) -> np.ndarray:
    """
    Double-precision reference FFT using numpy.fft.fft.
    Scaled by 1/256 to match the fixed-point per-stage divide-by-2 scaling.
    """
    n_points = len(x_complex)
    ref = np.fft.fft(x_complex)
    if scale_by_n:
        ref = ref / n_points
    return ref


def compute_sqnr(ref_complex: np.ndarray, test_complex: np.ndarray) -> float:
    """
    Compute Signal-to-Quantization-Noise Ratio (SQNR) in dB:
        SQNR = 10 * log10(signal_power / quantization_noise_power)

    Parameters:
        ref_complex: Floating-point reference output (scaled by 1/256)
        test_complex: Fixed-point model output converted to float

    Returns:
        sqnr_db: SQNR in decibels
    """
    noise = test_complex - ref_complex
    sig_power = np.mean(np.abs(ref_complex) ** 2)
    noise_power = np.mean(np.abs(noise) ** 2)

    if noise_power == 0:
        return float('inf')
    if sig_power == 0:
        return 0.0

    sqnr_db = 10.0 * np.log10(sig_power / noise_power)
    return float(sqnr_db)


# ==============================================================================
# Test Signals Generation
# ==============================================================================

def generate_test_signals(n_points: int = 256):
    """
    Generate standard verification test signals:
    1. Single tone at bin 32 (amplitude 0.8)
    2. Two-tone at bins 32 and 96 (amplitudes 0.4 and 0.4)
    3. Gaussian white noise (seed=42, RMS = 0.25)
    4. Linear Frequency Modulated Chirp (bin 4 to bin 60)
    5. Unit impulse at n = 0 (scaled to 0.9)
    """
    n = np.arange(n_points)
    signals = {}

    # 1. Single tone at bin 32
    f1 = 32
    amp1 = 0.85
    tone1 = amp1 * np.cos(2.0 * np.pi * f1 * n / n_points)
    signals['single_tone'] = {
        'name': 'Single Tone (Bin 32, Amp 0.85)',
        'data': tone1 + 0j,
        'description': 'Single sinusoidal tone centered exactly at FFT bin 32'
    }

    # 2. Two-tone at bins 32 and 96
    f2 = 96
    amp2 = 0.45
    tone2 = amp2 * np.cos(2.0 * np.pi * f1 * n / n_points) + amp2 * np.cos(2.0 * np.pi * f2 * n / n_points)
    signals['two_tone'] = {
        'name': 'Two-Tone (Bins 32 & 96, Amp 0.45 each)',
        'data': tone2 + 0j,
        'description': 'Dual-tone test for dynamic range and intermodulation'
    }

    # 3. Gaussian White Noise
    rng = np.random.default_rng(seed=42)
    noise_r = rng.normal(0, 0.22, n_points)
    noise_i = rng.normal(0, 0.22, n_points)
    # Clip to avoid saturation
    noise = np.clip(noise_r, -0.95, 0.95) + 1j * np.clip(noise_i, -0.95, 0.95)
    signals['gaussian_noise'] = {
        'name': 'White Gaussian Noise (seed=42)',
        'data': noise,
        'description': 'Broadband Gaussian noise signal for full spectrum excitation'
    }

    # 4. Chirp Signal
    k_chirp = (60.0 - 4.0) / n_points
    phase = 2.0 * np.pi * (4.0 * n + 0.5 * k_chirp * (n ** 2)) / n_points
    chirp = 0.8 * np.cos(phase) + 0j
    signals['chirp'] = {
        'name': 'Linear Chirp (Bins 4 to 60)',
        'data': chirp,
        'description': 'Swept-frequency chirp signal spanning low to mid frequencies'
    }

    # 5. Unit Impulse
    impulse = np.zeros(n_points, dtype=np.complex128)
    impulse[0] = 0.9 + 0j
    signals['impulse'] = {
        'name': 'Unit Impulse (n=0, Amp 0.9)',
        'data': impulse,
        'description': 'Impulse test for flat frequency response verification'
    }

    return signals


# ==============================================================================
# RTL Verification File Exporter
# ==============================================================================

def export_rtl_files(output_dir: str, signal_tag: str, in_q15_r: np.ndarray,
                     in_q15_i: np.ndarray, out_fixed: dict, out_ref_scaled: np.ndarray):
    """
    Export stimulus and expected output text files for Verilog testbenches.

    Files generated:
        - <tag>_input.hex: 32-bit hex per line [31:16]=Imag, [15:0]=Real ($readmemh format)
        - <tag>_expected.hex: 32-bit hex per line [31:16]=Imag, [15:0]=Real
        - <tag>_report.txt: Tabular format: Bin | Real_Q15 | Imag_Q15 | Mag_Float | Ref_Mag
    """
    os.makedirs(output_dir, exist_ok=True)
    n_points = len(in_q15_r)

    input_file = os.path.join(output_dir, f"{signal_tag}_input.hex")
    expected_file = os.path.join(output_dir, f"{signal_tag}_expected.hex")
    report_file = os.path.join(output_dir, f"{signal_tag}_report.txt")

    # 1. Write Input Hex ($readmemh)
    with open(input_file, 'w') as f:
        f.write(f"// Input Test Vector: {signal_tag}\n")
        f.write(f"// Format: 32-bit hex per line: [31:16]=Imag(Q1.15), [15:0]=Real(Q1.15)\n")
        for i in range(n_points):
            f.write(f"{to_hex32(in_q15_i[i], in_q15_r[i])}\n")

    # 2. Write Expected Output Hex ($readmemh)
    with open(expected_file, 'w') as f:
        f.write(f"// Expected FFT Output: {signal_tag}\n")
        f.write(f"// Format: 32-bit hex per line: [31:16]=Imag(Q1.15), [15:0]=Real(Q1.15)\n")
        for i in range(n_points):
            f.write(f"{to_hex32(out_fixed['imag'][i], out_fixed['real'][i])}\n")

    # 3. Write Detailed Verification Report
    with open(report_file, 'w') as f:
        f.write(f"# Verification Report: {signal_tag}\n")
        f.write(f"# Bin | Real_Hex | Imag_Hex | Real_Q15 | Imag_Q15 | Mag_Fixed | Mag_Float_Ref | Diff\n")
        for i in range(n_points):
            r_val = int(out_fixed['real'][i])
            i_val = int(out_fixed['imag'][i])
            m_fix = out_fixed['magnitude'][i]
            m_ref = np.abs(out_ref_scaled[i])
            diff = abs(m_fix - m_ref)
            f.write(f"{i:4d}   {to_hex16(r_val)}   {to_hex16(i_val)}   {r_val:7d}   {i_val:7d}   "
                    f"{m_fix:10.6f}   {m_ref:10.6f}   {diff:10.6f}\n")


# ==============================================================================
# Standalone Test Execution and Plotting
# ==============================================================================

def run_golden_tests(save_plots: bool = True, output_dir: str = None):
    """
    Execute golden model tests across all standard signals, compute SQNR,
    and generate expected verification files and plots.
    """
    if output_dir is None:
        base_dir = os.path.dirname(os.path.abspath(__file__))
        output_dir = os.path.join(base_dir, "data")

    os.makedirs(output_dir, exist_ok=True)
    plots_dir = os.path.join(output_dir, "plots")
    os.makedirs(plots_dir, exist_ok=True)

    print("=" * 80)
    print("   256-POINT RADIX-2 DIT FIXED-POINT FFT GOLDEN MODEL VERIFICATION")
    print("=" * 80)
    print(f"Data output directory: {output_dir}")
    print(f"Plots directory:       {plots_dir}\n")

    signals = generate_test_signals(256)
    results = {}

    for key, sig_info in signals.items():
        data = sig_info['data']
        name = sig_info['name']

        # Quantize inputs to Q1.15
        in_r = float_to_q15(np.real(data))
        in_i = float_to_q15(np.imag(data))

        # Fixed-point FFT execution
        out_fixed = fft_256_fixed(in_r, in_i, round_mode='trunc', scale_stages=True)

        # Double-precision reference (scaled by 1/256)
        in_float_quant = q15_to_float(in_r) + 1j * q15_to_float(in_i)
        out_ref = fft_reference_float(in_float_quant, scale_by_n=True)

        # Compute SQNR and Errors
        sqnr = compute_sqnr(out_ref, out_fixed['complex_float'])
        max_err = np.max(np.abs(out_fixed['complex_float'] - out_ref))
        rms_err = np.sqrt(np.mean(np.abs(out_fixed['complex_float'] - out_ref) ** 2))

        results[key] = {
            'name': name,
            'sqnr_db': sqnr,
            'max_err': max_err,
            'rms_err': rms_err,
            'out_fixed': out_fixed,
            'out_ref': out_ref
        }

        print(f"[*] Testcase: {name}")
        print(f"    - SQNR:       {sqnr:6.2f} dB")
        print(f"    - Max Error:  {max_err:8.6f} (scaled float)")
        print(f"    - RMS Error:  {rms_err:8.6f} (scaled float)")
        print(f"    - Max LSB:    {max_err * Q15_SCALE:6.2f} counts (out of 32768)")

        # Export RTL verification vectors
        export_rtl_files(output_dir, key, in_r, in_i, out_fixed, out_ref)
        print(f"    -> Exported stimulus & golden hex to {output_dir}\n")

    # Generate Summary Plot
    if save_plots:
        fig, axes = plt.subplots(len(signals), 2, figsize=(14, 3.2 * len(signals)))
        fig.suptitle("256-Point Fixed-Point FFT Golden Model vs Reference (NumPy)", fontsize=14, y=0.995)

        for idx, (key, res) in enumerate(results.items()):
            ax_spec = axes[idx, 0]
            ax_err = axes[idx, 1]

            k_bins = np.arange(256)
            fix_mag = res['out_fixed']['magnitude']
            ref_mag = np.abs(res['out_ref'])
            err = np.abs(res['out_fixed']['complex_float'] - res['out_ref'])

            # Spectrum Plot
            ax_spec.plot(k_bins, ref_mag, 'b-', label='NumPy Ref (Scaled 1/256)', alpha=0.7, linewidth=1.5)
            ax_spec.plot(k_bins, fix_mag, 'r--', label='Fixed-Point Q1.15', alpha=0.85, linewidth=1.2)
            ax_spec.set_title(f"{res['name']} - Spectrum (SQNR: {res['sqnr_db']:.1f} dB)", fontsize=10)
            ax_spec.set_xlabel("FFT Bin Index")
            ax_spec.set_ylabel("Linear Magnitude")
            ax_spec.grid(True, linestyle=':', alpha=0.6)
            ax_spec.legend(loc='upper right', fontsize=8)

            # Error Plot
            ax_err.plot(k_bins, err, 'm-', linewidth=1.2)
            ax_err.set_title(f"Quantization Error (|Fixed - Ref|)", fontsize=10)
            ax_err.set_xlabel("FFT Bin Index")
            ax_err.set_ylabel("Absolute Error")
            ax_err.grid(True, linestyle=':', alpha=0.6)

        plt.tight_layout()
        plot_path = os.path.join(plots_dir, "fft_golden_verification.png")
        plt.savefig(plot_path, dpi=200)
        plt.close()
        print(f"[+] Verification plot saved to: {plot_path}")

    print("=" * 80)
    print("Golden model execution completed successfully.")
    print("=" * 80)
    return results


if __name__ == '__main__':
    run_golden_tests()
