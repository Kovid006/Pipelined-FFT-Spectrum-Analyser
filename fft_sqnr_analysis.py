#!/usr/bin/env python3
"""
Multi-model SQNR / SFDR analysis for the 256-point fixed-point FFT (P10)
========================================================================

Compares any number of bit-accurate Q1.15 FFT models against double-precision
numpy.fft.fft. Models are registered in MODELS: each is a function
    fft_fn(in_q15_real, in_q15_imag) -> dict containing 'complex_float'
(the natural-order output divided by 32768, i.e. scaled by 1/256 overall).

To add the paper design later:
    MODELS['paper'] = lambda r, i: my_paper_model(r, i)

Changes from the radix-2-only version:
    * model is a parameter; radix-2 baseline, radix-2^2 (trunc / round) built in
    * REAL tones and REAL noise (DDS / XADC inputs are real)
    * off-bin (non-coherent) tone sweep added
    * exactly-lossless cases (SQNR = inf, e.g. bin 64) are excluded from the
      statistics and reported separately instead of breaking mean/plots
    * no hard-coded "theoretical" line or y-limits
    * two-tone analysis reports SFDR (worst spur) as well as SQNR, with the
      float reference's own SFDR as the input-quantization ceiling. Fixed-point
      spurs are floored at 1 LSB, so SFDR is bounded by the output word length
    * model_comparison.csv: the SQNR table for the report
    * every figure compares all models; two-tone results are plotted

Outputs: data/sqnr_v2/csv/*.csv and data/sqnr_v2/plots/*.png
"""

import os
import sys
import numpy as np
import matplotlib.pyplot as plt

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from fft_golden import (fft_256_fixed, fft_reference_float, compute_sqnr,
                        float_to_q15, q15_to_float)
from fft_r22_golden import fft_256_r22

N = 256
HALF = N // 2
N_BINS = np.arange(N)

# ------------------------------------------------------------------------------
# Model registry: add / remove models here
# ------------------------------------------------------------------------------
MODELS = {
    'radix-2 (baseline)': lambda r, i: fft_256_fixed(r, i, round_mode='trunc', scale_stages=True),
    'radix-2^2 trunc':    lambda r, i: fft_256_r22(r, i, round_mode='trunc'),
    'radix-2^2 round':    lambda r, i: fft_256_r22(r, i, round_mode='round'),
}
SPECTRUM_MODEL = 'radix-2^2 trunc'      # model shown in the spectrum figure

_COLORS = ['#1f77b4', '#d62728', '#2ca02c', '#ff7f0e', '#9467bd', '#8c564b']
_MARKERS = ['o', 's', '^', 'v', 'D', 'P']


def _style(idx):
    return dict(color=_COLORS[idx % len(_COLORS)], marker=_MARKERS[idx % len(_MARKERS)],
                markersize=3, linewidth=1.4)


# ------------------------------------------------------------------------------
# Core helpers
# ------------------------------------------------------------------------------
def real_tone(k, amp=0.85):
    """Real cosine at (possibly fractional) bin k."""
    n = np.arange(N)
    return amp * np.cos(2.0 * np.pi * k * n / N) + 0j


def evaluate(x_complex, fft_fn):
    """Quantize, run the model, compare with NumPy on the *quantized* input
    (so only FFT arithmetic error is measured, not input quantization)."""
    in_r = float_to_q15(np.real(x_complex))
    in_i = float_to_q15(np.imag(x_complex))
    out = fft_fn(in_r, in_i)
    ref = fft_reference_float(q15_to_float(in_r) + 1j * q15_to_float(in_i), scale_by_n=True)
    err = np.abs(out['complex_float'] - ref)
    return {
        'sqnr': compute_sqnr(ref, out['complex_float']),
        'max_err': float(err.max()),
        'rms_err': float(np.sqrt(np.mean(err ** 2))),
        'out': out, 'ref': ref,
    }


def finite_stats(arr):
    """(mean, min, max, n_exact) ignoring exactly-lossless (inf) entries."""
    arr = np.asarray(arr, dtype=float)
    fin = arr[np.isfinite(arr)]
    n_exact = int(arr.size - fin.size)
    if fin.size == 0:
        return float('nan'), float('nan'), float('nan'), n_exact
    return float(fin.mean()), float(fin.min()), float(fin.max()), n_exact


def mask_inf(arr):
    a = np.asarray(arr, dtype=float).copy()
    a[~np.isfinite(a)] = np.nan
    return a


LSB = 1.0 / 32768.0


def sfdr_db(mag, tone_bins, floor=0.0):
    """SFDR over bins 0..N/2-1: weakest tone vs largest non-tone bin.
    floor: smallest spur that can be reported. For fixed-point outputs use 1 LSB:
    a bin of exactly 0 only means "below 1 LSB", so SFDR there is limited by
    the output word length, not infinite."""
    half = np.asarray(mag)[:HALF]
    keep = np.ones(HALF, dtype=bool)
    keep[list(tone_bins)] = False
    tone = min(half[b] for b in tone_bins)
    spur = max(half[keep].max(), floor)
    return float('inf') if spur == 0 else float(20.0 * np.log10(tone / spur))


def write_csv(path, comments, header, rows):
    with open(path, 'w') as f:
        for c in comments:
            f.write(f"# {c}\n")
        f.write(",".join(header) + "\n")
        for row in rows:
            f.write(",".join(row) + "\n")
    print(f"    saved {path}")


def _fmt(v, nd=4):
    return "inf" if not np.isfinite(v) and v > 0 else f"{v:.{nd}f}"


# ------------------------------------------------------------------------------
# Analysis 1: SQNR vs tone frequency (coherent and off-bin)
# ------------------------------------------------------------------------------
def analyze_vs_frequency(models, csv_dir, amp=0.85, offset=0.37):
    print("--> Analysis 1: SQNR vs tone frequency (real tones)")
    bins = np.arange(1, HALF)
    res = {'bins': bins, 'integer': {}, 'offbin': {}}
    for name, fn in models.items():
        res['integer'][name] = np.array([evaluate(real_tone(k, amp), fn)['sqnr'] for k in bins])
        res['offbin'][name] = np.array([evaluate(real_tone(k + offset, amp), fn)['sqnr'] for k in bins])

    header = ['bin'] + [f"{m}_integer_db" for m in models] + [f"{m}_offbin_db" for m in models]
    rows = []
    for idx, k in enumerate(bins):
        rows.append([str(k)] +
                    [_fmt(res['integer'][m][idx]) for m in models] +
                    [_fmt(res['offbin'][m][idx]) for m in models])
    write_csv(os.path.join(csv_dir, "sqnr_vs_frequency.csv"),
              [f"real cosine, amp={amp}, off-bin offset={offset}; inf = bit-exact output"],
              header, rows)
    return res


# ------------------------------------------------------------------------------
# Analysis 2: SQNR vs input amplitude (tone and noise)
# ------------------------------------------------------------------------------
def analyze_vs_amplitude(models, csv_dir, test_bin=32):
    print("--> Analysis 2: SQNR vs input amplitude")
    dbfs = np.linspace(-60, 0, 31)
    rng = np.random.default_rng(12345)
    tone = {m: [] for m in models}
    noise = {m: [] for m in models}
    for db in dbfs:
        amp = 10.0 ** (db / 20.0)
        x_t = real_tone(test_bin, amp)
        x_n = np.clip(rng.normal(0, amp / 3.0, N), -1.0, 1.0) + 0j     # same noise for all models
        for name, fn in models.items():
            tone[name].append(evaluate(x_t, fn)['sqnr'])
            noise[name].append(evaluate(x_n, fn)['sqnr'])
    tone = {m: np.array(v) for m, v in tone.items()}
    noise = {m: np.array(v) for m, v in noise.items()}

    header = ['dbfs'] + [f"{m}_tone_db" for m in models] + [f"{m}_noise_db" for m in models]
    rows = [[f"{db:.2f}"] + [_fmt(tone[m][i]) for m in models] + [_fmt(noise[m][i]) for m in models]
            for i, db in enumerate(dbfs)]
    write_csv(os.path.join(csv_dir, "sqnr_vs_amplitude.csv"),
              [f"real tone at bin {test_bin}; noise sigma = amplitude/3"], header, rows)
    return {'dbfs': dbfs, 'tone': tone, 'noise': noise}


# ------------------------------------------------------------------------------
# Analysis 3: two-tone separation (SQNR and SFDR)
# ------------------------------------------------------------------------------
def analyze_two_tone(models, csv_dir, base_bin=32, amp_each=0.45):
    print("--> Analysis 3: two-tone separation (SQNR + SFDR)")
    deltas = np.array([1, 2, 3, 4, 8, 12, 16, 24, 32, 48, 64, 80])
    sqnr = {m: [] for m in models}
    sfdr = {m: [] for m in models}
    sfdr_ref = []
    for d in deltas:
        f2 = base_bin + d
        x = real_tone(base_bin, amp_each) + real_tone(f2, amp_each)
        for name, fn in models.items():
            r = evaluate(x, fn)
            sqnr[name].append(r['sqnr'])
            sfdr[name].append(sfdr_db(np.abs(r['out']['complex_float']), (base_bin, f2), floor=LSB))
        sfdr_ref.append(sfdr_db(np.abs(r['ref']), (base_bin, f2)))   # ref is model independent
    sqnr = {m: np.array(v) for m, v in sqnr.items()}
    sfdr = {m: np.array(v) for m, v in sfdr.items()}
    sfdr_ref = np.array(sfdr_ref)

    header = (['delta_bin', 'f2_bin', 'float_ref_sfdr_db'] +
              [f"{m}_sqnr_db" for m in models] + [f"{m}_sfdr_db" for m in models])
    rows = [[str(d), str(base_bin + d), _fmt(sfdr_ref[i], 2)] +
            [_fmt(sqnr[m][i], 2) for m in models] + [_fmt(sfdr[m][i], 2) for m in models]
            for i, d in enumerate(deltas)]
    write_csv(os.path.join(csv_dir, "two_tone.csv"),
              [f"real tones at bin {base_bin} and {base_bin}+delta, amp {amp_each} each; "
               "SFDR = weakest tone vs largest other bin in 0..127 (incl. DC); fixed-point spurs floored at 1 LSB; "
               "float reference blank/inf = spur exactly zero"], header, rows)
    return {'deltas': deltas, 'sqnr': sqnr, 'sfdr': sfdr, 'sfdr_ref': sfdr_ref}


# ------------------------------------------------------------------------------
# Analysis 4: Gaussian-noise Monte Carlo
# ------------------------------------------------------------------------------
def analyze_noise_mc(models, csv_dir, n_trials=50, sigma=0.25):
    print(f"--> Analysis 4: real Gaussian noise Monte Carlo ({n_trials} trials)")
    out = {m: [] for m in models}
    for seed in range(n_trials):
        rng = np.random.default_rng(seed)
        x = np.clip(rng.normal(0, sigma, N), -0.99, 0.99) + 0j
        for name, fn in models.items():
            out[name].append(evaluate(x, fn)['sqnr'])
    out = {m: np.array(v) for m, v in out.items()}

    rows = [[str(s)] + [_fmt(out[m][s]) for m in models] for s in range(n_trials)]
    write_csv(os.path.join(csv_dir, "noise_monte_carlo.csv"),
              [f"real Gaussian noise, sigma={sigma}, clipped at 0.99, seeds 0..{n_trials - 1}"],
              ['seed'] + [f"{m}_sqnr_db" for m in models], rows)
    for m in models:
        mean, lo, hi, _ = finite_stats(out[m])
        print(f"    {m:<20} mean {mean:6.2f} dB  std {np.std(out[m]):.2f}  [min {lo:.2f}, max {hi:.2f}]")
    return out


# ------------------------------------------------------------------------------
# Comparison table for the report
# ------------------------------------------------------------------------------
def comparison_table(models, noise_mc, csv_dir):
    cases = {
        'single tone, bin 32, amp 0.85': real_tone(32, 0.85),
        'two tones, bins 32 & 96, 0.45 each': real_tone(32, 0.45) + real_tone(96, 0.45),
        'off-bin tone, bin 40.37, amp 0.85': real_tone(40.37, 0.85),
    }
    rows, table = [], []
    for label, x in cases.items():
        vals = [evaluate(x, fn)['sqnr'] for fn in models.values()]
        table.append((label, vals))
    table.append(('noise, sigma 0.25 (mean of MC)', [finite_stats(noise_mc[m])[0] for m in models]))

    write_csv(os.path.join(csv_dir, "model_comparison.csv"), ["SQNR (dB) vs NumPy, per model"],
              ['signal'] + list(models), [[f'"{lab}"'] + [_fmt(v, 2) for v in vals] for lab, vals in table])

    print("\n" + "=" * 80)
    print("   SQNR COMPARISON (dB vs NumPy, FFT arithmetic error only)")
    print("=" * 80)
    print(f"{'signal':<38}" + "".join(f"{m:>20}" for m in models))
    for lab, vals in table:
        print(f"{lab:<38}" + "".join(f"{v:>20.2f}" for v in vals))
    print("=" * 80)


# ------------------------------------------------------------------------------
# Plots
# ------------------------------------------------------------------------------
def _plot_style():
    plt.rcParams.update({'font.size': 11, 'axes.labelsize': 12, 'axes.titlesize': 12,
                         'legend.fontsize': 9, 'font.family': 'sans-serif'})


def plot_frequency(res, models, plot_dir):
    fig, axes = plt.subplots(2, 1, figsize=(9.5, 8), sharex=True)
    for ax, key, title in ((axes[0], 'integer', 'Coherent tones (integer bins)'),
                           (axes[1], 'offbin', 'Non-coherent tones (bin + 0.37)')):
        for idx, m in enumerate(models):
            arr = res[key][m]
            mean, _, _, n_exact = finite_stats(arr)
            label = f"{m}: mean {mean:.1f} dB" + (f" ({n_exact} exact bin omitted)" if n_exact else "")
            ax.plot(res['bins'], mask_inf(arr), label=label, **_style(idx))
        ax.set_title(title)
        ax.set_ylabel("SQNR (dB)")
        ax.grid(True, linestyle='--', alpha=0.5)
        ax.legend(loc='best')
    axes[1].set_xlabel("Tone bin index k")
    fig.suptitle("SQNR vs tone frequency (real input, amplitude 0.85)")
    fig.tight_layout()
    path = os.path.join(plot_dir, "sqnr_vs_frequency.png")
    fig.savefig(path, dpi=300)
    plt.close(fig)
    print(f"    saved {path}")


def plot_amplitude(res, models, plot_dir):
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.8), sharey=True)
    for ax, key, title in ((axes[0], 'tone', 'Real tone (bin 32)'),
                           (axes[1], 'noise', 'White Gaussian noise')):
        for idx, m in enumerate(models):
            ax.plot(res['dbfs'], mask_inf(res[key][m]), label=m, **_style(idx))
        ax.set_title(title)
        ax.set_xlabel("Input amplitude (dBFS)")
        ax.grid(True, linestyle='--', alpha=0.5)
        ax.legend(loc='upper left')
    axes[0].set_ylabel("SQNR (dB)")
    fig.suptitle("SQNR vs input level: fixed 1/256 scaling costs dynamic range")
    fig.tight_layout()
    path = os.path.join(plot_dir, "sqnr_vs_amplitude.png")
    fig.savefig(path, dpi=300)
    plt.close(fig)
    print(f"    saved {path}")


def plot_two_tone(res, models, plot_dir):
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.8))
    for idx, m in enumerate(models):
        axes[0].plot(res['deltas'], mask_inf(res['sqnr'][m]), label=m, **_style(idx))
        axes[1].plot(res['deltas'], mask_inf(res['sfdr'][m]), label=m, **_style(idx))
    axes[1].plot(res['deltas'], mask_inf(res['sfdr_ref']), 'k:', linewidth=1.6,
                 label='float reference (input-quantization limit)')
    axes[0].set_title("Two-tone SQNR")
    axes[0].set_ylabel("SQNR (dB)")
    axes[1].set_title("Two-tone SFDR")
    axes[1].set_ylabel("SFDR (dB)")
    for ax in axes:
        ax.set_xlabel("Tone separation (bins)")
        ax.grid(True, linestyle='--', alpha=0.5)
        ax.legend(loc='best')
    fig.tight_layout()
    path = os.path.join(plot_dir, "two_tone_sqnr_sfdr.png")
    fig.savefig(path, dpi=300)
    plt.close(fig)
    print(f"    saved {path}")


def plot_spectrum(models, plot_dir, model_name=SPECTRUM_MODEL):
    fn = models[model_name]
    cases = (('Single tone (bin 32, amp 0.85)', real_tone(32, 0.85)),
             ('Two tones (bins 32 & 96, 0.45 each)', real_tone(32, 0.45) + real_tone(96, 0.45)))
    fig, axes = plt.subplots(2, 1, figsize=(10, 8), sharex=True)
    for ax, (title, x) in zip(axes, cases):
        r = evaluate(x, fn)
        to_db = lambda m: 20.0 * np.log10(np.maximum(m, 1e-12) / 0.5)   # 0 dBFS = full-scale real tone
        ax.plot(N_BINS[:HALF], to_db(np.abs(r['ref']))[:HALF], color='#1f77b4', linewidth=1.5,
                label='NumPy double reference')
        ax.plot(N_BINS[:HALF], to_db(np.abs(r['out']['complex_float']))[:HALF], color='#d62728',
                linestyle='--', linewidth=1.2, label=f'{model_name} (SQNR {r["sqnr"]:.1f} dB)')
        ax.set_title(title)
        ax.set_ylabel("Magnitude (dBFS)")
        ax.set_ylim([-120, 5])
        ax.grid(True, linestyle='--', alpha=0.5)
        ax.legend(loc='upper right')
    axes[1].set_xlabel("FFT bin (0 to 127)")
    fig.tight_layout()
    path = os.path.join(plot_dir, "spectrum_comparison_dbfs.png")
    fig.savefig(path, dpi=300)
    plt.close(fig)
    print(f"    saved {path}")


# ------------------------------------------------------------------------------
# Runner
# ------------------------------------------------------------------------------
def run_all(models=None, base_dir=None):
    models = MODELS if models is None else models
    base_dir = os.path.join(SCRIPT_DIR, "data", "sqnr_v2") if base_dir is None else base_dir
    csv_dir, plot_dir = os.path.join(base_dir, "csv"), os.path.join(base_dir, "plots")
    os.makedirs(csv_dir, exist_ok=True)
    os.makedirs(plot_dir, exist_ok=True)

    print("=" * 80)
    print("   256-POINT FIXED-POINT FFT: MULTI-MODEL SQNR / SFDR ANALYSIS")
    print("=" * 80)
    print("Models: " + ", ".join(models) + f"\nOutput: {base_dir}\n")

    r_freq = analyze_vs_frequency(models, csv_dir)
    r_amp = analyze_vs_amplitude(models, csv_dir)
    r_two = analyze_two_tone(models, csv_dir)
    r_noise = analyze_noise_mc(models, csv_dir)

    _plot_style()
    print("--> Plots")
    plot_frequency(r_freq, models, plot_dir)
    plot_amplitude(r_amp, models, plot_dir)
    plot_two_tone(r_two, models, plot_dir)
    plot_spectrum(models, plot_dir)

    comparison_table(models, r_noise, csv_dir)

    print("\nSingle-tone sweep summary (bins 1-127, finite values only):")
    for key, label in (('integer', 'coherent'), ('offbin', 'off-bin ')):
        for m in models:
            mean, lo, hi, n_ex = finite_stats(r_freq[key][m])
            print(f"  {label} {m:<20} mean {mean:6.2f}  min {lo:6.2f}  max {hi:6.2f}"
                  + (f"  ({n_ex} bit-exact bin(s) excluded)" if n_ex else ""))


if __name__ == '__main__':
    run_all()
