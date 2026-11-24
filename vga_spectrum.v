// =============================================================================
// vga_spectrum.v  —  VGA 640×480 @ 60Hz Spectrum Bar Display
// =============================================================================
// Displays 128 FFT magnitude bins (1..127) as vertical bars on VGA.
//
// Layout:
//   640 pixels wide  — 128 bins × 5 pixels/bin  = 640 pixels (exact)
//   480 pixels tall  — bar height proportional to magnitude
//   Bars are cyan on black background; white baseline at the bottom.
//
// Pixel clock: 25 MHz clock-enable (clk_en_25m) derived externally.
// All FFs run on the 100 MHz system clock; pixel logic gated by clk_en_25m.
//
// Bin-from-pixel mapping (5 px/bin, 128 bins):
//   pix_bin = h_cnt / 5  → implemented as multiply-shift (no divider needed):
//   pix_bin = (h_cnt * 205) >> 10  ≈ h_cnt/5  (exact for h_cnt 0..639)
//
// Magnitude scaling: bar_height = min(mag >> 7, 479)
//   mag max ≈ 45055 → 45055>>7 = 351  (< 479 → fine)
//   Full-scale (32768) → 256 pixel bar  (53% of screen height)
//
// Colour scheme:
//   Bar         : cyan   (R=0, G=A, B=A in 4-bit VGA)
//   Background  : black  (R=0, G=0, B=0)
//   Baseline    : white  (R=F, G=F, B=F)
//   DC bin (0)  : grey   (R=5, G=5, B=5)
// =============================================================================
`timescale 1ns/1ps
module vga_spectrum (
    input  wire        clk,         // 100 MHz system clock
    input  wire        rst_n,
    input  wire        clk_en_25m,  // 25 MHz pixel clock enable (every 4th cycle)

    // Magnitude write port  (from FFT output stream, 128 samples/frame)
    input  wire        mag_wr_en,
    input  wire [6:0]  mag_wr_bin,  // 0..127
    input  wire [16:0] mag_wr_data,

    // VGA output
    output reg         vga_hsync,
    output reg         vga_vsync,
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b
);

    // =========================================================================
    // VGA 640×480 @ 60Hz timing (pixel clock = 25.175 MHz ≈ 25 MHz)
    // =========================================================================
    localparam H_ACTIVE = 640;
    localparam H_FP     = 16;
    localparam H_SYNC   = 96;
    localparam H_BP     = 48;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 800

    localparam V_ACTIVE = 480;
    localparam V_FP     = 10;
    localparam V_SYNC   = 2;
    localparam V_BP     = 33;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 525

    reg [9:0] h_cnt;   // 0..799
    reg [9:0] v_cnt;   // 0..524

    // =========================================================================
    // Horizontal / vertical counters (gated by 25MHz clock-enable)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin h_cnt <= 10'd0; v_cnt <= 10'd0; end
        else if (clk_en_25m) begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                v_cnt <= (v_cnt == V_TOTAL - 1) ? 10'd0 : v_cnt + 10'd1;
            end else
                h_cnt <= h_cnt + 10'd1;
        end
    end

    wire h_active = (h_cnt < H_ACTIVE);
    wire v_active = (v_cnt < V_ACTIVE);
    wire active   = h_active && v_active;

    // =========================================================================
    // Sync signals  (active-low for Nexys A7)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin vga_hsync <= 1'b1; vga_vsync <= 1'b1; end
        else if (clk_en_25m) begin
            vga_hsync <= !((h_cnt >= H_ACTIVE + H_FP) &&
                           (h_cnt <  H_ACTIVE + H_FP + H_SYNC));
            vga_vsync <= !((v_cnt >= V_ACTIVE + V_FP) &&
                           (v_cnt <  V_ACTIVE + V_FP + V_SYNC));
        end
    end

    // =========================================================================
    // Magnitude double-buffer  (128 × 17-bit entries each bank)
    // Write side: FFT output stream fills write bank asynchronously.
    // Read  side: VGA pixel logic reads from display bank.
    // Banks swap at the start of each VGA frame (v=0, h=0).
    // =========================================================================
    reg [16:0] buf_a [0:127];
    reg [16:0] buf_b [0:127];
    reg        wr_to_a;   // 1 → current writes go to A, display reads from B

    // Bank swap at VGA frame start
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_to_a <= 1'b1;
        else if (clk_en_25m && (h_cnt == 10'd0) && (v_cnt == 10'd0))
            wr_to_a <= ~wr_to_a;
    end

    // Write incoming magnitudes into the write buffer
    always @(posedge clk) begin
        if (mag_wr_en) begin
            if (wr_to_a) buf_a[mag_wr_bin] <= mag_wr_data;
            else         buf_b[mag_wr_bin] <= mag_wr_data;
        end
    end

    // =========================================================================
    // Bin index from horizontal pixel — no divider:
    //   pix_bin = (h_cnt * 205) >> 10
    //   For h_cnt in [0,639]: exact (error < 0.5 — truncation correct)
    // =========================================================================
    // h_cnt (10-bit) × 205 (8-bit) = 18-bit product; take bits[17:11] = /2048*2 ≈ /5
    // Exact: for h_cnt in [0,639]: (h_cnt*205)>>10 = floor(h_cnt/5)  ✓
    wire [17:0] h_times_205 = {8'd0, h_cnt} * 10'd205;  // 18-bit safe
    wire [6:0]  pix_bin     = h_times_205[16:10];         // >> 10 → bin 0..127

    // Look up magnitude from the READ buffer (opposite of write buffer)
    wire [16:0] cur_mag = wr_to_a ? buf_b[pix_bin] : buf_a[pix_bin];

    // =========================================================================
    // Bar height from magnitude
    //   bar_height = min(cur_mag >> 7, 479)
    //   cur_mag[16:7] = 10 bits; cap at 479
    // =========================================================================
    wire [9:0] bar_height = (cur_mag[16:7] > 10'd479) ? 10'd479 : cur_mag[16:7];

    // Pixel is inside the bar if:
    //   v_cnt >= (V_ACTIVE - 1 - bar_height)  AND  v_cnt < V_ACTIVE - 1
    wire in_bar  = active &&
                   (v_cnt >= (V_ACTIVE - 1 - bar_height)) &&
                   (v_cnt <  V_ACTIVE - 1);

    // Baseline row at v_cnt == V_ACTIVE - 1 (pixel row 479)
    wire baseline = active && (v_cnt == V_ACTIVE - 1);

    // DC bin (bin 0) shown in grey
    wire is_dc = (pix_bin == 7'd0);

    // =========================================================================
    // Pixel colour output  (registered, one pixel-clock pipeline)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0; end
        else if (clk_en_25m) begin
            if (!active)
                begin vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0; end
            else if (baseline)
                begin vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'hF; end
            else if (in_bar && is_dc)
                begin vga_r <= 4'h5; vga_g <= 4'h5; vga_b <= 4'h5; end
            else if (in_bar)
                begin vga_r <= 4'h0; vga_g <= 4'hA; vga_b <= 4'hA; end
            else
                begin vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0; end
        end
    end

endmodule
