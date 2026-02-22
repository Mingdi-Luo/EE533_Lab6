//============================================================================
// Instruction Memory (ROM)
// Width: 32-bit, Depth: 512
// Byte-addressable, word-aligned reads
//============================================================================

`timescale 1ns / 1ps

module instruction_memory #(
    parameter DEPTH = 512
)(
    input  wire [10:0] addr,       // byte address (11 bits = 2048 bytes = 512 words)
    output wire [31:0] instr_out
);

    reg [31:0] mem [0:DEPTH-1];

    // Word-aligned access: addr[10:2] selects the word
    assign instr_out = mem[addr[10:2]];

    // Initialize to NOP (addi x0, x0, 0)
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h0000_0013;  // NOP = addi x0, x0, 0

        // Load program via $readmemh if file exists
        // $readmemh("program.hex", mem);
    end

endmodule
