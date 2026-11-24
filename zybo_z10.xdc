## Zybo Z7-10 XDC Constraints
## Project: P10 Pipelined FFT Spectrum Analyser
## Target Part: xc7z010clg400-1  (Zynq-7010, PL-only design)
## Board: Digilent Zybo Z7-10
## Synthesis top: zybo_wrapper
##
## IMPORTANT: Verify all pin assignments against the official Digilent
## Zybo-Z7 master XDC at:
## https://github.com/Digilent/digilent-xdc/blob/master/Zybo-Z7-Master.xdc
## =============================================================================

# =============================================================================
# PRIMARY CLOCK — 125 MHz crystal oscillator (K17)
# =============================================================================
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 8.000 -name sys_clk_125 -waveform {0.000 4.000} [get_ports clk]

# =============================================================================
# RESET — BTN0 (K18, active HIGH from push-button)
# In zybo_wrapper.v:  rst_n = ~btn0_rst
# Press BTN0 to hold the design in reset.
# =============================================================================
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports btn0_rst]

# =============================================================================
# UART — PMOD JE connector
# JE Pin 1 (H17) = uart_tx  (FPGA → USB-UART adapter TX pin)
# JE Pin 2 (H18) = uart_rx  (USB-UART adapter RX pin → FPGA)
# Standard USB-UART adapter: connect TX→H17, RX→H18, GND→GND.
# =============================================================================
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports uart_tx]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33} [get_ports uart_rx]

# =============================================================================
# VGA (Zybo Z7 on-board VGA connector — 12-bit 4-4-4 RGB)
# =============================================================================
# Red channel (4 bits)
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}]

# Green channel (4 bits)
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}]

# Blue channel (4 bits)
# NOTE: R15 is not a valid pin on xc7z010clg400-1. Using P14 (JD pin 3).
# Verify this against your Pmod VGA wiring before generating bitstream.
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}]

# VGA sync (active low)
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports vga_hsync]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports vga_vsync]

# =============================================================================
# LEDs (4, active HIGH)
# =============================================================================
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

# =============================================================================
# PUSH BUTTONS (BTN1–BTN3, active HIGH) — not used in current design but
# uncomment if you add button-triggered bin sweep, etc.
# =============================================================================
# set_property -dict { PACKAGE_PIN P16   IOSTANDARD LVCMOS33 } [get_ports { btn1 }]
# set_property -dict { PACKAGE_PIN K19   IOSTANDARD LVCMOS33 } [get_ports { btn2 }]
# set_property -dict { PACKAGE_PIN Y16   IOSTANDARD LVCMOS33 } [get_ports { btn3 }]

# =============================================================================
# SLIDE SWITCHES (4, active HIGH) — not used in current design but
# uncomment to add manual bin / mode selection.
# =============================================================================
# set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
# set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]
# set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]
# set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]
# NOTE: T16 is shared with vga_b[3]. If you use SW3, comment out vga_b[3].

# =============================================================================
# TIMING CONSTRAINTS
# =============================================================================
# Asynchronous external inputs — pushbutton reset and UART RX
set_false_path -from [get_ports btn0_rst]
set_false_path -from [get_ports uart_rx]

# Asynchronous external outputs — LEDs, UART TX (115200 baud), and VGA pins
set_false_path -to [get_ports {led[*]}]
set_false_path -to [get_ports uart_tx]
set_false_path -to [get_ports vga_*]

# VGA pixel datapath multicycle constraint:
# Within vga_spectrum, h_cnt, v_cnt, and vga_r/g/b are enabled by clk_en_25m
# (1-cycle pulse every 5 cycles of 125 MHz = 25 MHz pixel rate).
# This gives a 40 ns budget (5 cycles of 8.0 ns).
set_multicycle_path -setup -from [get_cells -hier -filter {NAME =~ *u_vga/*cnt_reg* || NAME =~ *u_vga/wr_to_a_reg*}] -to [get_cells -hier -filter {NAME =~ *u_vga/vga_*_reg*}] 5
set_multicycle_path -hold -from [get_cells -hier -filter {NAME =~ *u_vga/*cnt_reg* || NAME =~ *u_vga/wr_to_a_reg*}] -to [get_cells -hier -filter {NAME =~ *u_vga/vga_*_reg*}] 4

# UART RX double-flop synchroniser ASYNC_REG constraints.
# NOTE: These cells do not exist when uart_rx is unconnected; constraint is intentionally
# left inactive. If UART RX is later wired up, uncomment the two lines below.
# set_property ASYNC_REG true [get_cells -hier -filter {NAME =~ *rxd_s1*}]
# set_property ASYNC_REG true [get_cells -hier -filter {NAME =~ *rxd_s*}]

# =============================================================================
# BITSTREAM / CONFIGURATION
# =============================================================================
# BITSTREAM.CONFIG.SPI_BUSWIDTH is not valid for Zynq (xc7z010).
# Use CONFIGRATE and CFGBVS instead.
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_IBUF_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 32 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {u_sys/pp_rd_data[0]} {u_sys/pp_rd_data[1]} {u_sys/pp_rd_data[2]} {u_sys/pp_rd_data[3]} {u_sys/pp_rd_data[4]} {u_sys/pp_rd_data[5]} {u_sys/pp_rd_data[6]} {u_sys/pp_rd_data[7]} {u_sys/pp_rd_data[8]} {u_sys/pp_rd_data[9]} {u_sys/pp_rd_data[10]} {u_sys/pp_rd_data[11]} {u_sys/pp_rd_data[12]} {u_sys/pp_rd_data[13]} {u_sys/pp_rd_data[14]} {u_sys/pp_rd_data[15]} {u_sys/pp_rd_data[16]} {u_sys/pp_rd_data[17]} {u_sys/pp_rd_data[18]} {u_sys/pp_rd_data[19]} {u_sys/pp_rd_data[20]} {u_sys/pp_rd_data[21]} {u_sys/pp_rd_data[22]} {u_sys/pp_rd_data[23]} {u_sys/pp_rd_data[24]} {u_sys/pp_rd_data[25]} {u_sys/pp_rd_data[26]} {u_sys/pp_rd_data[27]} {u_sys/pp_rd_data[28]} {u_sys/pp_rd_data[29]} {u_sys/pp_rd_data[30]} {u_sys/pp_rd_data[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 8 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {u_sys/peak_bin[0]} {u_sys/peak_bin[1]} {u_sys/peak_bin[2]} {u_sys/peak_bin[3]} {u_sys/peak_bin[4]} {u_sys/peak_bin[5]} {u_sys/peak_bin[6]} {u_sys/peak_bin[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 8 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {u_sys/peak_bin_lat[0]} {u_sys/peak_bin_lat[1]} {u_sys/peak_bin_lat[2]} {u_sys/peak_bin_lat[3]} {u_sys/peak_bin_lat[4]} {u_sys/peak_bin_lat[5]} {u_sys/peak_bin_lat[6]} {u_sys/peak_bin_lat[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 17 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {u_sys/mag_out[0]} {u_sys/mag_out[1]} {u_sys/mag_out[2]} {u_sys/mag_out[3]} {u_sys/mag_out[4]} {u_sys/mag_out[5]} {u_sys/mag_out[6]} {u_sys/mag_out[7]} {u_sys/mag_out[8]} {u_sys/mag_out[9]} {u_sys/mag_out[10]} {u_sys/mag_out[11]} {u_sys/mag_out[12]} {u_sys/mag_out[13]} {u_sys/mag_out[14]} {u_sys/mag_out[15]} {u_sys/mag_out[16]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 16 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {u_sys/fft_out_r[0]} {u_sys/fft_out_r[1]} {u_sys/fft_out_r[2]} {u_sys/fft_out_r[3]} {u_sys/fft_out_r[4]} {u_sys/fft_out_r[5]} {u_sys/fft_out_r[6]} {u_sys/fft_out_r[7]} {u_sys/fft_out_r[8]} {u_sys/fft_out_r[9]} {u_sys/fft_out_r[10]} {u_sys/fft_out_r[11]} {u_sys/fft_out_r[12]} {u_sys/fft_out_r[13]} {u_sys/fft_out_r[14]} {u_sys/fft_out_r[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 17 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {u_sys/peak_mag_lat[0]} {u_sys/peak_mag_lat[1]} {u_sys/peak_mag_lat[2]} {u_sys/peak_mag_lat[3]} {u_sys/peak_mag_lat[4]} {u_sys/peak_mag_lat[5]} {u_sys/peak_mag_lat[6]} {u_sys/peak_mag_lat[7]} {u_sys/peak_mag_lat[8]} {u_sys/peak_mag_lat[9]} {u_sys/peak_mag_lat[10]} {u_sys/peak_mag_lat[11]} {u_sys/peak_mag_lat[12]} {u_sys/peak_mag_lat[13]} {u_sys/peak_mag_lat[14]} {u_sys/peak_mag_lat[15]} {u_sys/peak_mag_lat[16]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 17 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {u_sys/peak_mag[0]} {u_sys/peak_mag[1]} {u_sys/peak_mag[2]} {u_sys/peak_mag[3]} {u_sys/peak_mag[4]} {u_sys/peak_mag[5]} {u_sys/peak_mag[6]} {u_sys/peak_mag[7]} {u_sys/peak_mag[8]} {u_sys/peak_mag[9]} {u_sys/peak_mag[10]} {u_sys/peak_mag[11]} {u_sys/peak_mag[12]} {u_sys/peak_mag[13]} {u_sys/peak_mag[14]} {u_sys/peak_mag[15]} {u_sys/peak_mag[16]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 16 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {u_sys/dds_out[0]} {u_sys/dds_out[1]} {u_sys/dds_out[2]} {u_sys/dds_out[3]} {u_sys/dds_out[4]} {u_sys/dds_out[5]} {u_sys/dds_out[6]} {u_sys/dds_out[7]} {u_sys/dds_out[8]} {u_sys/dds_out[9]} {u_sys/dds_out[10]} {u_sys/dds_out[11]} {u_sys/dds_out[12]} {u_sys/dds_out[13]} {u_sys/dds_out[14]} {u_sys/dds_out[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 8 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {u_sys/bin_cnt[0]} {u_sys/bin_cnt[1]} {u_sys/bin_cnt[2]} {u_sys/bin_cnt[3]} {u_sys/bin_cnt[4]} {u_sys/bin_cnt[5]} {u_sys/bin_cnt[6]} {u_sys/bin_cnt[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 16 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list {u_sys/fft_out_i[0]} {u_sys/fft_out_i[1]} {u_sys/fft_out_i[2]} {u_sys/fft_out_i[3]} {u_sys/fft_out_i[4]} {u_sys/fft_out_i[5]} {u_sys/fft_out_i[6]} {u_sys/fft_out_i[7]} {u_sys/fft_out_i[8]} {u_sys/fft_out_i[9]} {u_sys/fft_out_i[10]} {u_sys/fft_out_i[11]} {u_sys/fft_out_i[12]} {u_sys/fft_out_i[13]} {u_sys/fft_out_i[14]} {u_sys/fft_out_i[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list u_sys/fft_out_vld]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list u_sys/peak_done]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list u_sys/pp_frame_done]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
