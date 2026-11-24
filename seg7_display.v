// =============================================================================
// seg7_display.v  —  8-digit Multiplexed 7-Segment Display Driver
//                    Nexys A7 100T  (Vivado-compatible Verilog-2001)
// =============================================================================
// Displays a 32-bit value on the right-hand 8 digits (hex or decimal).
// Uses a ~1 kHz digit multiplex rate (100 MHz / 2^17 ≈ 763 Hz).
//
// Ports:
//   clk        — 100 MHz system clock
//   rst_n      — active-low reset
//   value      — 32-bit display value (hex nibbles, digit 0 = rightmost)
//   dp_in      — 8-bit decimal-point mask (bit i = DP of digit i, active-high)
//   seg        — 7 segments {g,f,e,d,c,b,a} active-LOW
//   dp         — decimal point, active-LOW
//   an         — 8 digit-enable anodes, active-LOW
// =============================================================================
module seg7_display (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] value,
    input  wire [7:0]  dp_in,
    output reg  [6:0]  seg,
    output reg         dp,
    output reg  [7:0]  an
);

    // -------------------------------------------------------------------------
    // Multiplex counter  — 17-bit gives ~763 Hz digit rate @ 100 MHz
    // -------------------------------------------------------------------------
    reg [16:0] mux_cnt;
    wire [2:0] digit_sel = mux_cnt[16:14]; // top 3 bits → 0..7

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mux_cnt <= 17'h0;
        else        mux_cnt <= mux_cnt + 17'h1;
    end

    // -------------------------------------------------------------------------
    // Digit MUX — select nibble
    // -------------------------------------------------------------------------
    reg [3:0] nibble;
    always @(*) begin
        case (digit_sel)
            3'd0: nibble = value[ 3: 0];
            3'd1: nibble = value[ 7: 4];
            3'd2: nibble = value[11: 8];
            3'd3: nibble = value[15:12];
            3'd4: nibble = value[19:16];
            3'd5: nibble = value[23:20];
            3'd6: nibble = value[27:24];
            3'd7: nibble = value[31:28];
            default: nibble = 4'h0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Anode enable — one-hot, active-low
    // -------------------------------------------------------------------------
    always @(*) begin
        an = 8'hFF;                   // all off
        an[digit_sel] = 1'b0;         // enable selected digit
    end

    // -------------------------------------------------------------------------
    // Decimal point (registered to avoid glitches)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dp <= 1'b1;
        else        dp <= ~dp_in[digit_sel];
    end

    // -------------------------------------------------------------------------
    // 7-segment decoder  (registered)
    // Segment mapping: seg[6:0] = {g, f, e, d, c, b, a}  active-LOW
    //
    //      aaa
    //     f   b
    //     f   b
    //      ggg
    //     e   c
    //     e   c
    //      ddd
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg <= 7'h7F;  // all off
        end else begin
            case (nibble)
                //             gfedcba (active-low: 0=on, 1=off)
                4'h0: seg <= 7'b100_0000;
                4'h1: seg <= 7'b111_1001;
                4'h2: seg <= 7'b010_0100;
                4'h3: seg <= 7'b011_0000;
                4'h4: seg <= 7'b001_1001;
                4'h5: seg <= 7'b001_0010;
                4'h6: seg <= 7'b000_0010;
                4'h7: seg <= 7'b111_1000;
                4'h8: seg <= 7'b000_0000;
                4'h9: seg <= 7'b001_0000;
                4'hA: seg <= 7'b000_1000;
                4'hB: seg <= 7'b000_0011;
                4'hC: seg <= 7'b100_0110;
                4'hD: seg <= 7'b010_0001;
                4'hE: seg <= 7'b000_0110;
                4'hF: seg <= 7'b000_1110;
                default: seg <= 7'h7F;
            endcase
        end
    end

endmodule
