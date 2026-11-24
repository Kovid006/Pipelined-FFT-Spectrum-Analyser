// =============================================================================
// tb_bf2i.v  —  Testbench for BF2I butterfly
// =============================================================================
`timescale 1ns/1ps

module tb_bf2i;

    // Test all four input pairs and check outputs match golden model arithmetic
    reg signed [15:0] x0r, x0i, x1r, x1i, x2r, x2i, x3r, x3i;
    wire signed [15:0] s0r, s0i, d0r, d0i, s1r, s1i, d1r, d1i;

    bf2i dut (
        .x0r(x0r), .x0i(x0i), .x1r(x1r), .x1i(x1i),
        .x2r(x2r), .x2i(x2i), .x3r(x3r), .x3i(x3i),
        .s0r(s0r), .s0i(s0i), .d0r(d0r), .d0i(d0i),
        .s1r(s1r), .s1i(s1i), .d1r(d1r), .d1i(d1i)
    );

    integer errors;
    task check;
        input signed [15:0] got, expected;
        input [255:0] name;
        begin
            if (got !== expected) begin
                $display("FAIL %s: got %0d, expected %0d", name, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        // Test 1: simple values
        x0r=16'd100; x0i=16'd0; x1r=16'd200; x1i=16'd0;
        x2r=16'd50;  x2i=16'd0; x3r=16'd100; x3i=16'd0;
        #1;
        // s0 = (100+50)/2 = 75
        check(s0r, 16'sd75,  "s0r_t1");
        // d0 = (100-50)/2 = 25
        check(d0r, 16'sd25,  "d0r_t1");
        // s1 = (200+100)/2 = 150
        check(s1r, 16'sd150, "s1r_t1");
        // d1 = (200-100)/2 = 50
        check(d1r, 16'sd50,  "d1r_t1");

        // Test 2: negative values
        x0r=-16'sd1000; x0i=16'sd500; x1r=16'sd2000; x1i=-16'sd1000;
        x2r=16'sd1000;  x2i=-16'sd500; x3r=-16'sd2000; x3i=16'sd1000;
        #1;
        // s0 = (-1000+1000)/2 = 0
        check(s0r, 16'sd0,    "s0r_t2");
        check(s0i, 16'sd0,    "s0i_t2");
        // d0 = (-1000-1000)/2 = -1000
        check(d0r, -16'sd1000,"d0r_t2");
        check(d0i, 16'sd500,  "d0i_t2");
        // s1 = (2000-2000)/2 = 0
        check(s1r, 16'sd0,    "s1r_t2");
        // d1 = (2000-(-2000))/2 = 2000
        check(d1r, 16'sd2000, "d1r_t2");

        // Test 3: max/min saturation check — >>1 means no overflow needed
        x0r=16'sd32767; x0i=16'sd0; x2r=16'sd32767; x2i=16'sd0;
        x1r=16'sd0;     x1i=16'sd0; x3r=16'sd0;     x3i=16'sd0;
        #1;
        // s0 = (32767+32767)/2 = 32767 (truncated: 65534>>1=32767)
        check(s0r, 16'sd32767, "s0r_t3");
        // d0 = 0
        check(d0r, 16'sd0, "d0r_t3");

        if (errors == 0)
            $display("PASS: bf2i all tests passed");
        else
            $display("FAIL: bf2i had %0d errors", errors);
        $finish;
    end
endmodule
