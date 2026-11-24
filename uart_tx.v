`timescale 1ns / 1ps

// =============================================================================
// Module: uart_tx
// Description: UART Transmitter (8N1: 8 data bits, no parity, 1 stop bit)
//              Features an 8-entry circular FIFO buffer and AXI-Stream-like
//              handshake interface (tx_valid, tx_ready).
// =============================================================================

module uart_tx #(
    parameter CLK_FREQ     = 100000000,
    parameter BAUD_RATE    = 115200,
    parameter CLKS_PER_BIT = CLK_FREQ / BAUD_RATE
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready,
    output reg        uart_txd
);

    // -------------------------------------------------------------------------
    // Constants / State Encoding
    // -------------------------------------------------------------------------
    localparam STATE_IDLE  = 2'd0;
    localparam STATE_START = 2'd1;
    localparam STATE_DATA  = 2'd2;
    localparam STATE_STOP  = 2'd3;

    // -------------------------------------------------------------------------
    // 16-Entry Circular FIFO (accommodates 10-byte "PEAK:xxx\r\n" burst)
    // -------------------------------------------------------------------------
    reg [7:0] fifo_mem [0:15];
    reg [3:0] wr_ptr;
    reg [3:0] rd_ptr;
    reg [4:0] fifo_count;

    wire fifo_empty = (fifo_count == 5'd0);
    wire fifo_full  = (fifo_count == 5'd16);

    assign tx_ready = !fifo_full;
    wire fifo_wr_en = tx_valid && tx_ready;
    reg  fifo_rd_en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= 4'd0;
            rd_ptr     <= 4'd0;
            fifo_count <= 5'd0;
        end else begin
            case ({fifo_wr_en, fifo_rd_en})
                2'b10: begin // Write only
                    fifo_mem[wr_ptr] <= tx_data;
                    wr_ptr           <= wr_ptr + 1'b1;
                    fifo_count       <= fifo_count + 1'b1;
                end
                2'b01: begin // Read only
                    rd_ptr           <= rd_ptr + 1'b1;
                    fifo_count       <= fifo_count - 1'b1;
                end
                2'b11: begin // Simultaneous write and read
                    fifo_mem[wr_ptr] <= tx_data;
                    wr_ptr           <= wr_ptr + 1'b1;
                    rd_ptr           <= rd_ptr + 1'b1;
                    fifo_count       <= fifo_count; // Unchanged
                end
                default: ; // No operation
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // UART Transmitter FSM & Baud Rate Generator
    // -------------------------------------------------------------------------
    reg [1:0]  state;
    reg [15:0] baud_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= STATE_IDLE;
            uart_txd    <= 1'b1; // Idle line is HIGH
            baud_cnt    <= 16'd0;
            bit_idx     <= 3'd0;
            tx_shift    <= 8'd0;
            fifo_rd_en  <= 1'b0;
        end else begin
            fifo_rd_en <= 1'b0; // Default deassert

            case (state)
                STATE_IDLE: begin
                    uart_txd <= 1'b1;
                    baud_cnt <= 16'd0;
                    bit_idx  <= 3'd0;
                    if (!fifo_empty) begin
                        tx_shift   <= fifo_mem[rd_ptr];
                        fifo_rd_en <= 1'b1;
                        state      <= STATE_START;
                    end
                end

                STATE_START: begin
                    uart_txd <= 1'b0; // Start bit is LOW
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 16'd0;
                        state    <= STATE_DATA;
                        bit_idx  <= 3'd0;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STATE_DATA: begin
                    uart_txd <= tx_shift[bit_idx]; // LSB first
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            state <= STATE_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STATE_STOP: begin
                    uart_txd <= 1'b1; // Stop bit is HIGH
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 16'd0;
                        state    <= STATE_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
