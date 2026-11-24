// =============================================================================
// tb_fft256.v  —  Full 256-point FFT Testbench  (Vivado/xsim, Verilog-2001)
// =============================================================================
// Loads golden-model hex vectors, streams them through fft256_top, and
// compares every output sample against the expected SDF-order output.
//
// Three test cases: single_tone, two_tone, noise
//
// KEY DESIGN NOTES:
//   - The SDF pipeline MUST receive continuous in_valid=1 to propagate.
//     Stopping in_valid after 256 samples starves downstream stages.
//     Solution: keep feeding ZEROS after the test block until all 256
//     outputs are collected, then reset the DUT between test cases.
//   - Clock: 125 MHz (8 ns half-period = #4).
//   - Timeout: 4096 extra cycles is enough for 4-stage + 3×cmul latency (~352).
// =============================================================================
`timescale 1ns/1ps

module tb_fft256;

    // -------------------------------------------------------------------------
    // Clock and reset  — 125 MHz = 8 ns period
    // -------------------------------------------------------------------------
    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;   // 125 MHz

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    reg         in_valid;
    reg  signed [15:0] in_r, in_i;
    wire        out_valid;
    wire signed [15:0] out_r, out_i;

    fft256_top dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_r(in_r), .in_i(in_i),
        .out_valid(out_valid), .out_r(out_r), .out_i(out_i)
    );

    // -------------------------------------------------------------------------
    // Vector memories  (32-bit words: {imag[15:0], real[15:0]})
    // -------------------------------------------------------------------------
    reg [31:0] input_mem    [0:255];
    reg [31:0] expected_mem [0:255];

    // -------------------------------------------------------------------------
    // Shared state
    // -------------------------------------------------------------------------
    integer errors_total;
    integer errors_case;
    integer out_cnt;
    integer feed_cnt;         // how many samples fed this run (inc. drain zeros)
    integer collecting;       // flag: still need outputs
    reg signed [15:0] exp_r, exp_i;

    // -------------------------------------------------------------------------
    // Helper: apply one DUT reset (10 cycles asserted, 5 cycles wait after)
    // -------------------------------------------------------------------------
    task do_reset;
        begin
            @(negedge clk); rst_n = 0; in_valid = 0; in_r = 0; in_i = 0;
            repeat(10) @(posedge clk);
            @(negedge clk); rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: run one test case
    //
    // Strategy:
    //   Phase 1 — drive 256 real test samples (in_valid=1).
    //   Phase 2 — keep driving ZEROS (in_valid=1) while we wait for outputs.
    //             The pipeline MUST keep receiving data to propagate; stopping
    //             in_valid freezes every downstream stage's cnt counter.
    //   We collect outputs concurrently.  Once we have all 256, disable feeder.
    // -------------------------------------------------------------------------
    task run_test;
        input [8*256-1:0] in_file;
        input [8*256-1:0] exp_file;
        input [8*32 -1:0] tag;
        integer i;
        begin
            $readmemh(in_file,  input_mem);
            $readmemh(exp_file, expected_mem);
            errors_case = 0;
            out_cnt     = 0;
            feed_cnt    = 0;
            collecting  = 1;

            // ---- Phase 1: drive 256 test samples ----
            @(posedge clk);
            for (i = 0; i < 256; i = i+1) begin
                @(negedge clk);
                in_valid = 1;
                in_r     = $signed(input_mem[i][15:0]);
                in_i     = $signed(input_mem[i][31:16]);
                feed_cnt = feed_cnt + 1;
            end

            // ---- Phase 2: keep feeding ZEROS to drain the pipeline ----
            // Fork: feeder (zeros) vs collector vs timeout
            fork
                // --- Feeder: pump zeros until collector is done or 4096 extra ---
                begin : feeder
                    repeat(4096) begin
                        @(negedge clk);
                        in_valid = 1;
                        in_r     = 16'sd0;
                        in_i     = 16'sd0;
                        feed_cnt = feed_cnt + 1;
                        if (!collecting) disable feeder;
                    end
                    @(negedge clk); in_valid = 0;
                end

                // --- Collector: gather 256 out_valid samples ---
                begin : collector
                    while (out_cnt < 256) begin
                        @(posedge clk);
                        if (out_valid) begin
                            exp_r = $signed(expected_mem[out_cnt][15:0]);
                            exp_i = $signed(expected_mem[out_cnt][31:16]);
                            if (out_r !== exp_r || out_i !== exp_i) begin
                                if (errors_case < 8)   // limit spam
                                    $display("FAIL %0s bin %0d: got (%0d,%0d) exp (%0d,%0d)",
                                        tag, out_cnt, out_r, out_i, exp_r, exp_i);
                                errors_case = errors_case + 1;
                            end
                            out_cnt = out_cnt + 1;
                        end
                    end
                    collecting = 0;
                    disable feeder;
                end

                // --- Timeout guard ---
                begin : guard
                    repeat(5000) @(posedge clk);
                    if (out_cnt < 256) begin
                        $display("TIMEOUT                      %0s: only got %0d/256 outputs",
                            tag, out_cnt);
                        errors_case = errors_case + 1;
                        collecting  = 0;
                        disable collector;
                        disable feeder;
                    end
                end
            join

            // Stop feeding, wait a couple of cycles
            @(negedge clk); in_valid = 0;
            repeat(4) @(posedge clk);

            errors_total = errors_total + errors_case;
            if (errors_case == 0)
                $display("PASS %0s: all 256 samples match golden model", tag);
            else if (out_cnt == 256)
                $display("FAIL %0s: %0d mismatches", tag, errors_case);

            // Reset DUT between test cases so pipeline state is clean
            do_reset;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    initial begin
        errors_total = 0;
        in_valid = 0; in_r = 0; in_i = 0;

        do_reset;

        run_test("single_tone_input.hex",
                 "single_tone_expected_sdf.hex",
                 "SINGLE_TONE");

        run_test("two_tone_input.hex",
                 "two_tone_expected_sdf.hex",
                 "TWO_TONE");

        run_test("noise_input.hex",
                 "noise_expected_sdf.hex",
                 "NOISE");

        $display("=== TOTAL: %0d errors ===", errors_total);
        if (errors_total == 0) $display("ALL TESTS PASSED");
        else                   $display("SOME TESTS FAILED");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_fft256.vcd");
        $dumpvars(0, tb_fft256);
    end

endmodule
