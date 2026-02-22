//============================================================================
// RV64I 5-Stage Pipelined Processor - Core
// 存储器接口暴露给外层 wrapper，由 wrapper 管理 IP core 和调试 mux
//============================================================================

`timescale 1ns / 1ps

module rv64i_pipeline_core #(
    parameter DATA_WIDTH           = 64,
    parameter INSTR_WIDTH          = 32,
    parameter IMEM_ADDR_WIDTH      = 9,
    parameter DMEM_ADDR_WIDTH      = 8,
    parameter REGFILE_ADDRESS_WIDTH= 5
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          enable,    // 0 = freeze pipeline

    // Instruction Memory interface (to wrapper)
    output wire [IMEM_ADDR_WIDTH-1:0]    imem_addr,
    input  wire [INSTR_WIDTH-1:0]        imem_dout,

    // Data Memory interface (to wrapper)
    output wire                          dmem_wea,
    output wire [DMEM_ADDR_WIDTH-1:0]    dmem_addra,
    output wire [DMEM_ADDR_WIDTH-1:0]    dmem_addrb,
    output wire [DATA_WIDTH-1:0]         dmem_dina,
    input  wire [DATA_WIDTH-1:0]         dmem_doutb
);

    //========================================================================
    // Wire Declarations
    //========================================================================

    // --- IF Stage ---
    wire [63:0] pc_current;
    wire [63:0] pc_plus_4;
    wire [63:0] pc_next;
    wire [31:0] instruction_if;

    // --- IF/ID Pipeline Register Outputs ---
    wire [63:0] pc_ifid;
    wire [31:0] instr_ifid;
    wire [63:0] pc_plus_4_ifid;

    // --- ID Stage ---
    wire [4:0]  rs1_addr, rs2_addr, rd_addr_id;
    wire [63:0] rs1_data, rs2_data;
    wire [63:0] imm_out;
    wire [6:0]  opcode;
    wire [2:0]  funct3_id;
    wire [6:0]  funct7_id;

    // Control signals
    wire        reg_write_id, mem_read_id, mem_write_id;
    wire        mem_to_reg_id, alu_src_id, branch_id;
    wire [1:0]  alu_op_id;
    wire        jal_id, jalr_id, lui_id, auipc_id;

    // --- ID/EX Pipeline Register Outputs ---
    wire [63:0] pc_idex;
    wire [63:0] rs1_data_idex, rs2_data_idex;
    wire [63:0] imm_idex;
    wire [4:0]  rs1_addr_idex, rs2_addr_idex, rd_addr_idex;
    wire [2:0]  funct3_idex;
    wire [6:0]  funct7_idex;
    wire        reg_write_idex, mem_read_idex, mem_write_idex;
    wire        mem_to_reg_idex, alu_src_idex, branch_idex;
    wire [1:0]  alu_op_idex;
    wire        jal_idex, jalr_idex, lui_idex, auipc_idex;
    wire [63:0] pc_plus_4_idex;

    // --- EX Stage ---
    wire [63:0] alu_result_ex;
    wire        alu_zero;
    wire [63:0] branch_target;
    wire [63:0] alu_operand_b;
    wire [3:0]  alu_control;
    wire [1:0]  forward_a, forward_b;
    wire [63:0] forward_a_data, forward_b_data;

    // --- EX/MEM Pipeline Register Outputs ---
    wire [63:0] alu_result_exmem;
    wire [63:0] rs2_data_exmem;
    wire [4:0]  rd_addr_exmem;
    wire        reg_write_exmem, mem_read_exmem, mem_write_exmem;
    wire        mem_to_reg_exmem;
    wire        branch_exmem;
    wire        alu_zero_exmem;
    wire [63:0] branch_target_exmem;
    wire        jal_exmem, jalr_exmem;
    wire [63:0] pc_plus_4_exmem;
    wire [2:0]  funct3_exmem;

    // --- MEM Stage ---
    wire [63:0] mem_read_data;
    wire [63:0] dmem_raw_read;

    // --- MEM/WB Pipeline Register Outputs ---
    wire [63:0] alu_result_memwb;
    wire [63:0] mem_read_data_memwb;
    wire [4:0]  rd_addr_memwb;
    wire        reg_write_memwb, mem_to_reg_memwb;
    wire [63:0] pc_plus_4_memwb;
    wire        jal_memwb, jalr_memwb;

    // --- WB Stage ---
    wire [63:0] write_back_data;

    // --- Hazard Detection ---
    wire        stall;
    wire        flush;

    // --- Internal stall (freeze when enable=0) ---
    wire        stall_or_freeze = stall | (~enable);

    //========================================================================
    // IF Stage: Instruction Fetch
    //========================================================================

    wire pc_src_ex;
    assign pc_src_ex = (branch_idex & alu_zero) | jal_idex | jalr_idex;
    assign pc_next   = pc_src_ex ? branch_target : pc_plus_4;

    // Program Counter (stalls when frozen)
    program_counter u_pc (
        .clk      (clk),
        .rst_n    (rst_n),
        .stall    (stall_or_freeze),
        .pc_next  (pc_next),
        .pc_out   (pc_current)
    );

    assign pc_plus_4 = pc_current + 64'd4;

    // Instruction Memory interface
    assign imem_addr      = pc_current[IMEM_ADDR_WIDTH+1:2]; // word address
    assign instruction_if = imem_dout;

    //========================================================================
    // IF/ID Pipeline Register
    //========================================================================

    pipe_reg_if_id u_ifid (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (stall_or_freeze),
        .flush        (flush | pc_src_ex),
        .pc_in        (pc_current),
        .instr_in     (instruction_if),
        .pc_plus_4_in (pc_plus_4),
        .pc_out       (pc_ifid),
        .instr_out    (instr_ifid),
        .pc_plus_4_out(pc_plus_4_ifid)
    );

    //========================================================================
    // ID Stage
    //========================================================================

    assign opcode    = instr_ifid[6:0];
    assign rd_addr_id= instr_ifid[11:7];
    assign funct3_id = instr_ifid[14:12];
    assign rs1_addr  = instr_ifid[19:15];
    assign rs2_addr  = instr_ifid[24:20];
    assign funct7_id = instr_ifid[31:25];

    control_unit u_ctrl (
        .opcode     (opcode),
        .reg_write  (reg_write_id),
        .mem_read   (mem_read_id),
        .mem_write  (mem_write_id),
        .mem_to_reg (mem_to_reg_id),
        .alu_src    (alu_src_id),
        .branch     (branch_id),
        .alu_op     (alu_op_id),
        .jal        (jal_id),
        .jalr       (jalr_id),
        .lui        (lui_id),
        .auipc      (auipc_id)
    );

    register_file #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_REGS  (32)
    ) u_regfile (
        .clk        (clk),
        .rst_n      (rst_n),
        .rs1_addr   (rs1_addr),
        .rs2_addr   (rs2_addr),
        .rd_addr    (rd_addr_memwb),
        .rd_data    (write_back_data),
        .reg_write  (reg_write_memwb),
        .rs1_data   (rs1_data),
        .rs2_data   (rs2_data)
    );

    imm_gen u_immgen (
        .instr  (instr_ifid),
        .imm    (imm_out)
    );

    //========================================================================
    // ID/EX Pipeline Register
    //========================================================================

    pipe_reg_id_ex u_idex (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (stall_or_freeze | pc_src_ex),
        .pc_in          (pc_ifid),
        .rs1_data_in    (rs1_data),
        .rs2_data_in    (rs2_data),
        .imm_in         (imm_out),
        .rs1_addr_in    (rs1_addr),
        .rs2_addr_in    (rs2_addr),
        .rd_addr_in     (rd_addr_id),
        .funct3_in      (funct3_id),
        .funct7_in      (funct7_id),
        .pc_plus_4_in   (pc_plus_4_ifid),
        .reg_write_in   (reg_write_id),
        .mem_read_in    (mem_read_id),
        .mem_write_in   (mem_write_id),
        .mem_to_reg_in  (mem_to_reg_id),
        .alu_src_in     (alu_src_id),
        .branch_in      (branch_id),
        .alu_op_in      (alu_op_id),
        .jal_in         (jal_id),
        .jalr_in        (jalr_id),
        .lui_in         (lui_id),
        .auipc_in       (auipc_id),
        .pc_out         (pc_idex),
        .rs1_data_out   (rs1_data_idex),
        .rs2_data_out   (rs2_data_idex),
        .imm_out        (imm_idex),
        .rs1_addr_out   (rs1_addr_idex),
        .rs2_addr_out   (rs2_addr_idex),
        .rd_addr_out    (rd_addr_idex),
        .funct3_out     (funct3_idex),
        .funct7_out     (funct7_idex),
        .pc_plus_4_out  (pc_plus_4_idex),
        .reg_write_out  (reg_write_idex),
        .mem_read_out   (mem_read_idex),
        .mem_write_out  (mem_write_idex),
        .mem_to_reg_out (mem_to_reg_idex),
        .alu_src_out    (alu_src_idex),
        .branch_out     (branch_idex),
        .alu_op_out     (alu_op_idex),
        .jal_out        (jal_idex),
        .jalr_out       (jalr_idex),
        .lui_out        (lui_idex),
        .auipc_out      (auipc_idex)
    );

    //========================================================================
    // EX Stage
    //========================================================================

    forwarding_unit u_fwd (
        .rs1_addr_ex    (rs1_addr_idex),
        .rs2_addr_ex    (rs2_addr_idex),
        .rd_addr_mem    (rd_addr_exmem),
        .rd_addr_wb     (rd_addr_memwb),
        .reg_write_mem  (reg_write_exmem),
        .reg_write_wb   (reg_write_memwb),
        .forward_a      (forward_a),
        .forward_b      (forward_b)
    );

    assign forward_a_data = (forward_a == 2'b10) ? alu_result_exmem :
                            (forward_a == 2'b01) ? write_back_data  :
                                                   rs1_data_idex;

    assign forward_b_data = (forward_b == 2'b10) ? alu_result_exmem :
                            (forward_b == 2'b01) ? write_back_data  :
                                                   rs2_data_idex;

    assign alu_operand_b = alu_src_idex ? imm_idex : forward_b_data;

    alu_control_unit u_alu_ctrl (
        .alu_op   (alu_op_idex),
        .funct3   (funct3_idex),
        .funct7   (funct7_idex),
        .alu_ctrl (alu_control)
    );

    alu_64bit u_alu (
        .a        (lui_idex ? 64'd0 : (auipc_idex ? pc_idex : forward_a_data)),
        .b        (lui_idex ? imm_idex : alu_operand_b),
        .alu_ctrl (lui_idex ? 4'b0000 : alu_control),
        .result   (alu_result_ex),
        .zero     (alu_zero)
    );

    assign branch_target = jalr_idex ? (forward_a_data + imm_idex) & ~64'd1
                                     : pc_idex + imm_idex;

    //========================================================================
    // EX/MEM Pipeline Register
    //========================================================================

    pipe_reg_ex_mem u_exmem (
        .clk                (clk),
        .rst_n              (rst_n),
        .flush              (1'b0),
        .alu_result_in      (alu_result_ex),
        .rs2_data_in        (forward_b_data),
        .rd_addr_in         (rd_addr_idex),
        .branch_target_in   (branch_target),
        .alu_zero_in        (alu_zero),
        .pc_plus_4_in       (pc_plus_4_idex),
        .funct3_in          (funct3_idex),
        .reg_write_in       (reg_write_idex),
        .mem_read_in        (mem_read_idex),
        .mem_write_in       (mem_write_idex),
        .mem_to_reg_in      (mem_to_reg_idex),
        .branch_in          (branch_idex),
        .jal_in             (jal_idex),
        .jalr_in            (jalr_idex),
        .alu_result_out     (alu_result_exmem),
        .rs2_data_out       (rs2_data_exmem),
        .rd_addr_out        (rd_addr_exmem),
        .branch_target_out  (branch_target_exmem),
        .alu_zero_out       (alu_zero_exmem),
        .pc_plus_4_out      (pc_plus_4_exmem),
        .funct3_out         (funct3_exmem),
        .reg_write_out      (reg_write_exmem),
        .mem_read_out       (mem_read_exmem),
        .mem_write_out      (mem_write_exmem),
        .mem_to_reg_out     (mem_to_reg_exmem),
        .branch_out         (branch_exmem),
        .jal_out            (jal_exmem),
        .jalr_out           (jalr_exmem)
    );

    //========================================================================
    // MEM Stage: Data Memory Interface
    //========================================================================

    wire [7:0] dmem_word_addr = alu_result_exmem[10:3];
    wire [2:0] dmem_byte_off  = alu_result_exmem[2:0];

    // dmem_raw_read comes from wrapper via dmem_doutb
    assign dmem_raw_read = dmem_doutb;

    // Store data merge (read-modify-write for sub-word stores)
    reg [63:0] store_merged_data;
    always @(*) begin
        store_merged_data = rs2_data_exmem;
        case (funct3_exmem)
            3'b000: begin // SB
                store_merged_data = dmem_raw_read;
                case (dmem_byte_off)
                    3'd0: store_merged_data[ 7: 0] = rs2_data_exmem[7:0];
                    3'd1: store_merged_data[15: 8] = rs2_data_exmem[7:0];
                    3'd2: store_merged_data[23:16] = rs2_data_exmem[7:0];
                    3'd3: store_merged_data[31:24] = rs2_data_exmem[7:0];
                    3'd4: store_merged_data[39:32] = rs2_data_exmem[7:0];
                    3'd5: store_merged_data[47:40] = rs2_data_exmem[7:0];
                    3'd6: store_merged_data[55:48] = rs2_data_exmem[7:0];
                    3'd7: store_merged_data[63:56] = rs2_data_exmem[7:0];
                endcase
            end
            3'b001: begin // SH
                store_merged_data = dmem_raw_read;
                case (dmem_byte_off[2:1])
                    2'd0: store_merged_data[15: 0] = rs2_data_exmem[15:0];
                    2'd1: store_merged_data[31:16] = rs2_data_exmem[15:0];
                    2'd2: store_merged_data[47:32] = rs2_data_exmem[15:0];
                    2'd3: store_merged_data[63:48] = rs2_data_exmem[15:0];
                endcase
            end
            3'b010: begin // SW
                store_merged_data = dmem_raw_read;
                if (dmem_byte_off[2])
                    store_merged_data[63:32] = rs2_data_exmem[31:0];
                else
                    store_merged_data[31: 0] = rs2_data_exmem[31:0];
            end
            3'b011: store_merged_data = rs2_data_exmem; // SD
            default: store_merged_data = rs2_data_exmem;
        endcase
    end

    // Data Memory interface signals to wrapper
    assign dmem_wea   = mem_write_exmem;
    assign dmem_addra = dmem_word_addr;
    assign dmem_addrb = dmem_word_addr;
    assign dmem_dina  = store_merged_data;

    // Load data post-processing
    reg [63:0] load_processed_data;
    always @(*) begin
        load_processed_data = 64'd0;
        case (funct3_exmem)
            3'b000: begin // LB
                case (dmem_byte_off)
                    3'd0: load_processed_data = {{56{dmem_raw_read[ 7]}}, dmem_raw_read[ 7: 0]};
                    3'd1: load_processed_data = {{56{dmem_raw_read[15]}}, dmem_raw_read[15: 8]};
                    3'd2: load_processed_data = {{56{dmem_raw_read[23]}}, dmem_raw_read[23:16]};
                    3'd3: load_processed_data = {{56{dmem_raw_read[31]}}, dmem_raw_read[31:24]};
                    3'd4: load_processed_data = {{56{dmem_raw_read[39]}}, dmem_raw_read[39:32]};
                    3'd5: load_processed_data = {{56{dmem_raw_read[47]}}, dmem_raw_read[47:40]};
                    3'd6: load_processed_data = {{56{dmem_raw_read[55]}}, dmem_raw_read[55:48]};
                    3'd7: load_processed_data = {{56{dmem_raw_read[63]}}, dmem_raw_read[63:56]};
                endcase
            end
            3'b001: begin // LH
                case (dmem_byte_off[2:1])
                    2'd0: load_processed_data = {{48{dmem_raw_read[15]}}, dmem_raw_read[15: 0]};
                    2'd1: load_processed_data = {{48{dmem_raw_read[31]}}, dmem_raw_read[31:16]};
                    2'd2: load_processed_data = {{48{dmem_raw_read[47]}}, dmem_raw_read[47:32]};
                    2'd3: load_processed_data = {{48{dmem_raw_read[63]}}, dmem_raw_read[63:48]};
                endcase
            end
            3'b010: begin // LW
                if (dmem_byte_off[2])
                    load_processed_data = {{32{dmem_raw_read[63]}}, dmem_raw_read[63:32]};
                else
                    load_processed_data = {{32{dmem_raw_read[31]}}, dmem_raw_read[31: 0]};
            end
            3'b011: load_processed_data = dmem_raw_read; // LD
            3'b100: begin // LBU
                case (dmem_byte_off)
                    3'd0: load_processed_data = {56'd0, dmem_raw_read[ 7: 0]};
                    3'd1: load_processed_data = {56'd0, dmem_raw_read[15: 8]};
                    3'd2: load_processed_data = {56'd0, dmem_raw_read[23:16]};
                    3'd3: load_processed_data = {56'd0, dmem_raw_read[31:24]};
                    3'd4: load_processed_data = {56'd0, dmem_raw_read[39:32]};
                    3'd5: load_processed_data = {56'd0, dmem_raw_read[47:40]};
                    3'd6: load_processed_data = {56'd0, dmem_raw_read[55:48]};
                    3'd7: load_processed_data = {56'd0, dmem_raw_read[63:56]};
                endcase
            end
            3'b101: begin // LHU
                case (dmem_byte_off[2:1])
                    2'd0: load_processed_data = {48'd0, dmem_raw_read[15: 0]};
                    2'd1: load_processed_data = {48'd0, dmem_raw_read[31:16]};
                    2'd2: load_processed_data = {48'd0, dmem_raw_read[47:32]};
                    2'd3: load_processed_data = {48'd0, dmem_raw_read[63:48]};
                endcase
            end
            3'b110: begin // LWU
                if (dmem_byte_off[2])
                    load_processed_data = {32'd0, dmem_raw_read[63:32]};
                else
                    load_processed_data = {32'd0, dmem_raw_read[31: 0]};
            end
            default: load_processed_data = 64'd0;
        endcase
    end

    assign mem_read_data = load_processed_data;

    //========================================================================
    // MEM/WB Pipeline Register
    //========================================================================

    pipe_reg_mem_wb u_memwb (
        .clk                (clk),
        .rst_n              (rst_n),
        .alu_result_in      (alu_result_exmem),
        .mem_read_data_in   (mem_read_data),
        .rd_addr_in         (rd_addr_exmem),
        .pc_plus_4_in       (pc_plus_4_exmem),
        .reg_write_in       (reg_write_exmem),
        .mem_to_reg_in      (mem_to_reg_exmem),
        .jal_in             (jal_exmem),
        .jalr_in            (jalr_exmem),
        .alu_result_out     (alu_result_memwb),
        .mem_read_data_out  (mem_read_data_memwb),
        .rd_addr_out        (rd_addr_memwb),
        .pc_plus_4_out      (pc_plus_4_memwb),
        .reg_write_out      (reg_write_memwb),
        .mem_to_reg_out     (mem_to_reg_memwb),
        .jal_out            (jal_memwb),
        .jalr_out           (jalr_memwb)
    );

    //========================================================================
    // WB Stage
    //========================================================================

    assign write_back_data = (jal_memwb | jalr_memwb) ? pc_plus_4_memwb :
                             mem_to_reg_memwb          ? mem_read_data_memwb :
                                                         alu_result_memwb;

    //========================================================================
    // Hazard Detection Unit
    //========================================================================

    hazard_detection_unit u_hazard (
        .rs1_addr_id    (rs1_addr),
        .rs2_addr_id    (rs2_addr),
        .rd_addr_ex     (rd_addr_idex),
        .mem_read_ex    (mem_read_idex),
        .stall          (stall)
    );

    assign flush = pc_src_ex;

endmodule