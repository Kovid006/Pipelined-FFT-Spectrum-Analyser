// =============================================================================
// fft_system_top.v  —  Complete FFT Spectrum Analyser System Top
//                       Zybo Z7-10 edition  (125 MHz, Vivado/Verilog-2001)
// =============================================================================
// Board: Zybo Z7-10 (xc7z010clg400-1)
// Clock: 125 MHz (K17 oscillator)
// Reset: active-LOW (driven by wrapper; BTN0 active-HIGH inverted externally)
//
// Integrates:
//   DDS → FFT pipeline (256-pt Radix-2^2 SDF, Q1.15) → ping-pong buffer
//   → magnitude approx → peak detector
//   → UART TX "PEAK:xxx\r\n" @ 115200 baud (PMOD JE: H17=TX, H18=RX)
//   → VGA spectrum display 640×480@60Hz (25 MHz CE from 125 MHz / 5)
//   → 4 LEDs: status indicators
//   → AXI4-Lite CSR for external controller
//
// CSR Map (5-bit byte address, 32-bit words):
//   0x00 CTRL      WR  [15:8]=DDS_bin  [1]=src_sel(0=DDS)  [0]=run
//   0x04 STATUS    RD  [2]=peak_done   [1]=frame_done       [0]=run
//   0x08 PEAK_BIN  RD  [7:0]=dominant bin index (1..127)
//   0x0C PEAK_MAG  RD  [16:0]=magnitude approximation
//   0x10 RD_ADDR   WR  [7:0]=bin to read (latches next cycle)
//   0x14 RD_DATA_R RD  [15:0]=real part Q1.15
//   0x18 RD_DATA_I RD  [15:0]=imag part Q1.15
//   0x1C CYCLES    RD  [31:0]=free-running cycle counter
// =============================================================================
module fft_system_top (
    input  wire         clk,        // 125 MHz from Zybo oscillator
    input  wire         rst_n,      // active-low (BTN0 inverted in wrapper)

    // -----------------------------------------------------------------
    // AXI4-Lite CSR slave (5-bit byte address → 8 word registers)
    // -----------------------------------------------------------------
    input  wire [4:0]   s_awaddr,
    input  wire         s_awvalid,
    output reg          s_awready,
    input  wire [31:0]  s_wdata,
    input  wire [3:0]   s_wstrb,
    input  wire         s_wvalid,
    output reg          s_wready,
    output reg  [1:0]   s_bresp,
    output reg          s_bvalid,
    input  wire         s_bready,

    input  wire [4:0]   s_araddr,
    input  wire         s_arvalid,
    output reg          s_arready,
    output reg  [31:0]  s_rdata,
    output reg  [1:0]   s_rresp,
    output reg          s_rvalid,
    input  wire         s_rready,

    // -----------------------------------------------------------------
    // UART (8N1, 115200 baud)
    // Connect: uart_tx → PMOD JE pin 1 (H17)
    //          uart_rx ← PMOD JE pin 2 (H18)
    // -----------------------------------------------------------------
    output wire         uart_tx,
    input  wire         uart_rx,

    // -----------------------------------------------------------------
    // Interrupts (1-cycle pulses)
    // -----------------------------------------------------------------
    output wire         irq_frame_done,
    output wire         irq_peak_done,

    // -----------------------------------------------------------------
    // VGA 4-bit 12-colour (Zybo Z7 VGA connector)
    // -----------------------------------------------------------------
    output wire [3:0]   vga_r,
    output wire [3:0]   vga_g,
    output wire [3:0]   vga_b,
    output wire         vga_hsync,
    output wire         vga_vsync,

    // -----------------------------------------------------------------
    // LEDs (4 on Zybo Z7-10, active HIGH)
    //   LD0 = csr_run   (system active)
    //   LD1 = frame_done toggle (flickers at frame rate)
    //   LD2 = peak_done  pulse (flickers when peak found)
    //   LD3 = peak_bin[6] (bit 6 of peak bin — visual indicator)
    // -----------------------------------------------------------------
    output wire [3:0]   led
);

    // =========================================================================
    // Suppress unused-input warning
    // =========================================================================
    wire _rx_unused  = uart_rx;
    wire _str_unused = |s_wstrb;

    // =========================================================================
    // CSR registers
    // =========================================================================
    reg         csr_run;
    reg         csr_src;        // 0 = DDS, 1 = external (not wired here)
    reg [7:0]   csr_dds_bin;   // DDS target bin 0..127  (default 32)
    reg [7:0]   csr_rd_addr;   // ping-pong bin read address

    // =========================================================================
    // Free-running cycle counter
    // =========================================================================
    reg [31:0] cycle_cnt;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) cycle_cnt <= 32'h0;
        else        cycle_cnt <= cycle_cnt + 32'd1;

    // =========================================================================
    // FFT input framing  (256 consecutive samples per frame)
    // =========================================================================
    reg [7:0]  frame_cnt;
    reg        fft_in_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin frame_cnt <= 8'd0; fft_in_v <= 1'b0; end
        else if (!csr_run) begin frame_cnt <= 8'd0; fft_in_v <= 1'b0; end
        else begin
            fft_in_v  <= 1'b1;
            frame_cnt <= (frame_cnt == 8'd255) ? 8'd0 : frame_cnt + 8'd1;
        end
    end

    // =========================================================================
    // DDS cosine generator
    //   Phase increment for bin k = k × 256  (16-bit phase accumulator)
    //   = k × (2^16 / 256) → correct for 256-point FFT at any sample rate
    // =========================================================================
    (* mark_debug = "true" *) wire signed [15:0] dds_out;

    dds u_dds (
        .clk      (clk),
        .rst_n    (rst_n),
        .en       (fft_in_v && !csr_src),
        .freq_word({csr_dds_bin, 8'h00}),   // phase inc = bin × 256
        .out      (dds_out)
    );

    // =========================================================================
    // FFT input mux
    // =========================================================================
    wire signed [15:0] fft_in_r   = csr_src ? 16'sd0  : dds_out;
    wire               fft_in_vld = csr_run && fft_in_v;

    // =========================================================================
    // FFT pipeline (256-pt Radix-2^2 SDF, Q1.15)
    // Pipeline latency ≈ 352 clock cycles
    // =========================================================================
    // --- ILA probes: FFT I/O ---
    (* mark_debug = "true" *) wire         fft_out_vld;
    (* mark_debug = "true" *) wire signed [15:0] fft_out_r, fft_out_i;

    fft256_top u_fft (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (fft_in_vld),
        .in_r     (fft_in_r),
        .in_i     (16'sd0),
        .out_valid(fft_out_vld),
        .out_r    (fft_out_r),
        .out_i    (fft_out_i)
    );

    // =========================================================================
    // Ping-pong output buffer (bit-reversed write, natural-order read)
    // =========================================================================
    (* mark_debug = "true" *) wire [31:0]  pp_rd_data;
    (* mark_debug = "true" *) wire         pp_frame_done;

    pingpong_buf u_pp (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_valid  (fft_out_vld),
        .wr_r      (fft_out_r),
        .wr_i      (fft_out_i),
        .rd_addr   (csr_rd_addr),
        .rd_data   (pp_rd_data),
        .frame_done(pp_frame_done)
    );

    // =========================================================================
    // Magnitude approximation  (2-stage pipelined: Stage 1 = abs, Stage 2 = sum)
    // =========================================================================
    (* mark_debug = "true" *) wire [16:0] mag_out;
    mag_approx u_mag (
        .clk  (clk),
        .rst_n(rst_n),
        .re   (fft_out_r),
        .im   (fft_out_i),
        .mag  (mag_out)
    );

    // =========================================================================
    // FFT output sample counter (tracks position in bit-reversed output stream, 0..255)
    // =========================================================================
    reg [7:0] sample_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             sample_cnt <= 8'd0;
        else if (pp_frame_done) sample_cnt <= 8'd0;
        else if (fft_out_vld)   sample_cnt <= sample_cnt + 8'd1;
    end

    // Bit-reverse 8-bit sample_cnt to get true natural frequency bin (0..255)
    wire [7:0] natural_bin = {sample_cnt[0], sample_cnt[1], sample_cnt[2], sample_cnt[3],
                              sample_cnt[4], sample_cnt[5], sample_cnt[6], sample_cnt[7]};

    // Keep bin_cnt alias for debug probes
    (* mark_debug = "true" *) wire [7:0] bin_cnt = natural_bin;

    // =========================================================================
    // 2-stage pipeline matching u_mag latency (2 cycles).
    // Aligns natural_bin and frame boundary markers with the registered mag_out.
    // =========================================================================
    reg [7:0]  natural_bin_p1, natural_bin_p2;
    reg [7:0]  sample_cnt_p1,  sample_cnt_p2;
    reg        fft_out_vld_p1, fft_out_vld_p2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            natural_bin_p1 <= 8'd0;
            natural_bin_p2 <= 8'd0;
            sample_cnt_p1  <= 8'd0;
            sample_cnt_p2  <= 8'd0;
            fft_out_vld_p1 <= 1'b0;
            fft_out_vld_p2 <= 1'b0;
        end else begin
            natural_bin_p1 <= natural_bin;
            natural_bin_p2 <= natural_bin_p1;
            sample_cnt_p1  <= sample_cnt;
            sample_cnt_p2  <= sample_cnt_p1;
            fft_out_vld_p1 <= fft_out_vld;
            fft_out_vld_p2 <= fft_out_vld_p1;
        end
    end

    wire is_first_sample = (sample_cnt_p2 == 8'd0);
    wire is_last_sample  = (sample_cnt_p2 == 8'd255);

    // =========================================================================
    // Peak detector
    // =========================================================================
    (* mark_debug = "true" *) wire         peak_done;
    (* mark_debug = "true" *) wire [7:0]   peak_bin;
    (* mark_debug = "true" *) wire [16:0]  peak_mag;

    peak_detector u_peak (
        .clk     (clk),
        .rst_n   (rst_n),
        .in_valid(fft_out_vld_p2),
        .in_mag  (mag_out),
        .in_bin  (natural_bin_p2),
        .in_first(is_first_sample),
        .in_last (is_last_sample),
        .done    (peak_done),
        .peak_bin(peak_bin),
        .peak_mag(peak_mag)
    );

    (* mark_debug = "true" *) reg [7:0]  peak_bin_lat;
    (* mark_debug = "true" *) reg [16:0] peak_mag_lat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin peak_bin_lat <= 8'd0; peak_mag_lat <= 17'd0; end
        else if (peak_done) begin
            peak_bin_lat <= peak_bin;
            peak_mag_lat <= peak_mag;
        end
    end

    // =========================================================================
    // Interrupts
    // =========================================================================
    assign irq_frame_done = pp_frame_done;
    assign irq_peak_done  = peak_done;

    // =========================================================================
    // LEDs  (4 on Zybo Z7-10, active HIGH)
    //   LD0 = csr_run   (system active — ON in auto-start mode)
    //   LD1 = Heartbeat at ~7.5 Hz (cycle_cnt[23]): visible when system clocks
    //   LD2 = peak_done pulse stretched to ~67 ms (visible flash each frame result)
    //   LD3 = peak_bin_lat[5] (bit 5 of peak bin; ON if dominant bin is 32..63 or 96..127)
    //         → LED3 ON with DDS at bin 32 confirms peak detected correctly
    // =========================================================================

    // LD1: visible heartbeat using free-running cycle counter bit 23 (~7.5 Hz)
    assign led[1] = cycle_cnt[23];

    // LD2: counts peak_done events; bit[14] toggles at ~15 Hz (488kHz / 2^15).
    // OFF at reset, blinks once peak detection is active — visually distinct from LD1.
    reg [14:0] peak_cnt;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)         peak_cnt <= 15'd0;
        else if (peak_done) peak_cnt <= peak_cnt + 15'd1;

    assign led[0] = csr_run;
    assign led[2] = peak_cnt[14];              // ~15 Hz blink when peaks detected
    assign led[3] = peak_bin_lat[5];           // bit 5: ON for bins 32..63 (and 96..127)

    // =========================================================================
    // UART TX — sends "PEAK:XYZ\r\n" on every peak_done pulse
    //   CLK_FREQ = 125 MHz (Zybo Z7-10 clock)
    //   BAUD_RATE = 115200  →  CLKS_PER_BIT = 125000000/115200 = 1085
    // =========================================================================
    reg  [7:0] uart_data;
    reg        uart_vld;
    wire       uart_rdy;

    uart_tx #(.CLK_FREQ(125_000_000), .BAUD_RATE(115200)) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_data (uart_data),
        .tx_valid(uart_vld),
        .tx_ready(uart_rdy),
        .uart_txd(uart_tx)
    );

    // =========================================================================
    // BCD pre-computation for peak bin (avoids synthesising dividers in
    // the UART sequencer case-statement, which Vivado can be slow on).
    // Registered on peak_done pulse — results ready one cycle later.
    // peak_bin range: 1..127, so hundreds = 0 or 1 only.
    // =========================================================================
    reg [7:0] bcd_hundreds, bcd_tens, bcd_units;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bcd_hundreds <= 8'd0; bcd_tens <= 8'd0; bcd_units <= 8'd0;
        end else if (peak_done) begin
            // Integer divide 8-bit constant: Vivado elaborates cleanly
            bcd_hundreds <= (peak_bin >= 8'd100) ? 8'd1 : 8'd0;
            bcd_tens     <= ((peak_bin >= 8'd100) ? (peak_bin - 8'd100) : peak_bin) / 8'd10;
            bcd_units    <= peak_bin % 8'd10;
        end
    end

    // 10-byte sequencer: 'P' 'E' 'A' 'K' ':' d2 d1 d0 CR LF
    // tx_seq advances one step per uart_rdy cycle.
    // BCD regs are stable by the time we reach steps 6/7/8 (uart_rdy-gated).
    reg [3:0] tx_seq;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_seq    <= 4'd0;
            uart_vld  <= 1'b0;
            uart_data <= 8'h00;
        end else begin
            uart_vld <= 1'b0;
            // Latch peak_done and start the sequence (only when idle)
            if (peak_done && (tx_seq == 4'd0))
                tx_seq <= 4'd1;
            // Advance sequencer whenever UART TX is ready
            if ((tx_seq != 4'd0) && uart_rdy) begin
                uart_vld <= 1'b1;
                case (tx_seq)
                    4'd1:  uart_data <= 8'h50;               // 'P'
                    4'd2:  uart_data <= 8'h45;               // 'E'
                    4'd3:  uart_data <= 8'h41;               // 'A'
                    4'd4:  uart_data <= 8'h4B;               // 'K'
                    4'd5:  uart_data <= 8'h3A;               // ':'
                    4'd6:  uart_data <= 8'h30 + bcd_hundreds; // hundreds digit
                    4'd7:  uart_data <= 8'h30 + bcd_tens;     // tens digit
                    4'd8:  uart_data <= 8'h30 + bcd_units;    // units digit
                    4'd9:  uart_data <= 8'h0D;               // CR
                    4'd10: uart_data <= 8'h0A;               // LF
                    default: uart_data <= 8'h20;
                endcase
                tx_seq <= (tx_seq == 4'd10) ? 4'd0 : (tx_seq + 4'd1);
            end
        end
    end

    // =========================================================================
    // VGA spectrum display
    //   clk_div generates 25 MHz CE from 125 MHz (divide-by-5)
    // =========================================================================
    wire clk_en_25m;
    clk_div u_clkdiv (.clk(clk), .rst_n(rst_n), .clk_en(clk_en_25m));

    wire        vga_wr_en   = fft_out_vld_p2 && (natural_bin_p2 <= 8'd127);
    wire [6:0]  vga_wr_bin  = natural_bin_p2[6:0];
    wire [16:0] vga_wr_data = mag_out;

    vga_spectrum u_vga (
        .clk        (clk),
        .rst_n      (rst_n),
        .clk_en_25m (clk_en_25m),
        .mag_wr_en  (vga_wr_en),
        .mag_wr_bin (vga_wr_bin),
        .mag_wr_data(vga_wr_data),
        .vga_hsync  (vga_hsync),
        .vga_vsync  (vga_vsync),
        .vga_r      (vga_r),
        .vga_g      (vga_g),
        .vga_b      (vga_b)
    );

    // =========================================================================
    // Ping-pong bin read data latch (1-cycle BRAM latency)
    // =========================================================================
    reg [15:0] rd_data_r_lat, rd_data_i_lat;
    reg        rd_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data_r_lat <= 16'd0; rd_data_i_lat <= 16'd0; rd_pending <= 1'b0;
        end else begin
            if (rd_pending) begin
                rd_data_r_lat <= pp_rd_data[15:0];
                rd_data_i_lat <= pp_rd_data[31:16];
                rd_pending    <= 1'b0;
            end
        end
    end

    // =========================================================================
    // AXI4-Lite write channel
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_run     <= 1'b1;   // auto-start: system runs immediately after reset
            csr_src     <= 1'b0;   // DDS source
            csr_dds_bin <= 8'd32;  // default: bin 32 (tone at Fs/8)
            csr_rd_addr <= 8'd0;
            s_awready   <= 1'b0;
            s_wready    <= 1'b0;
            s_bvalid    <= 1'b0;
            s_bresp     <= 2'b00;
        end else begin
            s_awready <= 1'b1;
            s_wready  <= 1'b1;
            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
            if (s_awvalid && s_wvalid) begin
                s_bvalid <= 1'b1;
                s_bresp  <= 2'b00;
                case (s_awaddr[4:2])
                    3'd0: begin
                        csr_run     <= s_wdata[0];
                        csr_src     <= s_wdata[1];
                        csr_dds_bin <= s_wdata[15:8];
                    end
                    3'd4: begin
                        csr_rd_addr <= s_wdata[7:0];
                        rd_pending  <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // AXI4-Lite read channel
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_arready <= 1'b0; s_rvalid <= 1'b0;
            s_rdata   <= 32'h0; s_rresp <= 2'b00;
        end else begin
            s_arready <= 1'b1;
            if (s_rvalid && s_rready) s_rvalid <= 1'b0;
            if (s_arvalid) begin
                s_rvalid <= 1'b1;
                s_rresp  <= 2'b00;
                case (s_araddr[4:2])
                    3'd0: s_rdata <= {16'd0, csr_dds_bin, 6'd0, csr_src, csr_run};
                    3'd1: s_rdata <= {29'd0, peak_done, pp_frame_done, csr_run};
                    3'd2: s_rdata <= {24'd0, peak_bin_lat};
                    3'd3: s_rdata <= {15'd0, peak_mag_lat};
                    3'd4: s_rdata <= {24'd0, csr_rd_addr};
                    3'd5: s_rdata <= {16'd0, rd_data_r_lat};
                    3'd6: s_rdata <= {16'd0, rd_data_i_lat};
                    3'd7: s_rdata <= cycle_cnt;
                    default: s_rdata <= 32'hDEAD_BEEF;
                endcase
            end
        end
    end

endmodule
