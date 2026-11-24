// =============================================================================
// uart_rx.v  —  UART Receiver (8N1)
// =============================================================================
// Receives 8-bit data at the configured baud rate.
// Output: rx_data valid for one cycle when rx_done asserts.
// =============================================================================
module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rxd,

    output reg  [7:0] rx_data,
    output reg        rx_done,   // 1-cycle pulse when byte received
    output reg        rx_err     // framing error (stop bit was 0)
);
    localparam integer CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
    localparam integer HALF_BIT      = CLKS_PER_BIT / 2;
    localparam integer CTR_W         = $clog2(CLKS_PER_BIT + 1);

    // Synchronise async input to clock domain (2FF)
    reg rxd_s1, rxd_s;
    always @(posedge clk) begin rxd_s1 <= uart_rxd; rxd_s <= rxd_s1; end

    localparam S_IDLE  = 2'd0,
               S_START = 2'd1,
               S_DATA  = 2'd2,
               S_STOP  = 2'd3;

    reg [1:0]        state;
    reg [CTR_W-1:0]  ctr;
    reg [2:0]        bit_idx;
    reg [7:0]        shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE; ctr <= 0; bit_idx <= 0;
            shift   <= 0; rx_data <= 0;
            rx_done <= 0; rx_err  <= 0;
        end else begin
            rx_done <= 0; rx_err <= 0;
            case (state)
                S_IDLE: begin
                    if (!rxd_s) begin  // start bit detected (falling edge)
                        ctr   <= HALF_BIT;  // sample in middle of start bit
                        state <= S_START;
                    end
                end
                S_START: begin
                    if (ctr == 0) begin
                        if (!rxd_s) begin  // confirm start bit
                            ctr     <= CLKS_PER_BIT - 1;
                            bit_idx <= 0;
                            state   <= S_DATA;
                        end else
                            state <= S_IDLE;  // false start
                    end else
                        ctr <= ctr - 1;
                end
                S_DATA: begin
                    if (ctr == 0) begin
                        shift   <= {rxd_s, shift[7:1]};  // LSB first
                        ctr     <= CLKS_PER_BIT - 1;
                        if (bit_idx == 7) begin
                            bit_idx <= 0;
                            state   <= S_STOP;
                        end else
                            bit_idx <= bit_idx + 1;
                    end else
                        ctr <= ctr - 1;
                end
                S_STOP: begin
                    if (ctr == 0) begin
                        rx_data <= shift;
                        rx_done <= 1;
                        rx_err  <= !rxd_s;  // stop bit must be 1
                        state   <= S_IDLE;
                    end else
                        ctr <= ctr - 1;
                end
            endcase
        end
    end
endmodule
