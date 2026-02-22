//============================================================================
// 64-bit ALU
// Supports all RV64I arithmetic/logic/branch operations
// Also supports W-suffix (32-bit) variants via sign extension
//============================================================================

`timescale 1ns / 1ps

module alu_64bit (
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [3:0]  alu_ctrl,
    output reg  [63:0] result,
    output reg         zero       // '1' when branch condition is met
);

    wire signed [63:0] a_signed = a;
    wire signed [63:0] b_signed = b;

    always @(*) begin
        result = 64'd0;
        zero   = 1'b0;

        case (alu_ctrl)
            4'b0000: // ADD
                result = a + b;

            4'b0001: // SUB
                result = a - b;

            4'b0010: // SLL (shift left logical)
                result = a << b[5:0];

            4'b0011: // SLT (set less than, signed)
                result = (a_signed < b_signed) ? 64'd1 : 64'd0;

            4'b0100: // SLTU (set less than, unsigned)
                result = (a < b) ? 64'd1 : 64'd0;

            4'b0101: // XOR
                result = a ^ b;

            4'b0110: // SRL (shift right logical)
                result = a >> b[5:0];

            4'b0111: // SRA (shift right arithmetic)
                result = a_signed >>> b[5:0];

            4'b1000: // OR
                result = a | b;

            4'b1001: // AND
                result = a & b;

            // Branch operations: result is don't care, zero indicates branch taken
            4'b1010: begin // BEQ
                zero = (a == b);
            end

            4'b1011: begin // BNE
                zero = (a != b);
            end

            4'b1100: begin // BLT (signed)
                zero = (a_signed < b_signed);
            end

            4'b1101: begin // BGE (signed)
                zero = (a_signed >= b_signed);
            end

            4'b1110: begin // BLTU (unsigned)
                zero = (a < b);
            end

            4'b1111: begin // BGEU (unsigned)
                zero = (a >= b);
            end

            default: begin
                result = 64'd0;
                zero   = 1'b0;
            end
        endcase
    end

endmodule
