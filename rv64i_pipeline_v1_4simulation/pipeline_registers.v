//============================================================================
// Pipeline Registers for 5-Stage RISC-V RV64I Processor
//============================================================================

`timescale 1ns / 1ps

//============================================================================
// IF/ID Pipeline Register
//============================================================================
module pipe_reg_if_id (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    // Inputs
    input  wire [63:0] pc_in,
    input  wire [31:0] instr_in,
    input  wire [63:0] pc_plus_4_in,
    // Outputs
    output reg  [63:0] pc_out,
    output reg  [31:0] instr_out,
    output reg  [63:0] pc_plus_4_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            pc_out        <= 64'd0;
            instr_out     <= 32'h0000_0013;  // NOP
            pc_plus_4_out <= 64'd0;
        end else if (!stall) begin
            pc_out        <= pc_in;
            instr_out     <= instr_in;
            pc_plus_4_out <= pc_plus_4_in;
        end
    end

endmodule

//============================================================================
// ID/EX Pipeline Register
//============================================================================
module pipe_reg_id_ex (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    // Data inputs
    input  wire [63:0] pc_in,
    input  wire [63:0] rs1_data_in,
    input  wire [63:0] rs2_data_in,
    input  wire [63:0] imm_in,
    input  wire [4:0]  rs1_addr_in,
    input  wire [4:0]  rs2_addr_in,
    input  wire [4:0]  rd_addr_in,
    input  wire [2:0]  funct3_in,
    input  wire [6:0]  funct7_in,
    input  wire [63:0] pc_plus_4_in,
    // Control inputs
    input  wire        reg_write_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire        alu_src_in,
    input  wire        branch_in,
    input  wire [1:0]  alu_op_in,
    input  wire        jal_in,
    input  wire        jalr_in,
    input  wire        lui_in,
    input  wire        auipc_in,
    // Data outputs
    output reg  [63:0] pc_out,
    output reg  [63:0] rs1_data_out,
    output reg  [63:0] rs2_data_out,
    output reg  [63:0] imm_out,
    output reg  [4:0]  rs1_addr_out,
    output reg  [4:0]  rs2_addr_out,
    output reg  [4:0]  rd_addr_out,
    output reg  [2:0]  funct3_out,
    output reg  [6:0]  funct7_out,
    output reg  [63:0] pc_plus_4_out,
    // Control outputs
    output reg         reg_write_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         mem_to_reg_out,
    output reg         alu_src_out,
    output reg         branch_out,
    output reg  [1:0]  alu_op_out,
    output reg         jal_out,
    output reg         jalr_out,
    output reg         lui_out,
    output reg         auipc_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            pc_out          <= 64'd0;
            rs1_data_out    <= 64'd0;
            rs2_data_out    <= 64'd0;
            imm_out         <= 64'd0;
            rs1_addr_out    <= 5'd0;
            rs2_addr_out    <= 5'd0;
            rd_addr_out     <= 5'd0;
            funct3_out      <= 3'd0;
            funct7_out      <= 7'd0;
            pc_plus_4_out   <= 64'd0;
            // Control → bubble (NOP)
            reg_write_out   <= 1'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            mem_to_reg_out  <= 1'b0;
            alu_src_out     <= 1'b0;
            branch_out      <= 1'b0;
            alu_op_out      <= 2'b00;
            jal_out         <= 1'b0;
            jalr_out        <= 1'b0;
            lui_out         <= 1'b0;
            auipc_out       <= 1'b0;
        end else begin
            pc_out          <= pc_in;
            rs1_data_out    <= rs1_data_in;
            rs2_data_out    <= rs2_data_in;
            imm_out         <= imm_in;
            rs1_addr_out    <= rs1_addr_in;
            rs2_addr_out    <= rs2_addr_in;
            rd_addr_out     <= rd_addr_in;
            funct3_out      <= funct3_in;
            funct7_out      <= funct7_in;
            pc_plus_4_out   <= pc_plus_4_in;
            reg_write_out   <= reg_write_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            mem_to_reg_out  <= mem_to_reg_in;
            alu_src_out     <= alu_src_in;
            branch_out      <= branch_in;
            alu_op_out      <= alu_op_in;
            jal_out         <= jal_in;
            jalr_out        <= jalr_in;
            lui_out         <= lui_in;
            auipc_out       <= auipc_in;
        end
    end

endmodule

//============================================================================
// EX/MEM Pipeline Register
//============================================================================
module pipe_reg_ex_mem (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    // Data inputs
    input  wire [63:0] alu_result_in,
    input  wire [63:0] rs2_data_in,
    input  wire [4:0]  rd_addr_in,
    input  wire [63:0] branch_target_in,
    input  wire        alu_zero_in,
    input  wire [63:0] pc_plus_4_in,
    input  wire [2:0]  funct3_in,
    // Control inputs
    input  wire        reg_write_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire        branch_in,
    input  wire        jal_in,
    input  wire        jalr_in,
    // Data outputs
    output reg  [63:0] alu_result_out,
    output reg  [63:0] rs2_data_out,
    output reg  [4:0]  rd_addr_out,
    output reg  [63:0] branch_target_out,
    output reg         alu_zero_out,
    output reg  [63:0] pc_plus_4_out,
    output reg  [2:0]  funct3_out,
    // Control outputs
    output reg         reg_write_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         mem_to_reg_out,
    output reg         branch_out,
    output reg         jal_out,
    output reg         jalr_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            alu_result_out    <= 64'd0;
            rs2_data_out      <= 64'd0;
            rd_addr_out       <= 5'd0;
            branch_target_out <= 64'd0;
            alu_zero_out      <= 1'b0;
            pc_plus_4_out     <= 64'd0;
            funct3_out        <= 3'd0;
            reg_write_out     <= 1'b0;
            mem_read_out      <= 1'b0;
            mem_write_out     <= 1'b0;
            mem_to_reg_out    <= 1'b0;
            branch_out        <= 1'b0;
            jal_out           <= 1'b0;
            jalr_out          <= 1'b0;
        end else begin
            alu_result_out    <= alu_result_in;
            rs2_data_out      <= rs2_data_in;
            rd_addr_out       <= rd_addr_in;
            branch_target_out <= branch_target_in;
            alu_zero_out      <= alu_zero_in;
            pc_plus_4_out     <= pc_plus_4_in;
            funct3_out        <= funct3_in;
            reg_write_out     <= reg_write_in;
            mem_read_out      <= mem_read_in;
            mem_write_out     <= mem_write_in;
            mem_to_reg_out    <= mem_to_reg_in;
            branch_out        <= branch_in;
            jal_out           <= jal_in;
            jalr_out          <= jalr_in;
        end
    end

endmodule

//============================================================================
// MEM/WB Pipeline Register
//============================================================================
module pipe_reg_mem_wb (
    input  wire        clk,
    input  wire        rst_n,
    // Data inputs
    input  wire [63:0] alu_result_in,
    input  wire [63:0] mem_read_data_in,
    input  wire [4:0]  rd_addr_in,
    input  wire [63:0] pc_plus_4_in,
    // Control inputs
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    input  wire        jal_in,
    input  wire        jalr_in,
    // Data outputs
    output reg  [63:0] alu_result_out,
    output reg  [63:0] mem_read_data_out,
    output reg  [4:0]  rd_addr_out,
    output reg  [63:0] pc_plus_4_out,
    // Control outputs
    output reg         reg_write_out,
    output reg         mem_to_reg_out,
    output reg         jal_out,
    output reg         jalr_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_out    <= 64'd0;
            mem_read_data_out <= 64'd0;
            rd_addr_out       <= 5'd0;
            pc_plus_4_out     <= 64'd0;
            reg_write_out     <= 1'b0;
            mem_to_reg_out    <= 1'b0;
            jal_out           <= 1'b0;
            jalr_out          <= 1'b0;
        end else begin
            alu_result_out    <= alu_result_in;
            mem_read_data_out <= mem_read_data_in;
            rd_addr_out       <= rd_addr_in;
            pc_plus_4_out     <= pc_plus_4_in;
            reg_write_out     <= reg_write_in;
            mem_to_reg_out    <= mem_to_reg_in;
            jal_out           <= jal_in;
            jalr_out          <= jalr_in;
        end
    end

endmodule
