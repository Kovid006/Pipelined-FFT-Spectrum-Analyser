// =============================================================================
// tb_system.v  —  System-level testbench for fft_system_top
//                 Zybo Z7-10 edition: 125 MHz clock, no seg7 ports
//                 (Vivado-compatible Verilog-2001)
// =============================================================================
// Tests:
//   1. DDS mode bin=32, waits for irq_frame_done
//   2. Reads back CSR_PEAK_BIN, asserts it equals 32
//   3. Monitors UART TX output, checks for "PEAK:032\r\n"
//   4. Checks VGA HSYNC toggles
//
// Clock: 125 MHz → period = 8 ns
// UART:  115200 baud → 1 bit = 1,000,000,000/115200 = 8680.6 ns
// =============================================================================
`timescale 1ns/1ps

module tb_system;

    // =========================================================================
    // CSR address offsets
    // =========================================================================
    localparam [4:0] OFF_CTRL     = 5'h00;
    localparam [4:0] OFF_STATUS   = 5'h04;
    localparam [4:0] OFF_PEAK_BIN = 5'h08;
    localparam [4:0] OFF_PEAK_MAG = 5'h0C;
    localparam [4:0] OFF_RD_ADDR  = 5'h10;
    localparam [4:0] OFF_RD_R     = 5'h14;
    localparam [4:0] OFF_RD_I     = 5'h18;
    localparam [4:0] OFF_CYCLES   = 5'h1C;

    // =========================================================================
    // DUT ports
    // =========================================================================
    reg         clk;
    reg         rst_n;

    // AXI4-Lite write channel
    reg  [4:0]  s_awaddr;  reg s_awvalid;  wire s_awready;
    reg  [31:0] s_wdata;   reg [3:0] s_wstrb;  reg s_wvalid;
    wire        s_wready;  wire [1:0] s_bresp;  wire s_bvalid;  reg s_bready;

    // AXI4-Lite read channel
    reg  [4:0]  s_araddr;  reg s_arvalid;  wire s_arready;
    wire [31:0] s_rdata;   wire [1:0] s_rresp;  wire s_rvalid;  reg s_rready;

    // Other
    wire        uart_tx;   reg uart_rx;
    wire        irq_frame_done, irq_peak_done;
    wire [3:0]  vga_r, vga_g, vga_b;
    wire        vga_hsync, vga_vsync;
    wire [3:0]  led;

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    fft_system_top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_awaddr      (s_awaddr),   .s_awvalid  (s_awvalid),  .s_awready  (s_awready),
        .s_wdata       (s_wdata),    .s_wstrb    (s_wstrb),    .s_wvalid   (s_wvalid),
        .s_wready      (s_wready),   .s_bresp    (s_bresp),    .s_bvalid   (s_bvalid),
        .s_bready      (s_bready),
        .s_araddr      (s_araddr),   .s_arvalid  (s_arvalid),  .s_arready  (s_arready),
        .s_rdata       (s_rdata),    .s_rresp    (s_rresp),    .s_rvalid   (s_rvalid),
        .s_rready      (s_rready),
        .uart_tx       (uart_tx),    .uart_rx    (uart_rx),
        .irq_frame_done(irq_frame_done),
        .irq_peak_done (irq_peak_done),
        .vga_r         (vga_r),      .vga_g      (vga_g),      .vga_b      (vga_b),
        .vga_hsync     (vga_hsync),  .vga_vsync  (vga_vsync),
        .led           (led)
    );

    // =========================================================================
    // Clock — 125 MHz (8 ns period)
    // =========================================================================
    initial clk = 1'b0;
    always #4 clk = ~clk;

    // =========================================================================
    // AXI4-Lite write task
    // =========================================================================
    task axi_write;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(negedge clk);
            s_awaddr = addr; s_awvalid = 1'b1;
            s_wdata  = data; s_wstrb   = 4'hF; s_wvalid = 1'b1;
            @(posedge clk);
            while (!s_awready || !s_wready) @(posedge clk);
            @(negedge clk); s_awvalid = 1'b0; s_wvalid = 1'b0;
            s_bready = 1'b1;
            @(posedge clk); while (!s_bvalid) @(posedge clk);
            @(negedge clk); s_bready = 1'b0;
        end
    endtask

    // =========================================================================
    // AXI4-Lite read task
    // =========================================================================
    reg [31:0] rd_buf;
    task axi_read;
        input  [4:0]  addr;
        output [31:0] rdata;
        begin
            @(negedge clk);
            s_araddr = addr; s_arvalid = 1'b1; s_rready = 1'b1;
            @(posedge clk); while (!s_arready) @(posedge clk);
            @(negedge clk); s_arvalid = 1'b0;
            @(posedge clk); while (!s_rvalid)  @(posedge clk);
            rdata = s_rdata;
            @(negedge clk); s_rready = 1'b0;
        end
    endtask

    // =========================================================================
    // UART RX monitor (time-based, 125 MHz clock, 115200 baud)
    //   1 bit period = 1e9/115200 = 8680.6 ns
    // =========================================================================
    localparam real BIT_NS  = 1.0e9 / 115200.0;
    localparam real HALF_NS = BIT_NS / 2.0;

    reg [7:0] uart_buf [0:63];
    integer   uart_ptr;
    integer   uart_done;
    integer   u_bit;
    reg [7:0] uart_shift;

    initial begin uart_rx = 1'b1; uart_ptr = 0; uart_done = 0; end

    initial begin
        uart_ptr = 0;
        forever begin
            @(negedge uart_tx);         // detect start bit
            #(HALF_NS);                 // wait to mid-start-bit
            if (uart_tx == 1'b0) begin
                uart_shift = 8'h00;
                for (u_bit = 0; u_bit < 8; u_bit = u_bit + 1) begin
                    #(BIT_NS);
                    uart_shift[u_bit] = uart_tx;
                end
                #(BIT_NS);             // stop bit
                if (uart_ptr < 64) begin
                    uart_buf[uart_ptr] = uart_shift;
                    $write("%c", uart_shift);
                    uart_ptr = uart_ptr + 1;
                end
                if (uart_ptr >= 10) uart_done = 1;
            end
        end
    end

    // =========================================================================
    // IRQ latches
    // =========================================================================
    reg irq_seen, peak_irq_seen;
    initial begin irq_seen = 0; peak_irq_seen = 0; end
    always @(posedge clk) begin
        if (irq_frame_done) irq_seen      <= 1'b1;
        if (irq_peak_done)  peak_irq_seen <= 1'b1;
    end

    // =========================================================================
    // Main test
    // =========================================================================
    integer wait_cnt;
    integer test_pass;
    integer peak_bin_val;
    integer peak_mag_val;

    initial begin
        // Init AXI
        s_awaddr=5'h0; s_awvalid=1'b0; s_wdata=32'h0; s_wstrb=4'hF; s_wvalid=1'b0;
        s_bready=1'b0; s_araddr=5'h0; s_arvalid=1'b0; s_rready=1'b0;
        uart_rx=1'b1; rst_n=1'b0; test_pass=1;

        // 10 cycles reset
        repeat(10) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        $display("[TB_SYS] Reset released @ 125 MHz. Configuring DDS bin=32...");

        // -----------------------------------------------------------------
        // CTRL = bin=32 | src=DDS | run=1
        //   bits[15:8]=32=0x20, bits[1:0]=01 → 0x0000_2001
        // -----------------------------------------------------------------
        axi_write(OFF_CTRL, 32'h0000_2001);
        $display("[TB_SYS] CTRL written. Waiting for irq_frame_done...");

        // Allow up to 2000 cycles (pipeline latency ≈ 352 + 256 ≈ 608 cycles)
        wait_cnt = 0;
        while (!irq_seen && wait_cnt < 2000) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end

        if (!irq_seen) begin
            $display("[TB_SYS] FAIL: irq_frame_done not seen within 2000 cycles");
            test_pass = 0;
        end else
            $display("[TB_SYS] irq_frame_done seen at cycle %0d", wait_cnt);

        // Wait for peak_done
        wait_cnt = 0;
        while (!peak_irq_seen && wait_cnt < 500) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        if (peak_irq_seen) $display("[TB_SYS] irq_peak_done seen OK");

        // Read CSRs
        axi_read(OFF_PEAK_BIN, rd_buf);
        peak_bin_val = rd_buf[7:0];
        $display("[TB_SYS] CSR_PEAK_BIN = %0d (expected 32)", peak_bin_val);
        if (peak_bin_val !== 32) begin
            $display("[TB_SYS] FAIL: peak_bin=%0d expected 32", peak_bin_val);
            test_pass = 0;
        end

        axi_read(OFF_PEAK_MAG, rd_buf);
        peak_mag_val = rd_buf;
        $display("[TB_SYS] CSR_PEAK_MAG = %0d", peak_mag_val);
        if (peak_mag_val == 0) begin
            $display("[TB_SYS] FAIL: peak_mag is zero"); test_pass = 0;
        end

        // Wait for UART "PEAK:032\r\n"
        // 10 chars × 10 bits × 8681 ns = 868100 ns ≈ 109000 × 8ns cycles
        $display("[TB_SYS] Waiting for UART 'PEAK:032\\r\\n'...");
        wait_cnt = 0;
        while (!uart_done && wait_cnt < 115000) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end

        if (!uart_done) begin
            $display("[TB_SYS] FAIL: UART did not output 10 chars"); test_pass = 0;
        end else begin
            if (uart_buf[0]=="P" && uart_buf[1]=="E" && uart_buf[2]=="A" &&
                uart_buf[3]=="K" && uart_buf[4]==":" &&
                uart_buf[5]=="0" && uart_buf[6]=="3" && uart_buf[7]=="2" &&
                uart_buf[8]==8'h0D && uart_buf[9]==8'h0A)
                $display("[TB_SYS] PASS: UART output is 'PEAK:032\\r\\n'");
            else begin
                $display("[TB_SYS] FAIL: UART string mismatch");
                test_pass = 0;
            end
        end

        // VGA HSYNC check: at 125 MHz with /5 CE → 25 MHz pixel clock
        // HSYNC goes low at h_cnt=656 → 656 pixels × 4 sys-cycles/pixel = 2624 sys-cycles
        wait_cnt = 0;
        while (vga_hsync && wait_cnt < 4000) begin
            @(posedge clk); wait_cnt = wait_cnt + 1;
        end
        if (wait_cnt < 4000)
            $display("[TB_SYS] VGA HSYNC toggled OK after %0d sys-cycles", wait_cnt);
        else
            $display("[TB_SYS] NOTE: VGA HSYNC did not toggle in 4000 cycles");

        // Final verdict
        $display("====================================================");
        if (test_pass) $display("tb_system: ALL TESTS PASSED");
        else           $display("tb_system: SOME TESTS FAILED");
        $display("====================================================");
        $finish;
    end

    // =========================================================================
    // Timeout — 5 ms (at 125 MHz = 625,000 cycles)
    // =========================================================================
    initial begin
        #5_000_000;
        $display("TIMEOUT: tb_system exceeded 5ms");
        $finish;
    end

    initial begin
        $dumpfile("tb_system.vcd");
        $dumpvars(1, tb_system);
    end

endmodule
