// =============================================================================
// clk_div.v  —  25 MHz clock-enable generator from 125 MHz (Zybo Z7-10)
// =============================================================================
// Produces a single-cycle pulse every 5 clock cycles (25 MHz effective).
// 125 MHz / 5 = 25 MHz — matches VGA 640×480@60Hz pixel clock requirement.
//
// Vivado timing-clean: all flip-flops remain on the 125 MHz clock.
// No derived clock domain — just a clock-enable gating signal.
// =============================================================================
module clk_div (
    input  wire clk,      // 125 MHz system clock
    input  wire rst_n,
    output reg  clk_en    // 1-cycle pulse at 25 MHz rate (every 5 cycles)
);
    reg [2:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt    <= 3'd0;
            clk_en <= 1'b0;
        end else begin
            if (cnt == 3'd4) begin
                cnt    <= 3'd0;
                clk_en <= 1'b1;
            end else begin
                cnt    <= cnt + 3'd1;
                clk_en <= 1'b0;
            end
        end
    end
endmodule
