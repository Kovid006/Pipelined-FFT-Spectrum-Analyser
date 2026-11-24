// =============================================================================
// dds.v  —  Direct Digital Synthesiser (test tone generator)
// =============================================================================
// Produces a 16-bit Q1.15 cosine output at a programmable frequency.
// Uses a 256-entry quarter-wave cosine ROM and a phase accumulator.
//
//   Phase accumulator: 16-bit  (top 8 bits = ROM address with quadrant logic)
//   Frequency word   : FREQ_WORD = round(f / f_clk * 2^16)
//
// For a 100 MHz clock and 1 sample/clock the output rate is 100 MS/s.
// A tone at bin k of a 256-point FFT needs f = k × (Fs/N):
//   FREQ_WORD = round(k × 65536 / 256) = k × 256
//
// Quadrant logic maps the full 256-step (8-bit MSB of phase) to the 64-entry
// quarter-wave ROM (the same values as the twiddle ROM, real part only):
//   Q0 (MSB[7:6]=00): addr = MSB[5:0],       output =  rom[addr]
//   Q1 (MSB[7:6]=01): addr = 63−MSB[5:0],    output =  rom[addr]
//   Q2 (MSB[7:6]=10): addr = MSB[5:0],        output = −rom[addr]
//   Q3 (MSB[7:6]=11): addr = 63−MSB[5:0],     output = −rom[addr]
// =============================================================================
module dds (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         en,            // enable (gated clock-enable)
    input  wire [15:0]  freq_word,     // phase increment per sample

    output reg  signed [15:0] out      // Q1.15 cosine
);
    // ---- Phase accumulator ----
    reg [15:0] phase;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) phase <= 0;
        else if (en)  phase <= phase + freq_word;

    // ---- Quarter-wave ROM (64 entries, cos values Q1.15) ----
    // Loaded from same twiddle ROM data (real part, indices 0..63).
    reg signed [15:0] cos_rom [0:63];
    initial $readmemh("dds_cos_rom.hex", cos_rom);

    // ---- Quadrant decode ----
    wire [1:0]  quadrant = phase[15:14];
    wire [5:0]  ph6      = phase[13:8];
    wire [5:0]  addr6    = (quadrant[0]) ? (6'd63 - ph6) : ph6;

    reg signed [15:0] rom_out;
    always @(posedge clk)
        rom_out <= cos_rom[addr6];

    // ---- Sign inversion for Q2/Q3 (registered with same latency as ROM) ----
    reg [1:0] quad_r;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) quad_r <= 0;
        else quad_r <= quadrant;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) out <= 0;
        else out <= (quad_r[1]) ? -rom_out : rom_out;
    end
endmodule
