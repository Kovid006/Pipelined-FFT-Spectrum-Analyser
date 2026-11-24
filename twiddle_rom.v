// =============================================================================
// twiddle_rom.v  —  256-entry Q1.15 twiddle factor ROM
// =============================================================================
// Stores W_256^k = exp(−j·2π·k/256) for k = 0..255.
//   tw_r[k] = round(cos(−2π·k/256) · 32768)  clamped to [−32768, 32767]
//   tw_i[k] = round(sin(−2π·k/256) · 32768)
//
// 1-cycle registered read — maps to BRAM or distributed ROM.
// =============================================================================
module twiddle_rom (
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  signed [15:0] tw_r,
    output reg  signed [15:0] tw_i
);
    reg signed [15:0] rom_r [0:255];
    reg signed [15:0] rom_i [0:255];

    initial begin
        $readmemh("twiddle_rom_r.hex", rom_r);
        $readmemh("twiddle_rom_i.hex", rom_i);
    end

    always @(posedge clk) begin
        tw_r <= rom_r[addr];
        tw_i <= rom_i[addr];
    end
endmodule
