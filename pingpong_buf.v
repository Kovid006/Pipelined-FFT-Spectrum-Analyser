// =============================================================================
// pingpong_buf.v  —  Ping-Pong Output Buffer with Bit-Reversed Read-Out
// =============================================================================
// Collects 256 FFT output samples (bit-reversed SDF order) into one bank
// while the CPU reads the previously completed bank in natural order.
//
// Write side: accepts the SDF stream (bit-reversed order, 256 samples).
// Read side : AXI4-Lite-like word read with 8-bit address (natural bin index).
//             Internally the natural address is converted to bit-reversed.
//
// Two 256×32 banks (ping / pong). After each full 256-sample write the
// active bank flips.  The bank being read is always the OPPOSITE of the
// bank being written.
//
// Memory layout per entry: { imag[15:0], real[15:0] }  (32-bit word).
//
// done pulse: single-cycle high one clock after the last sample of each
//             256-sample frame is written.  RV32 polls or uses this as IRQ.
// =============================================================================
module pingpong_buf (
    input  wire         clk,
    input  wire         rst_n,

    // --- Write port (from FFT SDF output stream) ---
    input  wire         wr_valid,
    input  wire signed [15:0] wr_r,
    input  wire signed [15:0] wr_i,

    // --- Read port (CPU natural-order access) ---
    input  wire [7:0]   rd_addr,     // natural bin index 0..255
    output wire [31:0]  rd_data,     // { imag[15:0], real[15:0] }

    // --- Status ---
    output reg          frame_done   // 1-cycle pulse after each 256-sample frame
);

    // -------------------------------------------------------------------------
    // Bit-reversal function (8-bit)
    // -------------------------------------------------------------------------
    function [7:0] bitrev8;
        input [7:0] x;
        integer i;
        reg [7:0] r;
        begin
            r = 0;
            for (i = 0; i < 8; i = i+1)
                r[7-i] = x[i];
            bitrev8 = r;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Write counter (tracks position within 256-sample write burst)
    // -------------------------------------------------------------------------
    reg [7:0]  wr_cnt;      // 0..255 write position (also = SDF stream index)
    reg        wr_bank;     // which bank is being written

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_cnt  <= 0;
            wr_bank <= 0;
            frame_done <= 0;
        end else begin
            frame_done <= 0;
            if (wr_valid) begin
                if (wr_cnt == 8'd255) begin
                    wr_cnt    <= 0;
                    wr_bank   <= ~wr_bank;
                    frame_done<= 1;
                end else
                    wr_cnt <= wr_cnt + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Dual-port memories (bank 0 and bank 1)
    // Write address in SDF order = wr_cnt (the SDF stream is already in
    // bit-reversed order, so wr_cnt IS the bit-reversed index).
    // Read address  = bitrev8(rd_addr) to convert natural → bit-reversed.
    // -------------------------------------------------------------------------
    reg [31:0] mem0 [0:255];
    reg [31:0] mem1 [0:255];

    wire [31:0] wr_word = {wr_i[15:0], wr_r[15:0]};

    // Write
    always @(posedge clk) begin
        if (wr_valid) begin
            if (!wr_bank) mem0[wr_cnt] <= wr_word;
            else          mem1[wr_cnt] <= wr_word;
        end
    end

    // Read from the bank NOT being written (registered for BRAM inference)
    wire [7:0] rd_br = bitrev8(rd_addr);
    wire rd_bank = ~wr_bank;

    reg [31:0] rd_data_r;
    always @(posedge clk)
        rd_data_r <= rd_bank ? mem1[rd_br] : mem0[rd_br];

    assign rd_data = rd_data_r;

endmodule
