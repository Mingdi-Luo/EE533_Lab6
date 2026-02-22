//============================================================================
// Immediate Generator
// Extracts and sign-extends immediate values for all RV64I formats:
//   I-type, S-type, B-type, U-type, J-type
//============================================================================

`timescale 1ns / 1ps

module imm_gen (
    input  wire [31:0] instr,
    output reg  [63:0] imm
);

    wire [6:0] opcode = instr[6:0];

    always @(*) begin
        case (opcode)
            // I-type: ADDI, SLTI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, LB/LH/LW/LD, JALR
            7'b0010011, // OP-IMM
            7'b0011011, // OP-IMM-32 (ADDIW, SLLIW, SRLIW, SRAIW)
            7'b0000011, // LOAD
            7'b1100111: // JALR
                imm = {{52{instr[31]}}, instr[31:20]};

            // S-type: SB, SH, SW, SD
            7'b0100011:
                imm = {{52{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type: BEQ, BNE, BLT, BGE, BLTU, BGEU
            7'b1100011:
                imm = {{51{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

            // U-type: LUI, AUIPC
            7'b0110111, // LUI
            7'b0010111: // AUIPC
                imm = {{32{instr[31]}}, instr[31:12], 12'b0};

            // J-type: JAL
            7'b1101111:
                imm = {{43{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

            default:
                imm = 64'd0;
        endcase
    end

endmodule
