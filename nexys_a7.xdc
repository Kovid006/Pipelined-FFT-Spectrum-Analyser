## Nexys A7 100T — XDC Constraints
## Project: P10 Pipelined FFT Spectrum Analyser
## Target: xc7a100tcsg324-1
## Vivado 2022.x compatible
## =============================================================================
## Notes:
##   All timing constraints reference the 100 MHz system clock.
##   VGA uses a 25 MHz clock-enable (not a separate clock domain), so a
##   generated_clock on the CE-driven path is not required.
## =============================================================================

# =============================================================================
# PRIMARY CLOCK — W5 (100 MHz crystal on Nexys A7)
# =============================================================================
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -name sys_clk_100 -period 10.000 -waveform {0.000 5.000} [get_ports { clk }]

# =============================================================================
# RESET — CPU_RESETN (active-low, button C12 on Nexys A7)
# =============================================================================
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { rst_n }]

# =============================================================================
# UART  (USB-UART via CP2105 on Nexys A7)
# =============================================================================
set_property -dict { PACKAGE_PIN D4  IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]
set_property -dict { PACKAGE_PIN C4  IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]

# =============================================================================
# VGA  (Standard Nexys A7 VGA header — 12-bit color)
# =============================================================================
# Red channel (4 bits)
set_property -dict { PACKAGE_PIN A3  IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }]
set_property -dict { PACKAGE_PIN B4  IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }]
set_property -dict { PACKAGE_PIN C5  IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }]
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }]

# Green channel (4 bits)
set_property -dict { PACKAGE_PIN C6  IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }]
set_property -dict { PACKAGE_PIN A5  IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }]
set_property -dict { PACKAGE_PIN B6  IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }]
set_property -dict { PACKAGE_PIN A6  IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }]

# Blue channel (4 bits)
set_property -dict { PACKAGE_PIN B7  IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }]
set_property -dict { PACKAGE_PIN C7  IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }]
set_property -dict { PACKAGE_PIN D7  IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }]
set_property -dict { PACKAGE_PIN D8  IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }]

# VGA sync
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { vga_hsync }]
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports { vga_vsync }]

# =============================================================================
# 7-SEGMENT DISPLAY (8 digits, multiplexed, common anode)
# =============================================================================
# Segments (active-low)
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { seg[0] }]
set_property -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 } [get_ports { seg[1] }]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { seg[2] }]
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { seg[3] }]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { seg[4] }]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { seg[5] }]
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports { seg[6] }]

# Decimal point (active-low)
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { dp }]

# Digit enables (active-low)
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { an[0] }]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { an[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { an[2] }]
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports { an[3] }]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { an[4] }]
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { an[5] }]
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports { an[6] }]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { an[7] }]

# =============================================================================
# PUSH BUTTONS (active-high)
# =============================================================================
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { btnc }]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports { btnu }]
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports { btnl }]
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { btnr }]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { btnd }]

# =============================================================================
# SLIDE SWITCHES (16, active-high)
# =============================================================================
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { sw[0]  }]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { sw[1]  }]
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports { sw[2]  }]
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports { sw[3]  }]
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports { sw[4]  }]
set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports { sw[5]  }]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { sw[6]  }]
set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS33 } [get_ports { sw[7]  }]
set_property -dict { PACKAGE_PIN T8  IOSTANDARD LVCMOS33 } [get_ports { sw[8]  }]
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS33 } [get_ports { sw[9]  }]
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports { sw[10] }]
set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports { sw[11] }]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports { sw[12] }]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports { sw[13] }]
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports { sw[14] }]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports { sw[15] }]

# =============================================================================
# LEDs (16, active-high)
# =============================================================================
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { led[0]  }]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { led[1]  }]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { led[2]  }]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { led[3]  }]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { led[4]  }]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { led[5]  }]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { led[6]  }]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { led[7]  }]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { led[8]  }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { led[9]  }]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { led[10] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { led[11] }]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports { led[12] }]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { led[13] }]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { led[14] }]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports { led[15] }]

# =============================================================================
# TIMING CONSTRAINTS
# =============================================================================
# Input delay (from switches and buttons — board traces ~2ns)
set_input_delay  -clock sys_clk_100 -max 4.0 [get_ports { sw[*] btn* }]
set_input_delay  -clock sys_clk_100 -min 1.0 [get_ports { sw[*] btn* }]

# Output delay (to LEDs, 7-seg, VGA — FPGA drives board loads)
set_output_delay -clock sys_clk_100 -max 4.0 [get_ports { led[*] seg[*] an[*] dp }]
set_output_delay -clock sys_clk_100 -min 0.0 [get_ports { led[*] seg[*] an[*] dp }]
set_output_delay -clock sys_clk_100 -max 4.0 [get_ports { vga_* }]
set_output_delay -clock sys_clk_100 -min 0.0 [get_ports { vga_* }]

# UART — asynchronous input
set_property ASYNC_REG true [get_cells -hier -filter {NAME =~ *uart_rx_sync*}]

# =============================================================================
# BITSTREAM / CONFIGURATION
# =============================================================================
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4    [current_design]
set_property CONFIG_VOLTAGE              3.3    [current_design]
set_property CFGBVS                      VCCO   [current_design]
