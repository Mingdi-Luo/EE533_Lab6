//============================================================================
// RV64I 5-Stage Pipelined Processor - Top Wrapper
//
// 完整保留 pipeline_datapath_1_.v 的外部接口:
//   - Streaming datapath passthrough (in_data/out_data)
//   - Register ring (generic_regs + SW/HW regs)
//   - imem/dmem interact 调试接口通过 SW regs 控制
//============================================================================

`timescale 1ns / 1ps

`include "../include/registers.v"

module rv64i_pipeline_top #(
    parameter DATA_WIDTH           = 64,
    parameter CTRL_WIDTH           = DATA_WIDTH/8,
    parameter UDP_REG_SRC_WIDTH    = 2,
    parameter INSTR_WIDTH          = 32,
    parameter IMEM_ADDR_WIDTH      = 9,
    parameter DMEM_ADDR_WIDTH      = 8,
    parameter REGFILE_ADDRESS_WIDTH= 5
)(
    input  wire                         clk,
    input  wire                         reset,

    // Streaming datapath in/out
    input  wire [DATA_WIDTH-1:0]        in_data,
    input  wire [CTRL_WIDTH-1:0]        in_ctrl,
    input  wire                         in_wr,
    output wire                         in_rdy,

    output wire [DATA_WIDTH-1:0]        out_data,
    output wire [CTRL_WIDTH-1:0]        out_ctrl,
    output wire                         out_wr,
    input  wire                         out_rdy,

    // Register ring in/out
    input  wire                         reg_req_in,
    input  wire                         reg_ack_in,
    input  wire                         reg_rd_wr_L_in,
    input  wire [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_in,
    input  wire [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in,
    input  wire [UDP_REG_SRC_WIDTH-1:0]    reg_src_in,

    output wire                         reg_req_out,
    output wire                         reg_ack_out,
    output wire                         reg_rd_wr_L_out,
    output wire [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_out,
    output wire [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
    output wire [UDP_REG_SRC_WIDTH-1:0]    reg_src_out
);

    // ----------------------------
    // Datapath passthrough
    // ----------------------------
    assign out_data = in_data;
    assign out_ctrl = in_ctrl;
    assign out_wr   = in_wr;
    assign in_rdy   = out_rdy;

    // ----------------------------
    // SW regs (written by software / host)
    // ----------------------------
    wire [31:0] imem_interact;
    wire [31:0] imem_write;
    wire [31:0] imem_rw_address;
    wire [31:0] imem_wdata;

    wire [31:0] dmem_interact;
    wire [31:0] dmem_write;
    wire [31:0] dmem_rw_address;
    wire [31:0] dmem_wdata_upper;
    wire [31:0] dmem_wdata_lower;

    // ----------------------------
    // HW regs (read by software / host)
    // ----------------------------
    reg  [31:0] imem_rdata;
    reg  [31:0] dmem_rdata_upper;
    reg  [31:0] dmem_rdata_lower;

    // ----------------------------
    // generic_regs
    // ----------------------------
    generic_regs #(
        .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
        .TAG(`PIPE_BLOCK_ADDR),
        .REG_ADDR_WIDTH(`PIPE_REG_ADDR_WIDTH),
        .NUM_COUNTERS      (0),
        .NUM_SOFTWARE_REGS (9),
        .NUM_HARDWARE_REGS (3)
    ) u_regs (
        .reg_req_in      (reg_req_in),
        .reg_ack_in      (reg_ack_in),
        .reg_rd_wr_L_in  (reg_rd_wr_L_in),
        .reg_addr_in     (reg_addr_in),
        .reg_data_in     (reg_data_in),
        .reg_src_in      (reg_src_in),

        .reg_req_out     (reg_req_out),
        .reg_ack_out     (reg_ack_out),
        .reg_rd_wr_L_out (reg_rd_wr_L_out),
        .reg_addr_out    (reg_addr_out),
        .reg_data_out    (reg_data_out),
        .reg_src_out     (reg_src_out),

        .counter_updates  (),
        .counter_decrement(),

        .software_regs ({
            dmem_wdata_lower,
            dmem_wdata_upper,
            dmem_rw_address,
            dmem_write,
            dmem_interact,
            imem_wdata,
            imem_rw_address,
            imem_write,
            imem_interact
        }),

        .hardware_regs ({
            dmem_rdata_lower,
            dmem_rdata_upper,
            imem_rdata
        }),

        .clk   (clk),
        .reset (reset)
    );

    // ----------------------------
    // Freeze core during CPU interact
    // ----------------------------
    wire core_enable = ~(imem_interact[0] | dmem_interact[0]);

    // rst_n for core (active-low, derived from reset which is active-high)
    wire rst_n = ~reset;

    // ----------------------------
    // CORE <-> IMEM
    // ----------------------------
    wire [IMEM_ADDR_WIDTH-1:0] core_imem_addr;
    wire [INSTR_WIDTH-1:0]     core_imem_dout;

    reg  [IMEM_ADDR_WIDTH-1:0] imem_addr_mux;
    reg  [INSTR_WIDTH-1:0]     imem_din_mux;
    reg                        imem_we_mux;
    wire [INSTR_WIDTH-1:0]     imem_dout_wire;

    // Instruction Memory IP Core
    ins_mem u_imem (
        .addr (imem_addr_mux),
        .clk  (clk),
        .din  (imem_din_mux),
        .dout (imem_dout_wire),
        .we   (imem_we_mux)
    );

    always @(*) begin
        imem_addr_mux = core_imem_addr;
        imem_din_mux  = {INSTR_WIDTH{1'b0}};
        imem_we_mux   = 1'b0;

        if (imem_interact[0]) begin
            imem_addr_mux = imem_rw_address[IMEM_ADDR_WIDTH-1:0];
            imem_din_mux  = imem_wdata[INSTR_WIDTH-1:0];
            imem_we_mux   = imem_write[0];
        end
    end

    assign core_imem_dout = imem_dout_wire;

    // ----------------------------
    // CORE <-> DMEM
    // ----------------------------
    wire                       core_dmem_wea;
    wire [DMEM_ADDR_WIDTH-1:0] core_dmem_addra;
    wire [DMEM_ADDR_WIDTH-1:0] core_dmem_addrb;
    wire [DATA_WIDTH-1:0]      core_dmem_dina;
    wire [DATA_WIDTH-1:0]      core_dmem_doutb;

    reg                        dmem_wea_mux;
    reg  [DMEM_ADDR_WIDTH-1:0] dmem_addra_mux;
    reg  [DMEM_ADDR_WIDTH-1:0] dmem_addrb_mux;
    reg  [DATA_WIDTH-1:0]      dmem_dina_mux;
    wire [DATA_WIDTH-1:0]      dmem_doutb_wire;

    // Data Memory IP Core
    data_mem u_dmem (
        .addra (dmem_addra_mux),
        .addrb (dmem_addrb_mux),
        .clka  (clk),
        .clkb  (clk),
        .dina  (dmem_dina_mux),
        .doutb (dmem_doutb_wire),
        .wea   (dmem_wea_mux)
    );

    always @(*) begin
        dmem_wea_mux   = core_dmem_wea;
        dmem_addra_mux = core_dmem_addra;
        dmem_addrb_mux = core_dmem_addrb;
        dmem_dina_mux  = core_dmem_dina;

        if (dmem_interact[0]) begin
            dmem_addra_mux = dmem_rw_address[DMEM_ADDR_WIDTH-1:0];
            dmem_addrb_mux = dmem_rw_address[DMEM_ADDR_WIDTH-1:0];
            dmem_dina_mux  = {dmem_wdata_upper, dmem_wdata_lower};
            dmem_wea_mux   = dmem_write[0];
        end
    end

    assign core_dmem_doutb = dmem_doutb_wire;

    // ----------------------------
    // Readback regs
    // ----------------------------
    always @(posedge clk) begin
        if (reset) begin
            imem_rdata       <= 32'hBADABDAB;
            dmem_rdata_upper <= 32'hBADABDAB;
            dmem_rdata_lower <= 32'hBADABDAB;
        end else begin
            if (imem_interact[0] && !imem_we_mux) begin
                imem_rdata <= imem_dout_wire;
            end
            if (dmem_interact[0]) begin
                dmem_rdata_upper <= dmem_doutb_wire[63:32];
                dmem_rdata_lower <= dmem_doutb_wire[31:0];
            end
        end
    end

    // ----------------------------
    // CPU Core
    // ----------------------------
    rv64i_pipeline_core #(
        .DATA_WIDTH           (DATA_WIDTH),
        .INSTR_WIDTH          (INSTR_WIDTH),
        .IMEM_ADDR_WIDTH      (IMEM_ADDR_WIDTH),
        .DMEM_ADDR_WIDTH      (DMEM_ADDR_WIDTH),
        .REGFILE_ADDRESS_WIDTH(REGFILE_ADDRESS_WIDTH)
    ) u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (core_enable),

        .imem_addr  (core_imem_addr),
        .imem_dout  (core_imem_dout),

        .dmem_wea   (core_dmem_wea),
        .dmem_addra (core_dmem_addra),
        .dmem_addrb (core_dmem_addrb),
        .dmem_dina  (core_dmem_dina),
        .dmem_doutb (core_dmem_doutb)
    );

endmodule