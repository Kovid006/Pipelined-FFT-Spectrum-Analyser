// =============================================================================
// tb_fft256_debug.v  —  Debug version: traces exact out_valid timing for NOISE
// =============================================================================
`timescale 1ns/1ps

module tb_fft256_debug;

    reg clk = 0, rst_n = 0;
    always #4 clk = ~clk;   // 125 MHz

    reg         in_valid;
    reg  signed [15:0] in_r, in_i;
    wire        out_valid;
    wire signed [15:0] out_r, out_i;

    fft256_top dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_r(in_r), .in_i(in_i),
        .out_valid(out_valid), .out_r(out_r), .out_i(out_i)
    );

    reg [31:0] input_mem    [0:255];
    reg [31:0] expected_mem [0:255];

    integer i, out_cnt, cycle_cnt;
    integer errors;

    task do_reset;
        begin
            @(negedge clk); rst_n = 0; in_valid = 0; in_r = 0; in_i = 0;
            repeat(10) @(posedge clk);
            @(negedge clk); rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask

    // Run one full test, tracking cycle count from start of feed
    task run_test_timed;
        input [8*256-1:0] in_file;
        input [8*256-1:0] exp_file;
        input [8*32 -1:0] tag;
        integer collecting;
        reg signed [15:0] exp_r, exp_i;
        integer errors_case;
        begin
            $readmemh(in_file,  input_mem);
            $readmemh(exp_file, expected_mem);
            out_cnt = 0; cycle_cnt = 0; collecting = 1; errors_case = 0;

            // Drive 256 samples
            @(posedge clk);
            for (i = 0; i < 256; i = i+1) begin
                @(negedge clk);
                in_valid = 1;
                in_r = $signed(input_mem[i][15:0]);
                in_i = $signed(input_mem[i][31:16]);
            end

            // Keep feeding zeros and count cycles + collect outputs
            fork
                begin : feeder2
                    repeat(4096) begin
                        @(negedge clk);
                        in_valid = 1; in_r = 0; in_i = 0;
                        if (!collecting) disable feeder2;
                    end
                    @(negedge clk); in_valid = 0;
                end

                begin : counter
                    // Count posedge cycles from start of drain phase
                    forever begin
                        @(posedge clk);
                        if (collecting) cycle_cnt = cycle_cnt + 1;
                        else disable counter;
                    end
                end

                begin : collector2
                    while (out_cnt < 256) begin
                        @(posedge clk);
                        if (out_valid) begin
                            exp_r = $signed(expected_mem[out_cnt][15:0]);
                            exp_i = $signed(expected_mem[out_cnt][31:16]);
                            if (out_cnt < 32)
                                $display("%0s out[%03d] @ cycle %0d: got(%6d,%6d) exp(%6d,%6d) %0s",
                                    tag, out_cnt, cycle_cnt,
                                    out_r, out_i, exp_r, exp_i,
                                    (out_r===exp_r && out_i===exp_i) ? "OK" : "FAIL");
                            if (out_r !== exp_r || out_i !== exp_i)
                                errors_case = errors_case + 1;
                            out_cnt = out_cnt + 1;
                        end
                    end
                    collecting = 0;
                    disable feeder2; disable counter;
                end

                begin : guard2
                    repeat(5000) @(posedge clk);
                    if (out_cnt < 256) begin
                        $display("TIMEOUT %0s: got %0d/256", tag, out_cnt);
                        collecting = 0; disable collector2; disable feeder2; disable counter;
                    end
                end
            join

            @(negedge clk); in_valid = 0;
            repeat(4) @(posedge clk);

            if (errors_case == 0)
                $display("PASS %0s", tag);
            else
                $display("FAIL %0s: %0d mismatches", tag, errors_case);

            errors = errors + errors_case;
            do_reset;
        end
    endtask

    initial begin
        errors = 0;
        in_valid = 0; in_r = 0; in_i = 0;
        do_reset;

        // Run all 3 tests with timing info
        run_test_timed("single_tone_input.hex", "single_tone_expected_sdf.hex", "SINGLE");
        run_test_timed("two_tone_input.hex",    "two_tone_expected_sdf.hex",    "TWO_T ");
        run_test_timed("noise_input.hex",       "noise_expected_sdf.hex",       "NOISE ");

        $display("=== TOTAL: %0d errors ===", errors);
        $finish;
    end

    initial begin
        $dumpfile("tb_fft256_debug.vcd");
        $dumpvars(0, tb_fft256_debug);
    end

endmodule
