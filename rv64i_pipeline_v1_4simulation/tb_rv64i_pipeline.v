//============================================================================
// Testbench for RV64I 5-Stage Pipelined Processor
//============================================================================

`timescale 1ns / 1ps

module tb_rv64i_pipeline;

    reg clk;
    reg rst_n;

    // Instantiate DUT
    rv64i_pipeline_top dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    // Clock generation: 10ns period (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // Load test program into instruction memory
    initial begin
        // Wait for reset
        rst_n = 0;
        #20;
        rst_n = 1;

        // Manually load instructions into instruction memory
        // Test Program:
        //   addi x1, x0, 5        # x1 = 5
        //   addi x2, x0, 10       # x2 = 10
        //   add  x3, x1, x2       # x3 = 15 (data hazard, forwarding from EX/MEM)
        //   sub  x4, x1, x2       # x4 = -5
        //   and  x5, x3, x4       # x5 = x3 & x4
        //   or   x6, x3, x4       # x6 = x3 | x4
        //   sd   x3, 0(x0)        # Mem[0] = 15
        //   ld   x7, 0(x0)        # x7 = Mem[0] = 15 (load-use hazard → stall)
        //   add  x8, x7, x1       # x8 = 15 + 5 = 20 (uses loaded x7)
        //   slli x9, x1, 3        # x9 = 5 << 3 = 40
        //   slti x10, x2, 15      # x10 = (10 < 15) = 1
        //   xori x11, x1, 0xFF   # x11 = 5 ^ 0xFF = 0xFA
        //   beq  x1, x2, skip     # branch NOT taken (5 != 10)
        //   addi x12, x0, 42      # x12 = 42 (should execute)
        // skip:
        //   addi x13, x0, 99      # x13 = 99
        //   jal  x14, next        # x14 = PC+4, jump forward
        //   addi x15, x0, 77      # x15 = 77 (should be skipped by JAL)
        // next:
        //   addi x16, x0, 100     # x16 = 100

        dut.u_instr_mem.mem[0]  = 32'h00500093;  // addi x1, x0, 5
        dut.u_instr_mem.mem[1]  = 32'h00A00113;  // addi x2, x0, 10
        dut.u_instr_mem.mem[2]  = 32'h002081B3;  // add  x3, x1, x2
        dut.u_instr_mem.mem[3]  = 32'h40208233;  // sub  x4, x1, x2
        dut.u_instr_mem.mem[4]  = 32'h0041F2B3;  // and  x5, x3, x4
        dut.u_instr_mem.mem[5]  = 32'h0041E333;  // or   x6, x3, x4
        dut.u_instr_mem.mem[6]  = 32'h00303023;  // sd   x3, 0(x0)
        dut.u_instr_mem.mem[7]  = 32'h00003383;  // ld   x7, 0(x0)
        dut.u_instr_mem.mem[8]  = 32'h00138433;  // add  x8, x7, x1
        dut.u_instr_mem.mem[9]  = 32'h00309493;  // slli x9, x1, 3
        dut.u_instr_mem.mem[10] = 32'h00F12513;  // slti x10, x2, 15
        dut.u_instr_mem.mem[11] = 32'h0FF0C593;  // xori x11, x1, 0xFF
        dut.u_instr_mem.mem[12] = 32'h00208463;  // beq  x1, x2, +8 (skip)
        dut.u_instr_mem.mem[13] = 32'h02A00613;  // addi x12, x0, 42
        dut.u_instr_mem.mem[14] = 32'h06300693;  // addi x13, x0, 99
        dut.u_instr_mem.mem[15] = 32'h0080076F;  // jal  x14, +8 (next)
        dut.u_instr_mem.mem[16] = 32'h04D00793;  // addi x15, x0, 77
        dut.u_instr_mem.mem[17] = 32'h06400813;  // addi x16, x0, 100
    end

    // Monitor and verify
    integer cycle_count;
    initial begin
        cycle_count = 0;

        // Dump waveform
        $dumpfile("rv64i_pipeline.vcd");
        $dumpvars(0, tb_rv64i_pipeline);

        @(posedge rst_n);

        // Run for enough cycles
        repeat (60) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;

            // Print pipeline state every cycle
            $display("=== Cycle %0d | PC=0x%h ===", cycle_count, dut.pc_current);
            $display("  IF: instr=0x%h", dut.instruction_if);
            $display("  ID: instr=0x%h  rs1=%0d rs2=%0d rd=%0d",
                     dut.instr_ifid, dut.rs1_addr, dut.rs2_addr, dut.rd_addr_id);
            $display("  EX: ALU_a=0x%h ALU_b=0x%h result=0x%h  rd=%0d",
                     dut.u_alu.a, dut.u_alu.b, dut.alu_result_ex, dut.rd_addr_idex);
            $display("  MEM: addr=0x%h wr=%b rd=%b  rd_addr=%0d",
                     dut.alu_result_exmem, dut.mem_write_exmem, dut.mem_read_exmem, dut.rd_addr_exmem);
            $display("  WB: data=0x%h  rd=%0d wr=%b",
                     dut.write_back_data, dut.rd_addr_memwb, dut.reg_write_memwb);
            $display("  Stall=%b Flush=%b PCSrc=%b", dut.stall, dut.flush, dut.pc_src);
            $display("");
        end

        // Print final register state
        $display("========================================");
        $display("Final Register State:");
        $display("========================================");
        $display("  x0  = %0d (expect 0)",   dut.u_regfile.regs[0]);
        $display("  x1  = %0d (expect 5)",   dut.u_regfile.regs[1]);
        $display("  x2  = %0d (expect 10)",  dut.u_regfile.regs[2]);
        $display("  x3  = %0d (expect 15)",  dut.u_regfile.regs[3]);
        $display("  x4  = %0d (expect -5)",  $signed(dut.u_regfile.regs[4]));
        $display("  x5  = 0x%h (x3 & x4)",  dut.u_regfile.regs[5]);
        $display("  x6  = 0x%h (x3 | x4)",  dut.u_regfile.regs[6]);
        $display("  x7  = %0d (expect 15)",  dut.u_regfile.regs[7]);
        $display("  x8  = %0d (expect 20)",  dut.u_regfile.regs[8]);
        $display("  x9  = %0d (expect 40)",  dut.u_regfile.regs[9]);
        $display("  x10 = %0d (expect 1)",   dut.u_regfile.regs[10]);
        $display("  x11 = 0x%h (expect 0xFA)", dut.u_regfile.regs[11]);
        $display("  x12 = %0d (expect 42)",  dut.u_regfile.regs[12]);
        $display("  x13 = %0d (expect 99)",  dut.u_regfile.regs[13]);
        $display("  x14 = 0x%h (JAL link)",  dut.u_regfile.regs[14]);
        $display("  x16 = %0d (expect 100)", dut.u_regfile.regs[16]);
        $display("");

        // Print data memory
        $display("Data Memory[0] = %0d (expect 15)", dut.u_data_mem.mem[0]);
        $display("========================================");

        $finish;
    end

endmodule
