# Pipelined 256-Point Radix-$2^2$ SDF FFT Spectrum Analyser


**Target FPGA Board:** Digilent Zybo Z7-10 (`xc7z010clg400-1`)  
**Clock Frequency:** 125.0 MHz ($T_{\text{clk}} = 8.00\text{ ns}$)  
**Development Tool:** AMD / Xilinx Vivado 2025.2  

---

## 1. Project Overview & Deliverables Summary

This submission package contains the complete RTL design, testbenches, Python golden models, formal verification scripts, RV32 firmware, pre-compiled bitstream, and official course project report formatted strictly according to the **IIT Mandi SCEE Course Project Report Template** (`VL401_G10_P10.pdf`, 16 pages, Sections 1--12 in exactly 12 pages) as instructed by Dr. Bikram Paul.

### Deliverables Checklist (per Course Specification Sheet)

| Deliverable | Description | Implementation Status & Key Results |
| :--- | :--- | :--- |
| **Deliverable 1: SQNR Evaluation** | Fixed-point golden model compared with IEEE-754 double-precision NumPy FFT. | **Passed:** Single-tone mean SQNR = **69.05 dB** (Peak 75.47 dB), two-tone dynamic sweep $>60.54\text{ dB}$, Gaussian noise Monte-Carlo = **54.91 dB $\pm$ 0.33 dB**. |
| **Deliverable 2: Resource Table** | Resource & $F_{\max}$ comparison table: Radix-2 baseline vs. Radix-$2^2$ vs. literature CORDIC. | **Passed:** 5,110 Slice LUTs (29.0%), 4,649 FFs (13.2%), **10 DSP48E1 slices** (12.5%), 7 BRAMs (11.7%) @ 125 MHz. |
| **Deliverable 3: Throughput & Latency** | Streaming throughput (MS/s) and exact pipeline latency (cycles). | **Passed:** Continuous **125 MSamples/s** streaming throughput (1 sample/clock); exact **352 clock cycles** latency ($2.816\ \mu\text{s}$). |
| **Deliverable 4: Formal Proof** | CTL safety proof that ping-pong read and write banks never coincide. | **Passed:** Formal mathematical induction proof and NuSMV model-checking of $\mathbf{AG}(\text{wr\_bank} \neq \text{rd\_bank})$. |
| **Deliverable 5: Live Hardware Demo** | Spectrum bars on VGA, UART dominant frequency output, and on-chip ILA verification. | **Passed:** Hardware bitstream verified on Zybo Z7-10. UART transmits `PEAK:032\r\n`, VGA renders 640x480@60Hz spectrum, Vivado ILA captures `peak_bin = 0x20` (Bin 32) in silicon. |

---

## 2. Directory Structure

```
submission/
├── README.md                      # Comprehensive project documentation & reproduction guide
├── VL401_G10_P10.pdf              # Official IIT Mandi Report (Sections 1-12 in exactly 12 pages)
├── VL401_G10_P10.tex              # Official IIT Mandi LaTeX template source code
├── report/
│   ├── VL401_G10_P10.pdf          # Official IIT Mandi course project report
│   ├── VL401_G10_P10.tex          # Official IIT Mandi LaTeX source code
│   ├── report.pdf                 # Alternative IEEE conference format report
│   ├── report.tex                 # IEEE conference LaTeX source code
│   └── Images_for_Report/         # All 20 embedded figures, waveforms & FPGA_Video.mp4
├── rtl/                           # Synthesizable Verilog RTL source files & ROM hexes
│   ├── bf2i.v                     # Butterfly I unit (decimation-in-frequency)
│   ├── bf2ii.v                    # Butterfly II unit (conditional -j rotation)
│   ├── cmul_q15.v                 # 3-cycle pipelined Karatsuba 4-to-3 complex multiplier
│   ├── twiddle_rom.v              # Twiddle factor ROM interface (128x16 entries)
│   ├── twiddle_rom_r.hex          # Real twiddle cosine values (Q1.15)
│   ├── twiddle_rom_i.hex          # Imaginary twiddle -sine values (Q1.15)
│   ├── sdf_stage.v                # Parameterized Radix-2^2 SDF stage module
│   ├── fft256_top.v               # 4-stage cascaded 256-point FFT pipeline
│   ├── mag_approx.v               # Pipelined alpha-max + 3/8 beta-min magnitude unit
│   ├── peak_detector.v            # Wire-speed peak bin & magnitude detector (bins 1..127)
│   ├── pingpong_buf.v             # Dual-bank ping-pong buffer with bit-reversal read
│   ├── dds.v                      # Direct Digital Synthesis cosine test generator
│   ├── dds_cos_rom.hex            # Cosine lookup table for DDS excitation
│   ├── clk_div.v                  # Clock prescalers for 25 MHz VGA & LED diagnostics
│   ├── seg7_display.v             # Diagnostic 7-segment / LED pulse multiplexer
│   ├── uart_tx.v                  # 115200-baud UART ASCII transmitter ("PEAK:xxx\r\n")
│   ├── uart_rx.v                  # Asynchronous UART receiver
│   ├── vga_spectrum.v             # VESA 640x480@60Hz spectrum bar video rasterizer
│   ├── fft_system_top.v           # Complete integrated SoC top with AXI4-Lite CSR
│   └── zybo_wrapper.v             # Physical top-level wrapper with ILA debug cores
├── constraints/
│   ├── zybo_z10.xdc               # Target board constraints (Zybo Z7-10, 125 MHz)
│   └── nexys_a7.xdc               # Legacy reference constraints
├── tb/
│   ├── tb_system.v                # Top-level SoC testbench (excites DDS, tests UART & VGA)
│   ├── tb_fft256.v                # FFT core testbench against hex vectors
│   ├── tb_fft256_debug.v          # Intermediate pipeline stage debug testbench
│   ├── tb_sdf_stage.v             # Unit testbench for single SDF stage
│   ├── tb_bf2i.v                  # Butterfly I unit testbench
│   ├── tb_cmul_q15.v              # Karatsuba complex multiplier testbench
│   ├── tb_pingpong.v              # Ping-pong buffer unit testbench
│   ├── tb_system_waves.wcfg       # Vivado simulation waveform configuration
│   ├── uart_vga_sim_results.log   # Automated simulation execution log
│   └── vectors/                   # Hex stimulus and expected vectors
├── golden_model/
│   ├── fft_golden.py              # Bit-accurate hardware-equivalent Python model
│   ├── sqnr_analysis.py           # Comprehensive SQNR test suite (Single, Two-Tone, Noise)
│   ├── render_vga_display.py      # Virtual 640x480 VGA display rasterizer
│   ├── diagnose_shift.py          # Stage scaling and dynamic range diagnosis
│   ├── trace_stage3.py            # Terminal stage bit-accurate tracer
│   ├── regenerate_vectors.py      # Test vector generator
│   └── data/                      # SQNR CSV data files and generated plots
├── sw/
│   ├── fft_main.c                 # RV32I C firmware for AXI4-Lite CSR polling & peak find
│   ├── link.ld                    # Linker script for RV32 memory map
│   ├── startup.S                  # RV32 bare-metal startup routine
│   └── Makefile                   # GCC cross-compilation makefile
├── formal/
│   └── pingpong_buf.smv           # NuSMV model checking script for CTL safety proof
├── bitstream/
│   ├── zybo_wrapper.bit           # Pre-compiled FPGA bitstream for Zybo Z7-10
│   └── zybo_wrapper.ltx           # Vivado ILA debug probes file
└── scripts/
    └── create_vivado_project.tcl  # 1-click script to recreate entire Vivado project
```

---

## 3. How to Recreate the Vivado Project

You can recreate the entire project with all source files, constraints, and simulation sets with a single Tcl command in Vivado:

1. Open AMD / Xilinx Vivado (2025.2 or earlier).
2. In the Tcl Console, navigate to this submission directory:
   ```tcl
   cd {/path/to/submission}
   source scripts/create_vivado_project.tcl
   ```
3. Vivado will automatically:
   * Create project `fft_spectrum` targeting part `xc7z010clg400-1`.
   * Add all RTL source files, ROM hex initialization files, and constraints.
   * Configure synthesis and implementation runs at 125 MHz.

---

## 4. How to Run Verilog Simulation

To verify the integrated design before hardware programming:

### Method A: Standalone Batch Simulation (Fastest)
From the command prompt / PowerShell:
```powershell
xvlog -sv rtl/*.v tb/tb_system.v
xelab -timescale 1ns/1ps -top tb_system -snapshot tb_system_snap
xsim tb_system_snap -R
```
The testbench will report:
```
[TB_SYS] Reset released @ 125 MHz.
[TB_SYS] irq_frame_done seen at cycle 616
[TB_SYS] CSR_PEAK_BIN = 32 (expected 32)
[TB_SYS] CSR_PEAK_MAG = 11325
[TB_SYS] Waiting for UART 'PEAK:032\r\n'...
PEAK:032
[TB_SYS] PASS: UART output is 'PEAK:032\r\n'
```

### Method B: GUI Simulation in Vivado
1. Set `tb_system` as the simulation top.
2. Click **Run Simulation $\to$ Run Behavioral Simulation**.
3. Open `tb/tb_system_waves.wcfg` to observe the pipeline stages, ping-pong toggling, and UART serializer.

---

## 5. How to Program the Physical Zybo Z7-10 Board

A pre-compiled bitstream with on-chip ILA debug probes is provided in `bitstream/`:
* `bitstream/zybo_wrapper.bit`
* `bitstream/zybo_wrapper.ltx`

### Programming Steps:
1. Connect the Zybo Z7-10 board via micro-USB (PROG / UART port) and power it on.
2. Open Vivado **Hardware Manager** $\to$ **Open Target** $\to$ **Auto Connect**.
3. Right-click the FPGA device `xc7z010_1` $\to$ **Program Device**.
4. Select `bitstream/zybo_wrapper.bit` as the Bitstream file, and `bitstream/zybo_wrapper.ltx` as the Debug probes file.
5. Click **Program**.

### Board Verification Indicators:
* **LD0 (`csr_run`):** Solid ON (Core running in auto-start autonomous mode).
* **LD1 (Heartbeat):** Blinking at $\sim 7.45\text{ Hz}$ (confirms 125 MHz clock is alive via bit 23 of free-running counter).
* **LD2 (Peak Pulse):** Blinking at $\sim 14.9\text{ Hz}$ (confirms continuous 488 kHz frame completions).
* **LD3 (`peak_bin[5]`):** Steady ON (indicates Bin 32 ($00100000_2$) is detected).
* **BTN0 (Reset):** Press and hold BTN0 to hold the system in synchronous reset; releasing resumes continuous operation.
* **Vivado ILA:** The Hardware Manager ILA window will trigger on `u_sys/peak_done == 1`, capturing:
  * `peak_bin[7:0] = 0x20` (Bin 32)
  * `peak_mag[16:0] = 0x02D06` (11,526)

---

## 6. How to Run Python Golden Model & SQNR Analysis

The golden model requires Python 3.8+ with `numpy` and `matplotlib`:

```bash
cd golden_model
python sqnr_analysis.py
```

This runs:
1. **Single-Tone Sweep:** Sweeps frequency bins 1 to 127, printing mean SQNR (69.05 dB) and generating `data/plots/sqnr_vs_frequency.png`.
2. **Amplitude Sweep:** Sweeps tone amplitude from $-60\text{ dBFS}$ to $0\text{ dBFS}$, generating `data/plots/sqnr_vs_amplitude.png`.
3. **Two-Tone Intermodulation Test:** Sweeps frequency separation $\Delta k \in [1, 64]$ and outputs Table III.
4. **Gaussian Noise Monte-Carlo:** Runs 50 random noise seeds, reporting mean SQNR = 54.91 dB.

To render the virtual 640x480 VGA display:
```bash
python render_vga_display.py
```
Outputs `vga_display_virtual.png` in the current folder.

---

## 7. How to Verify Formal CTL Safety in NuSMV

To formally verify the ping-pong buffer mutual exclusion invariant:
```bash
cd formal
nusmv pingpong_buf.smv
```
NuSMV evaluates all reachable states and prints:
```
-- specification AG (wr_bank != rd_bank) is true
```

---

## 8. How to Recompile the LaTeX Report

To recompile the IEEE conference report:
```bash
cd report
pdflatex report.tex
pdflatex report.tex
```
Outputs `report.pdf` (9 pages, standard IEEE double-column format).
