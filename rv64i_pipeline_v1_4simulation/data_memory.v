//============================================================================
// Data Memory
// Width: 64-bit, Depth: 256
// Supports RV64I load/store variants via funct3:
//   LB/SB (000/000), LH/SH (001/001), LW/SW (010/010), LD/SD (011/011)
//   LBU (100), LHU (101), LWU (110)
//============================================================================

`timescale 1ns / 1ps

module data_memory #(
    parameter DEPTH = 256
)(
    input  wire        clk,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [10:0] addr,        // byte address
    input  wire [63:0] write_data,
    input  wire [2:0]  funct3,
    output reg  [63:0] read_data
);

    // 64-bit × 256 memory array
    reg [63:0] mem [0:DEPTH-1];

    wire [7:0]  word_addr = addr[10:3];  // 64-bit word index
    wire [2:0]  byte_off  = addr[2:0];   // byte offset within 64-bit word

    // Combinational read with sign/zero extension
    always @(*) begin
        read_data = 64'd0;
        if (mem_read) begin
            case (funct3)
                3'b000: begin // LB - load byte signed
                    case (byte_off)
                        3'd0: read_data = {{56{mem[word_addr][7]}},  mem[word_addr][7:0]};
                        3'd1: read_data = {{56{mem[word_addr][15]}}, mem[word_addr][15:8]};
                        3'd2: read_data = {{56{mem[word_addr][23]}}, mem[word_addr][23:16]};
                        3'd3: read_data = {{56{mem[word_addr][31]}}, mem[word_addr][31:24]};
                        3'd4: read_data = {{56{mem[word_addr][39]}}, mem[word_addr][39:32]};
                        3'd5: read_data = {{56{mem[word_addr][47]}}, mem[word_addr][47:40]};
                        3'd6: read_data = {{56{mem[word_addr][55]}}, mem[word_addr][55:48]};
                        3'd7: read_data = {{56{mem[word_addr][63]}}, mem[word_addr][63:56]};
                    endcase
                end
                3'b001: begin // LH - load halfword signed
                    case (byte_off[2:1])
                        2'd0: read_data = {{48{mem[word_addr][15]}}, mem[word_addr][15:0]};
                        2'd1: read_data = {{48{mem[word_addr][31]}}, mem[word_addr][31:16]};
                        2'd2: read_data = {{48{mem[word_addr][47]}}, mem[word_addr][47:32]};
                        2'd3: read_data = {{48{mem[word_addr][63]}}, mem[word_addr][63:48]};
                    endcase
                end
                3'b010: begin // LW - load word signed
                    if (byte_off[2])
                        read_data = {{32{mem[word_addr][63]}}, mem[word_addr][63:32]};
                    else
                        read_data = {{32{mem[word_addr][31]}}, mem[word_addr][31:0]};
                end
                3'b011: begin // LD - load doubleword
                    read_data = mem[word_addr];
                end
                3'b100: begin // LBU - load byte unsigned
                    case (byte_off)
                        3'd0: read_data = {56'd0, mem[word_addr][7:0]};
                        3'd1: read_data = {56'd0, mem[word_addr][15:8]};
                        3'd2: read_data = {56'd0, mem[word_addr][23:16]};
                        3'd3: read_data = {56'd0, mem[word_addr][31:24]};
                        3'd4: read_data = {56'd0, mem[word_addr][39:32]};
                        3'd5: read_data = {56'd0, mem[word_addr][47:40]};
                        3'd6: read_data = {56'd0, mem[word_addr][55:48]};
                        3'd7: read_data = {56'd0, mem[word_addr][63:56]};
                    endcase
                end
                3'b101: begin // LHU - load halfword unsigned
                    case (byte_off[2:1])
                        2'd0: read_data = {48'd0, mem[word_addr][15:0]};
                        2'd1: read_data = {48'd0, mem[word_addr][31:16]};
                        2'd2: read_data = {48'd0, mem[word_addr][47:32]};
                        2'd3: read_data = {48'd0, mem[word_addr][63:48]};
                    endcase
                end
                3'b110: begin // LWU - load word unsigned
                    if (byte_off[2])
                        read_data = {32'd0, mem[word_addr][63:32]};
                    else
                        read_data = {32'd0, mem[word_addr][31:0]};
                end
                default: read_data = 64'd0;
            endcase
        end
    end

    // Synchronous write
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000: begin // SB - store byte
                    case (byte_off)
                        3'd0: mem[word_addr][7:0]   <= write_data[7:0];
                        3'd1: mem[word_addr][15:8]  <= write_data[7:0];
                        3'd2: mem[word_addr][23:16] <= write_data[7:0];
                        3'd3: mem[word_addr][31:24] <= write_data[7:0];
                        3'd4: mem[word_addr][39:32] <= write_data[7:0];
                        3'd5: mem[word_addr][47:40] <= write_data[7:0];
                        3'd6: mem[word_addr][55:48] <= write_data[7:0];
                        3'd7: mem[word_addr][63:56] <= write_data[7:0];
                    endcase
                end
                3'b001: begin // SH - store halfword
                    case (byte_off[2:1])
                        2'd0: mem[word_addr][15:0]  <= write_data[15:0];
                        2'd1: mem[word_addr][31:16] <= write_data[15:0];
                        2'd2: mem[word_addr][47:32] <= write_data[15:0];
                        2'd3: mem[word_addr][63:48] <= write_data[15:0];
                    endcase
                end
                3'b010: begin // SW - store word
                    if (byte_off[2])
                        mem[word_addr][63:32] <= write_data[31:0];
                    else
                        mem[word_addr][31:0]  <= write_data[31:0];
                end
                3'b011: begin // SD - store doubleword
                    mem[word_addr] <= write_data;
                end
            endcase
        end
    end

    // Initialize memory to zero
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 64'd0;
    end

endmodule
