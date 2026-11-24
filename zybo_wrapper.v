// =============================================================================
// zybo_wrapper.v  —  Board-level wrapper for Zybo Z7-10
// =============================================================================
// Handles board-specific details so fft_system_top.v stays board-agnostic:
//   - Inverts active-HIGH BTN0 to active-LOW rst_n
//   - Ties off unused AXI ports (design runs in standalone / free-running mode)
//   - Exposes the board I/O defined in zybo_z10.xdc
//
// XDC synthesis top module: zybo_wrapper
// =============================================================================
module zybo_wrapper (
    // Board clock (125 MHz, pin K17)
    input  wire        clk,

    // BTN0 = reset (active HIGH from push-button, inverted to active-LOW rst_n)
    input  wire        btn0_rst,

    // UART — PMOD JE pins (H17=TX, H18=RX)
    output wire        uart_tx,
    input  wire        uart_rx,

    // VGA
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,

    // LEDs (4, active HIGH)
    output wire [3:0]  led
);

    // -------------------------------------------------------------------------
    // Active-low reset from active-HIGH button
    // -------------------------------------------------------------------------
    wire rst_n = ~btn0_rst;

    // -------------------------------------------------------------------------
    // Tie-off AXI4-Lite CSR bus (no processor attached in standalone mode)
    // The FFT runs continuously at the default DDS bin (bin 32).
    // -------------------------------------------------------------------------
    wire [4:0]  s_awaddr  = 5'h00;
    wire        s_awvalid = 1'b0;
    wire [31:0] s_wdata   = 32'h0000_2001; // CTRL default: bin=32, src=DDS, run=1
    wire [3:0]  s_wstrb   = 4'hF;
    wire        s_wvalid  = 1'b0;
    wire        s_bready  = 1'b1;
    wire [4:0]  s_araddr  = 5'h00;
    wire        s_arvalid = 1'b0;
    wire        s_rready  = 1'b1;

    // Unused outputs from AXI slave
    wire        s_awready, s_wready, s_bvalid;
    wire [1:0]  s_bresp;
    wire        s_arready, s_rvalid;
    wire [31:0] s_rdata;
    wire [1:0]  s_rresp;
    wire        irq_frame_done, irq_peak_done;

    // -------------------------------------------------------------------------
    // Instantiate the FFT system top
    // -------------------------------------------------------------------------
    fft_system_top u_sys (
        .clk          (clk),
        .rst_n        (rst_n),
        // AXI write
        .s_awaddr     (s_awaddr),
        .s_awvalid    (s_awvalid),
        .s_awready    (s_awready),
        .s_wdata      (s_wdata),
        .s_wstrb      (s_wstrb),
        .s_wvalid     (s_wvalid),
        .s_wready     (s_wready),
        .s_bresp      (s_bresp),
        .s_bvalid     (s_bvalid),
        .s_bready     (s_bready),
        // AXI read
        .s_araddr     (s_araddr),
        .s_arvalid    (s_arvalid),
        .s_arready    (s_arready),
        .s_rdata      (s_rdata),
        .s_rresp      (s_rresp),
        .s_rvalid     (s_rvalid),
        .s_rready     (s_rready),
        // Other
        .uart_tx      (uart_tx),
        .uart_rx      (uart_rx),
        .irq_frame_done(irq_frame_done),
        .irq_peak_done (irq_peak_done),
        .vga_r        (vga_r),
        .vga_g        (vga_g),
        .vga_b        (vga_b),
        .vga_hsync    (vga_hsync),
        .vga_vsync    (vga_vsync),
        .led          (led)
    );

endmodule
