//============================================================================
// Forwarding Unit
// Resolves data hazards by forwarding results from EX/MEM and MEM/WB
// stages back to the EX stage inputs
//
// forward_a/b encoding:
//   2'b00 : No forwarding (use register file output)
//   2'b01 : Forward from MEM/WB stage
//   2'b10 : Forward from EX/MEM stage (higher priority)
//============================================================================

`timescale 1ns / 1ps

module forwarding_unit (
    input  wire [4:0] rs1_addr_ex,
    input  wire [4:0] rs2_addr_ex,
    input  wire [4:0] rd_addr_mem,
    input  wire [4:0] rd_addr_wb,
    input  wire       reg_write_mem,
    input  wire       reg_write_wb,
    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);

    always @(*) begin
        // Default: no forwarding
        forward_a = 2'b00;
        forward_b = 2'b00;

        // Forward A (rs1)
        // EX/MEM hazard (higher priority)
        if (reg_write_mem && (rd_addr_mem != 5'd0) && (rd_addr_mem == rs1_addr_ex))
            forward_a = 2'b10;
        // MEM/WB hazard (lower priority)
        else if (reg_write_wb && (rd_addr_wb != 5'd0) && (rd_addr_wb == rs1_addr_ex))
            forward_a = 2'b01;

        // Forward B (rs2)
        // EX/MEM hazard (higher priority)
        if (reg_write_mem && (rd_addr_mem != 5'd0) && (rd_addr_mem == rs2_addr_ex))
            forward_b = 2'b10;
        // MEM/WB hazard (lower priority)
        else if (reg_write_wb && (rd_addr_wb != 5'd0) && (rd_addr_wb == rs2_addr_ex))
            forward_b = 2'b01;
    end

endmodule

//============================================================================
// Hazard Detection Unit
// Detects load-use data hazards that cannot be resolved by forwarding alone.
// Inserts a 1-cycle stall (bubble) when a load instruction in EX stage
// is followed by an instruction in ID that depends on the loaded value.
//============================================================================

module hazard_detection_unit (
    input  wire [4:0] rs1_addr_id,
    input  wire [4:0] rs2_addr_id,
    input  wire [4:0] rd_addr_ex,
    input  wire       mem_read_ex,
    output wire       stall
);

    // Stall when load in EX writes to a register that ID stage reads
    assign stall = mem_read_ex &&
                   (rd_addr_ex != 5'd0) &&
                   ((rd_addr_ex == rs1_addr_id) || (rd_addr_ex == rs2_addr_id));

endmodule
