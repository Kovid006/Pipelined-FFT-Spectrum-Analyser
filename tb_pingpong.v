// =============================================================================
// tb_pingpong.v  —  Testbench for ping-pong buffer
// =============================================================================
`timescale 1ns/1ps

module tb_pingpong;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg         wr_valid;
    reg  signed [15:0] wr_r, wr_i;
    reg  [7:0]  rd_addr;
    wire [31:0] rd_data;
    wire        frame_done;

    pingpong_buf dut (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(wr_valid), .wr_r(wr_r), .wr_i(wr_i),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .frame_done(frame_done)
    );

    integer i, errors = 0;
    // Write 256 samples with known pattern: sample k → real=k, imag=k+256
    initial begin
        rst_n = 0; wr_valid = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Write frame 0 (SDF order = natural here for test)
        for (i = 0; i < 256; i = i+1) begin
            @(negedge clk);
            wr_valid = 1;
            wr_r = i[15:0];       // real = bin index
            wr_i = (i + 256);     // imag = bin+256
        end
        @(negedge clk); wr_valid = 0;
        // frame_done should pulse
        repeat(3) @(posedge clk);

        // Read back bin 0 (natural address 0 → bit-reversed = 0)
        rd_addr = 8'd0;
        repeat(2) @(posedge clk);
        // rd_data[15:0] = real part written at SDF position 0 = bin 0
        if (rd_data[15:0] !== 16'd0) begin
            $display("FAIL pingpong bin0 real: got %0d expected 0", rd_data[15:0]);
            errors = errors + 1;
        end

        // Read bin 1 (natural addr 1 → bit-rev addr = 8'b10000000 = 128)
        // So we should read what was written at SDF position 128 → real=128
        rd_addr = 8'd1;
        repeat(2) @(posedge clk);
        if (rd_data[15:0] !== 16'd128) begin
            $display("FAIL pingpong bin1 real: got %0d expected 128", rd_data[15:0]);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: pingpong_buf tests passed");
        else
            $display("FAIL: pingpong_buf had %0d errors", errors);
        $finish;
    end
endmodule
