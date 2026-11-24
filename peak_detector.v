// =============================================================================
// peak_detector.v  —  Dominant FFT Bin Finder
// =============================================================================
// Accepts a stream of 256 magnitude values and outputs the index and magnitude
// of the maximum value within bins 1..127 (DC bin 0 is ignored).
//
// Works with any sample arrival order (natural or bit-reversed) using
// explicit in_first and in_last frame boundary signals.
//
// Interface:
//   in_valid  : valid data flag
//   in_mag    : 17-bit unsigned magnitude from mag_approx
//   in_bin    : 8-bit natural bin index (0..255)
//   in_first  : 1 on first sample of frame (sample 0)
//   in_last   : 1 on last sample of frame (sample 255)
//   done      : pulses high one cycle after in_last
//   peak_bin  : 8-bit index of maximum bin (1..127)
//   peak_mag  : 17-bit magnitude of that bin
// =============================================================================
module peak_detector (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         in_valid,
    input  wire [16:0]  in_mag,
    input  wire [7:0]   in_bin,
    input  wire         in_first,
    input  wire         in_last,

    output reg          done,
    output reg  [7:0]   peak_bin,
    output reg  [16:0]  peak_mag
);
    reg [16:0] cur_max;
    reg [7:0]  cur_bin;

    wire bin_in_range = (in_bin >= 8'd1) && (in_bin <= 8'd127);
    wire is_new_max   = bin_in_range && (in_mag > cur_max);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_max  <= 17'd0;
            cur_bin  <= 8'd1;
            done     <= 1'b0;
            peak_bin <= 8'd1;
            peak_mag <= 17'd0;
        end else begin
            done <= 1'b0;
            if (in_valid) begin
                if (in_first) begin
                    // Reset accumulator at frame start
                    if (bin_in_range) begin
                        cur_max <= in_mag;
                        cur_bin <= in_bin;
                    end else begin
                        cur_max <= 17'd0;
                        cur_bin <= 8'd1;
                    end
                end else if (is_new_max) begin
                    cur_max <= in_mag;
                    cur_bin <= in_bin;
                end

                if (in_last) begin
                    // Latch final peak result at frame end
                    peak_bin <= is_new_max ? in_bin : cur_bin;
                    peak_mag <= is_new_max ? in_mag : cur_max;
                    done     <= 1'b1;
                end
            end
        end
    end
endmodule
