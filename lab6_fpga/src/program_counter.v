//============================================================================
// Program Counter
//============================================================================

`timescale 1ns / 1ps

module program_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire [63:0] pc_next,
    output reg  [63:0] pc_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_out <= 64'h0000_0000_0000_0000;
        else if (!stall)
            pc_out <= pc_next;
    end

endmodule
