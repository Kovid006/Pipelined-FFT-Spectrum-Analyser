#!/usr/bin/env python3
"""
Comprehensive SQNR Analysis for 256-Point Fixed-Point FFT
==========================================================

This script conducts rigorous Signal-to-Quantization-Noise Ratio (SQNR)
evaluations comparing the bit-accurate Q1.15 fixed-point FFT model with
double-precision IEEE-754 floating-point FFT (numpy.fft.fft).

Analyses performed:
-------------------
1. SQNR vs Tone Frequency (sweeping bins 1 to 127)
2. SQNR vs Input Amplitude / SNR (sweeping -60 dBFS to 0 dBFS)
3. SQNR vs Two-Tone Frequency Separation (evaluating intermodulation / dynamic range)
4. SQNR vs White Gaussian Noise Power (Monte-Carlo across multiple seeds)
5. Magnitude Spectrum Comparison (dBFS scale with harmonic distortion analysis)

Outputs:
--------
- CSV files saved under 'data/sqnr_csv/' for RTL documentation
- Publication-quality figures (300 DPI) saved under 'data/plots/'

Author: FPGA DSP RTL Design Engineer
"""

import os
import sys
import numpy as np
import matplotlib.pyplot as plt

# Ensure local imports from fft_golden work regardless of working directory
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from fft_golden import (
    fft_256_fixed,
    fft_reference_float,
    compute_sqnr,
    float_to_q15,
    q15_to_float,
    Q15_SCALE
)


# ==============================================================================
# Helper Functions
# ==============================================================================

def ensure_dirs(base_data_dir: str):
    """Create data and plot directories."""
    csv_dir = os.path.join(base_data_dir, "sqnr_csv")
    plot_dir = os.path.join(base_data_dir, "plots")
    os.makedirs(csv_dir, exist_ok=True)
    os.makedirs(plot_dir, exist_ok=True)
    return csv_dir, plot_dir


def evaluate_signal_sqnr(sig_complex: np.ndarray, round_mode: str = 'trunc') -> tuple:
    """
    Run fixed-point FFT and floating-point reference on input signal,
    returning (sqnr_db, max_abs_err, rms_err, out_fixed, out_ref).
    """
    n_points = len(sig_complex)
    in_r = float_to_q15(np.real(sig_complex))
    in_i = float_to_q15(np.imag(sig_complex))

    out_fixed = fft_256_fixed(in_r, in_i, round_mode=round_mode, scale_stages=True)

    # Reference using exact quantized input representation to isolate FFT arithmetic error
    in_ref = q15_to_float(in_r) + 1j * q15_to_float(in_i)
    out_ref = fft_reference_float(in_ref, scale_by_n=True)

    sqnr_db = compute_sqnr(out_ref, out_fixed['complex_float'])
    err = np.abs(out_fixed['complex_float'] - out_ref)
    max_err = float(np.max(err))
    rms_err = float(np.sqrt(np.mean(err ** 2)))

    return sqnr_db, max_err, rms_err, out_fixed, out_ref


# ==============================================================================
# Analysis 1: SQNR vs Tone Frequency
# ==============================================================================

def analyze_sqnr_vs_frequency(csv_dir: str, n_points: int = 256, amp: float = 0.85):
    """
    Sweep single-tone frequency across bins 1 to (N/2 - 1) and calculate SQNR.
    """
    print("--> Running Analysis 1: SQNR vs Tone Frequency...")
    bins = np.arange(1, n_points // 2)
    n = np.arange(n_points)
    results = []

    for k_bin in bins:
        tone = amp * np.exp(1j * 2.0 * np.pi * k_bin * n / n_points)
        sqnr_db, max_err, rms_err, _, _ = evaluate_signal_sqnr(tone)
        results.append((k_bin, amp, sqnr_db, max_err, rms_err))

    # Save CSV
    csv_path = os.path.join(csv_dir, "sqnr_vs_frequency.csv")
    with open(csv_path, 'w') as f:
        f.write("# SQNR vs Tone Frequency Analysis\n")
        f.write("# FFT_Points=256, Amplitude=0.85, PerStageShift=1\n")
        f.write("bin_index,amplitude,sqnr_db,max_error,rms_error\n")
        for row in results:
            f.write(f"{row[0]},{row[1]:.4f},{row[2]:.4f},{row[3]:.8f},{row[4]:.8f}\n")

    print(f"    Saved results to: {csv_path}")
    return np.array(results)


# ==============================================================================
# Analysis 2: SQNR vs Input Amplitude / SNR
# ==============================================================================

def analyze_sqnr_vs_amplitude(csv_dir: str, n_points: int = 256, test_bin: int = 32):
    """
    Sweep signal amplitude from -60 dBFS to 0 dBFS and calculate SQNR.
    Also tests white noise input over varying RMS levels.
    """
    print("--> Running Analysis 2: SQNR vs Input Amplitude / SNR...")
    n = np.arange(n_points)
    dbfs_levels = np.linspace(-60, 0, 31)
    results_tone = []
    results_noise = []

    rng = np.random.default_rng(12345)

    for dbfs in dbfs_levels:
        amp = 10.0 ** (dbfs / 20.0)

        # 1. Sinusoidal Tone
        tone = amp * np.exp(1j * 2.0 * np.pi * test_bin * n / n_points)
        sqnr_tone, max_err_t, rms_err_t, _, _ = evaluate_signal_sqnr(tone)
        results_tone.append((dbfs, amp, sqnr_tone, max_err_t, rms_err_t))

        # 2. Gaussian Noise
        sigma = amp / 3.0  # ~3-sigma within peak amplitude
        noise = rng.normal(0, sigma, n_points) + 1j * rng.normal(0, sigma, n_points)
        noise = np.clip(np.real(noise), -1.0, 1.0) + 1j * np.clip(np.imag(noise), -1.0, 1.0)
        sqnr_noise, max_err_n, rms_err_n, _, _ = evaluate_signal_sqnr(noise)
        results_noise.append((dbfs, amp, sqnr_noise, max_err_n, rms_err_n))

    # Save CSV
    csv_path = os.path.join(csv_dir, "sqnr_vs_amplitude.csv")
    with open(csv_path, 'w') as f:
        f.write("# SQNR vs Input Amplitude Analysis\n")
        f.write("# FFT_Points=256, Test_Bin=32\n")
        f.write("dbfs,amplitude,tone_sqnr_db,noise_sqnr_db\n")
        for r_t, r_n in zip(results_tone, results_noise):
            f.write(f"{r_t[0]:.2f},{r_t[1]:.6f},{r_t[2]:.4f},{r_n[2]:.4f}\n")

    print(f"    Saved results to: {csv_path}")
    return np.array(results_tone), np.array(results_noise)


# ==============================================================================
# Analysis 3: Two-Tone Frequency Separation
# ==============================================================================

def analyze_sqnr_vs_separation(csv_dir: str, n_points: int = 256, base_bin: int = 32):
    """
    Sweep frequency separation between two equal-power tones.
    f1 = base_bin, f2 = base_bin + delta_k.
    """
    print("--> Running Analysis 3: SQNR vs Two-Tone Frequency Separation...")
    n = np.arange(n_points)
    amp_each = 0.45
    delta_bins = np.array([1, 2, 3, 4, 8, 12, 16, 24, 32, 48, 64, 80])
    results = []

    for delta in delta_bins:
        f2 = base_bin + delta
        if f2 >= n_points:
            continue
        signal = (amp_each * np.cos(2.0 * np.pi * base_bin * n / n_points) +
                  amp_each * np.cos(2.0 * np.pi * f2 * n / n_points)) + 0j
        sqnr_db, max_err, rms_err, _, _ = evaluate_signal_sqnr(signal)
        results.append((delta, base_bin, f2, sqnr_db, max_err, rms_err))

    # Save CSV
    csv_path = os.path.join(csv_dir, "sqnr_two_tone.csv")
    with open(csv_path, 'w') as f:
        f.write("# Two-Tone SQNR vs Frequency Separation\n")
        f.write("# Amplitude_each=0.45, Base_Bin=32\n")
        f.write("delta_bin,f1_bin,f2_bin,sqnr_db,max_error,rms_error\n")
        for row in results:
            f.write(f"{int(row[0])},{int(row[1])},{int(row[2])},{row[3]:.4f},{row[4]:.8f},{row[5]:.8f}\n")

    print(f"    Saved results to: {csv_path}")
    return np.array(results)


# ==============================================================================
# Analysis 4: Gaussian Noise Monte Carlo
# ==============================================================================

def analyze_gaussian_noise_monte_carlo(csv_dir: str, n_points: int = 256,
                                      n_trials: int = 50, sigma: float = 0.25):
    """
    Monte Carlo evaluation of SQNR with varying random seeds for white Gaussian noise.
    """
    print(f"--> Running Analysis 4: Gaussian Noise Monte Carlo ({n_trials} trials)...")
    sqnr_list = []
    rms_err_list = []

    for seed in range(n_trials):
        rng = np.random.default_rng(seed)
        noise = rng.normal(0, sigma, n_points) + 1j * rng.normal(0, sigma, n_points)
        noise = np.clip(np.real(noise), -0.99, 0.99) + 1j * np.clip(np.imag(noise), -0.99, 0.99)
        sqnr, _, rms_e, _, _ = evaluate_signal_sqnr(noise)
        sqnr_list.append(sqnr)
        rms_err_list.append(rms_e)

    sqnr_arr = np.array(sqnr_list)
    mean_sqnr = np.mean(sqnr_arr)
    std_sqnr = np.std(sqnr_arr)
    min_sqnr = np.min(sqnr_arr)
    max_sqnr = np.max(sqnr_arr)

    csv_path = os.path.join(csv_dir, "sqnr_gaussian_noise.csv")
    with open(csv_path, 'w') as f:
        f.write("# Gaussian Noise SQNR Monte Carlo Summary\n")
        f.write(f"# Trials={n_trials}, Sigma={sigma}\n")
        f.write("trial_seed,sqnr_db,rms_error\n")
        for idx, (s_val, r_val) in enumerate(zip(sqnr_list, rms_err_list)):
            f.write(f"{idx},{s_val:.4f},{r_val:.8f}\n")
        f.write(f"# Mean_SQNR={mean_sqnr:.4f}, Std_SQNR={std_sqnr:.4f}, Min_SQNR={min_sqnr:.4f}, Max_SQNR={max_sqnr:.4f}\n")

    print(f"    Gaussian Noise SQNR: Mean={mean_sqnr:.2f} dB, Std={std_sqnr:.2f} dB [Min={min_sqnr:.2f}, Max={max_sqnr:.2f}]")
    print(f"    Saved results to: {csv_path}")
    return mean_sqnr, std_sqnr, sqnr_arr


# ==============================================================================
# Publication-Quality Plot Generation
# ==============================================================================

def generate_plots(plot_dir: str, res_freq: np.ndarray, res_tone_amp: np.ndarray,
                   res_noise_amp: np.ndarray, res_sep: np.ndarray):
    """
    Generate publication-quality plots:
    1. SQNR vs Tone Frequency
    2. SQNR vs Input SNR / Amplitude
    3. Magnitude Spectrum Comparison (dBFS) for Single & Two-Tone Signals
    """
    print("--> Generating Publication-Quality Figures...")

    # Plot Configuration Style
    plt.style.use('default')
    plt.rcParams.update({
        'font.size': 11,
        'axes.labelsize': 12,
        'axes.titlesize': 13,
        'xtick.labelsize': 10,
        'ytick.labelsize': 10,
        'legend.fontsize': 10,
        'figure.titlesize': 14,
        'font.family': 'sans-serif'
    })

    # --------------------------------------------------------------------------
    # Figure 1: SQNR vs Tone Frequency
    # --------------------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(9, 5))
    bins = res_freq[:, 0]
    sqnr = res_freq[:, 2]
    mean_sqnr = np.mean(sqnr)

    ax.plot(bins, sqnr, color='#1f77b4', linewidth=1.8, marker='o', markersize=3, label='Fixed-Point Q1.15 SQNR')
    ax.axhline(mean_sqnr, color='#d62728', linestyle='--', linewidth=1.5,
               label=f'Mean SQNR ({mean_sqnr:.1f} dB)')
    ax.axhline(70.0, color='gray', linestyle=':', label='Theoretical Nominal Q1.15 Floor (~70 dB)')

    ax.set_title("256-Point FFT Fixed-Point SQNR vs Tone Frequency", pad=12)
    ax.set_xlabel("Tone Frequency Bin Index k (0 to 127)")
    ax.set_ylabel("SQNR (dB)")
    ax.set_ylim([45, 80])
    ax.grid(True, linestyle='--', alpha=0.6)
    ax.legend(loc='lower right', framealpha=0.9)
    plt.tight_layout()

    fig_path1 = os.path.join(plot_dir, "sqnr_vs_frequency.png")
    fig.savefig(fig_path1, dpi=300)
    plt.close(fig)
    print(f"    Saved: {fig_path1}")

    # --------------------------------------------------------------------------
    # Figure 2: SQNR vs Input Amplitude / SNR
    # --------------------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(9, 5))
    dbfs = res_tone_amp[:, 0]
    sqnr_t = res_tone_amp[:, 2]
    sqnr_n = res_noise_amp[:, 2]

    ax.plot(dbfs, sqnr_t, color='#2ca02c', linewidth=2.0, marker='s', markersize=4, label='Single Tone (Bin 32)')
    ax.plot(dbfs, sqnr_n, color='#ff7f0e', linewidth=2.0, marker='^', markersize=4, label='White Gaussian Noise')

    ax.set_title("Fixed-Point FFT SQNR vs Input Amplitude", pad=12)
    ax.set_xlabel("Input Signal Amplitude (dBFS)")
    ax.set_ylabel("SQNR (dB)")
    ax.set_xlim([-60, 0])
    ax.grid(True, linestyle='--', alpha=0.6)
    ax.legend(loc='upper left', framealpha=0.9)
    plt.tight_layout()

    fig_path2 = os.path.join(plot_dir, "sqnr_vs_amplitude.png")
    fig.savefig(fig_path2, dpi=300)
    plt.close(fig)
    print(f"    Saved: {fig_path2}")

    # --------------------------------------------------------------------------
    # Figure 3: Magnitude Spectrum Comparison (dBFS)
    # --------------------------------------------------------------------------
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

    # Subplot 1: Single Tone at Bin 32
    n = np.arange(256)
    tone_32 = 0.85 * np.cos(2.0 * np.pi * 32 * n / 256) + 0j
    _, _, _, out_fix_t, out_ref_t = evaluate_signal_sqnr(tone_32)

    mag_fix_t = np.abs(out_fix_t['complex_float'])
    mag_ref_t = np.abs(out_ref_t)

    # Convert to dBFS (0 dBFS = full scale unscaled peak)
    eps = 1e-12
    db_fix_t = 20.0 * np.log10(np.maximum(mag_fix_t, eps) / 0.5)
    db_ref_t = 20.0 * np.log10(np.maximum(mag_ref_t, eps) / 0.5)

    ax1.plot(n, db_ref_t, color='#1f77b4', linewidth=1.5, label='NumPy Double Reference')
    ax1.plot(n, db_fix_t, color='#d62728', linestyle='--', linewidth=1.2, label='Fixed-Point Q1.15 Model')
    ax1.set_title("Single Tone Spectrum Comparison (Bin 32, Amplitude 0.85)")
    ax1.set_ylabel("Normalized Magnitude (dBFS)")
    ax1.set_ylim([-90, 5])
    ax1.grid(True, linestyle='--', alpha=0.5)
    ax1.legend(loc='upper right')

    # Subplot 2: Two-Tone at Bins 32 and 96
    tone_two = (0.45 * np.cos(2.0 * np.pi * 32 * n / 256) +
                0.45 * np.cos(2.0 * np.pi * 96 * n / 256)) + 0j
    _, _, _, out_fix_2, out_ref_2 = evaluate_signal_sqnr(tone_two)

    mag_fix_2 = np.abs(out_fix_2['complex_float'])
    mag_ref_2 = np.abs(out_ref_2)
    db_fix_2 = 20.0 * np.log10(np.maximum(mag_fix_2, eps) / 0.5)
    db_ref_2 = 20.0 * np.log10(np.maximum(mag_ref_2, eps) / 0.5)

    ax2.plot(n, db_ref_2, color='#1f77b4', linewidth=1.5, label='NumPy Double Reference')
    ax2.plot(n, db_fix_2, color='#d62728', linestyle='--', linewidth=1.2, label='Fixed-Point Q1.15 Model')
    ax2.set_title("Two-Tone Spectrum Comparison (Bins 32 & 96, Amp 0.45 each)")
    ax2.set_xlabel("FFT Bin Index (0 to 255)")
    ax2.set_ylabel("Normalized Magnitude (dBFS)")
    ax2.set_ylim([-90, 5])
    ax2.grid(True, linestyle='--', alpha=0.5)
    ax2.legend(loc='upper right')

    plt.tight_layout()
    fig_path3 = os.path.join(plot_dir, "spectrum_comparison_dbfs.png")
    fig.savefig(fig_path3, dpi=300)
    plt.close(fig)
    print(f"    Saved: {fig_path3}")


# ==============================================================================
# Main Runner
# ==============================================================================

def run_all_sqnr_analyses(base_data_dir: str = None):
    """Run all SQNR analyses, export CSV tables, and render plots."""
    if base_data_dir is None:
        base_data_dir = os.path.join(SCRIPT_DIR, "data")

    csv_dir, plot_dir = ensure_dirs(base_data_dir)

    print("=" * 80)
    print("   256-POINT FIXED-POINT FFT: COMPREHENSIVE SQNR ANALYSIS")
    print("=" * 80)
    print(f"CSV Directory:   {csv_dir}")
    print(f"Plots Directory: {plot_dir}\n")

    res_freq = analyze_sqnr_vs_frequency(csv_dir)
    res_tone_amp, res_noise_amp = analyze_sqnr_vs_amplitude(csv_dir)
    res_sep = analyze_sqnr_vs_separation(csv_dir)
    mean_sqnr, std_sqnr, _ = analyze_gaussian_noise_monte_carlo(csv_dir)

    generate_plots(plot_dir, res_freq, res_tone_amp, res_noise_amp, res_sep)

    print("\n" + "=" * 80)
    print("   SQNR ANALYSIS SUMMARY REPORT")
    print("=" * 80)
    print(f"Single-Tone Mean SQNR (0 dBFS full range):  {np.mean(res_freq[:, 2]):.2f} dB")
    print(f"Single-Tone Max SQNR:                       {np.max(res_freq[:, 2]):.2f} dB")
    print(f"Single-Tone Min SQNR:                       {np.min(res_freq[:, 2]):.2f} dB")
    print(f"White Gaussian Noise SQNR (Mean ± 1-sigma): {mean_sqnr:.2f} ± {std_sqnr:.2f} dB")
    print("=" * 80)


if __name__ == '__main__':
    run_all_sqnr_analyses()
