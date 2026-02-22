//============================================================================
// Control Unit for RV64I
// Generates control signals based on opcode
//============================================================================

`timescale 1ns / 1ps

module control_unit (
    input  wire [6:0]  opcode,
    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         mem_to_reg,
    output reg         alu_src,
    output reg         branch,
    output reg  [1:0]  alu_op,
    output reg         jal,
    output reg         jalr,
    output reg         lui,
    output reg         auipc
);

    // RV64I Opcode definitions
    localparam OP_RTYPE    = 7'b0110011;  // R-type (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU)
    localparam OP_RTYPE_W  = 7'b0111011;  // R-type word (ADDW, SUBW, SLLW, SRLW, SRAW)
    localparam OP_ITYPE    = 7'b0010011;  // I-type ALU (ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI)
    localparam OP_ITYPE_W  = 7'b0011011;  // I-type word (ADDIW, SLLIW, SRLIW, SRAIW)
    localparam OP_LOAD     = 7'b0000011;  // Load (LB, LH, LW, LD, LBU, LHU, LWU)
    localparam OP_STORE    = 7'b0100011;  // Store (SB, SH, SW, SD)
    localparam OP_BRANCH   = 7'b1100011;  // Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
    localparam OP_JAL      = 7'b1101111;  // JAL
    localparam OP_JALR     = 7'b1100111;  // JALR
    localparam OP_LUI      = 7'b0110111;  // LUI
    localparam OP_AUIPC    = 7'b0010111;  // AUIPC

    always @(*) begin
        // Default: all signals deasserted
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        alu_src    = 1'b0;
        branch     = 1'b0;
        alu_op     = 2'b00;
        jal        = 1'b0;
        jalr       = 1'b0;
        lui        = 1'b0;
        auipc      = 1'b0;

        case (opcode)
            OP_RTYPE, OP_RTYPE_W: begin
                reg_write = 1'b1;
                alu_op    = 2'b10;  // R-type: ALU control from funct3/funct7
            end

            OP_ITYPE, OP_ITYPE_W: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;   // immediate as second operand
                alu_op    = 2'b11;  // I-type ALU
            end

            OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_op     = 2'b00; // ADD for address calculation
            end

            OP_STORE: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_op    = 2'b00;  // ADD for address calculation
            end

            OP_BRANCH: begin
                branch = 1'b1;
                alu_op = 2'b01;     // Branch comparison
            end

            OP_JAL: begin
                reg_write = 1'b1;
                jal       = 1'b1;
            end

            OP_JALR: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jalr      = 1'b1;
            end

            OP_LUI: begin
                reg_write = 1'b1;
                lui       = 1'b1;
            end

            OP_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                auipc     = 1'b1;
                alu_op    = 2'b00;  // ADD
            end

            default: begin
                // NOP / unknown instruction
            end
        endcase
    end

endmodule
