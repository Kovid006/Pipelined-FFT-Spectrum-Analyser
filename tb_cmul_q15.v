// =============================================================================
// tb_cmul_q15.v  —  Testbench for the complex multiplier
// =============================================================================
`timescale 1ns/1ps

module tb_cmul_q15;

    reg         clk = 0, rst_n = 0;
    always #5 clk = ~clk;   // 100 MHz

    reg         in_valid;
    reg  signed [15:0] br, bi, wr, wi;
    reg         trivial_w;
    reg  [1:0]  tw_sel;
    wire        out_valid;
    wire signed [15:0] out_r, out_i;

    cmul_q15 dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .br(br), .bi(bi), .wr(wr), .wi(wi),
        .trivial_w(trivial_w), .tw_sel(tw_sel),
        .out_valid(out_valid), .out_r(out_r), .out_i(out_i)
    );

    integer errors = 0;

    // Expected result task (waits 3 cycles for pipeline)
    task apply_and_check;
        input signed [15:0] i_br, i_bi, i_wr, i_wi;
        input                i_triv;
        input [1:0]          i_sel;
        input signed [15:0] exp_r, exp_i;
        input [255:0]        tag;
        integer k;
        begin
            @(posedge clk);
            br = i_br; bi = i_bi; wr = i_wr; wi = i_wi;
            trivial_w = i_triv; tw_sel = i_sel;
            in_valid = 1;
            @(posedge clk); in_valid = 0;
            // Wait 3 pipeline stages
            repeat(3) @(posedge clk);
            if (out_valid) begin
                if (out_r !== exp_r || out_i !== exp_i) begin
                    $display("FAIL %s: got (%0d,%0d) expected (%0d,%0d)",
                             tag, out_r, out_i, exp_r, exp_i);
                    errors = errors + 1;
                end
            end else begin
                $display("FAIL %s: out_valid not asserted", tag);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0; in_valid = 0;
        br = 0; bi = 0; wr = 0; wi = 0;
        trivial_w = 0; tw_sel = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: W=1 (wr=32767, wi=0) — B * 1 = B
        // Golden: re=(br*32767 - bi*0)>>15 = br*32767>>15 ≈ br (off by 1 LSB)
        // Exact: (100*32767)>>15 = 3276700>>15 = 99 (truncation)
        apply_and_check(16'sd100, 16'sd0, 16'sd32767, 16'sd0,
                        0, 2'b00,
                        16'sd99, 16'sd0, "W=1 non-triv");

        // Test 2: Trivial bypass W=1
        apply_and_check(16'sd1000, 16'sd500, 16'sd32767, 16'sd0,
                        1, 2'b00,
                        16'sd1000, 16'sd500, "W=1 trivial bypass");

        // Test 3: Trivial -j bypass (sel=01): out = (bi, -br)
        apply_and_check(16'sd1000, 16'sd500, 16'sd0, -16'sd32768,
                        1, 2'b01,
                        16'sd500, -16'sd1000, "W=-j trivial");

        // Test 4: Trivial -1 bypass (sel=10): out = (-br, -bi)
        apply_and_check(16'sd1000, 16'sd500, -16'sd32768, 16'sd0,
                        1, 2'b10,
                        -16'sd1000, -16'sd500, "W=-1 trivial");

        // Test 5: Trivial +j bypass (sel=11): out = (-bi, br)
        apply_and_check(16'sd1000, 16'sd500, 16'sd0, 16'sd32767,
                        1, 2'b11,
                        -16'sd500, 16'sd1000, "W=+j trivial");

        // Test 6: W=W256^1 = cos(-2pi/256)+j*sin(-2pi/256)
        // wr=32758, wi=-804 (from ROM)
        // re = (100*32758 - 0*(-804))>>15 = 3275800>>15 = 99
        // im = (100*(-804) + 0*32758)>>15 = -80400>>15 = -3  (trunc)
        apply_and_check(16'sd100, 16'sd0, 16'sd32758, -16'sd804,
                        0, 2'b00,
                        16'sd99, -16'sd3, "W=W256^1");

        repeat(5) @(posedge clk);

        if (errors == 0)
            $display("PASS: cmul_q15 all tests passed");
        else
            $display("FAIL: cmul_q15 had %0d errors", errors);
        $finish;
    end
endmodule
