//============================================================================
// Register File
// Width: 64-bit, Depth: 32 (x0-x31)
// 2 read ports, 1 write port
// x0 is hardwired to zero
// Write on rising edge, read combinationally (with WB forwarding)
//============================================================================

`timescale 1ns / 1ps

module register_file #(
    parameter DATA_WIDTH = 64,
    parameter NUM_REGS   = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [4:0]              rs1_addr,
    input  wire [4:0]              rs2_addr,
    input  wire [4:0]              rd_addr,
    input  wire [DATA_WIDTH-1:0]   rd_data,
    input  wire                    reg_write,
    output wire [DATA_WIDTH-1:0]   rs1_data,
    output wire [DATA_WIDTH-1:0]   rs2_data
);

    reg [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];

    // Read with internal forwarding: if writing and reading same register
    // in same cycle, forward the write data
    assign rs1_data = (rs1_addr == 5'd0) ? {DATA_WIDTH{1'b0}} :
                      (reg_write && rd_addr == rs1_addr) ? rd_data :
                      regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? {DATA_WIDTH{1'b0}} :
                      (reg_write && rd_addr == rs2_addr) ? rd_data :
                      regs[rs2_addr];

    // Synchronous write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin : reset_regs
            integer i;
            for (i = 0; i < NUM_REGS; i = i + 1)
                regs[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            if (reg_write && rd_addr != 5'd0)
                regs[rd_addr] <= rd_data;
        end
    end

endmodule
