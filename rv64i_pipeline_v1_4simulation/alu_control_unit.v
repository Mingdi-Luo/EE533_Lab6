//============================================================================
// ALU Control Unit
// Maps alu_op (from control unit) + funct3 + funct7 to 4-bit ALU control
//
// ALU Control encoding:
//   4'b0000 : ADD
//   4'b0001 : SUB
//   4'b0010 : SLL  (shift left logical)
//   4'b0011 : SLT  (set less than, signed)
//   4'b0100 : SLTU (set less than, unsigned)
//   4'b0101 : XOR
//   4'b0110 : SRL  (shift right logical)
//   4'b0111 : SRA  (shift right arithmetic)
//   4'b1000 : OR
//   4'b1001 : AND
//   4'b1010 : BEQ  (branch equal)
//   4'b1011 : BNE  (branch not equal)
//   4'b1100 : BLT  (branch less than signed)
//   4'b1101 : BGE  (branch >= signed)
//   4'b1110 : BLTU (branch less than unsigned)
//   4'b1111 : BGEU (branch >= unsigned)
//============================================================================

`timescale 1ns / 1ps

module alu_control_unit (
    input  wire [1:0]  alu_op,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    output reg  [3:0]  alu_ctrl
);

    always @(*) begin
        case (alu_op)
            2'b00: // Load / Store / AUIPC → ADD
                alu_ctrl = 4'b0000;

            2'b01: begin // Branch
                case (funct3)
                    3'b000: alu_ctrl = 4'b1010;  // BEQ
                    3'b001: alu_ctrl = 4'b1011;  // BNE
                    3'b100: alu_ctrl = 4'b1100;  // BLT
                    3'b101: alu_ctrl = 4'b1101;  // BGE
                    3'b110: alu_ctrl = 4'b1110;  // BLTU
                    3'b111: alu_ctrl = 4'b1111;  // BGEU
                    default: alu_ctrl = 4'b1010;
                endcase
            end

            2'b10: begin // R-type
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? 4'b0001 : 4'b0000; // SUB / ADD
                    3'b001: alu_ctrl = 4'b0010;  // SLL
                    3'b010: alu_ctrl = 4'b0011;  // SLT
                    3'b011: alu_ctrl = 4'b0100;  // SLTU
                    3'b100: alu_ctrl = 4'b0101;  // XOR
                    3'b101: alu_ctrl = (funct7[5]) ? 4'b0111 : 4'b0110; // SRA / SRL
                    3'b110: alu_ctrl = 4'b1000;  // OR
                    3'b111: alu_ctrl = 4'b1001;  // AND
                endcase
            end

            2'b11: begin // I-type ALU
                case (funct3)
                    3'b000: alu_ctrl = 4'b0000;  // ADDI (no SUBI in RV)
                    3'b001: alu_ctrl = 4'b0010;  // SLLI
                    3'b010: alu_ctrl = 4'b0011;  // SLTI
                    3'b011: alu_ctrl = 4'b0100;  // SLTIU
                    3'b100: alu_ctrl = 4'b0101;  // XORI
                    3'b101: alu_ctrl = (funct7[5]) ? 4'b0111 : 4'b0110; // SRAI / SRLI
                    3'b110: alu_ctrl = 4'b1000;  // ORI
                    3'b111: alu_ctrl = 4'b1001;  // ANDI
                endcase
            end
        endcase
    end

endmodule
