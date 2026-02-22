`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   23:25:45 02/19/2026
// Design Name:   rv64i_pipeline_top
// Module Name:   C:/Documents and Settings/student/Desktop/lab6/tb_max.v
// Project Name:  lab6
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: rv64i_pipeline_top
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

//============================================================================
// Testbench: Find Max on RV64I 5-Stage Pipeline
// Target: Xilinx ISE (ISim)
//
// Converted from ARM assembly (arm7tdmi, armv4t) via arm2rv64i compiler
//
// C program:
//   int arr[6] = {3, 9, 1, 6, 2, 8};
//   int max = arr[0];       // max starts at 3
//   for (i = 1; i < 6; i++)
//       if (arr[i] > max) max = arr[i];
//   // Expected max: 9
//
// Memory layout:
//   fp = 0x224 (548), so [fp,#-36] = 0x200 = arr[0]
//   arr[0..5] stored at byte addr 0x200..0x214 (32-bit words, sw)
//   max variable at [fp,#-8] = byte addr 0x21C
//   i variable at [fp,#-12] = byte addr 0x218
//============================================================================

module tb_max;

    reg clk;
    reg rst_n;

    rv64i_pipeline_top dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer cycle_count;
    integer i;
    integer pass_count;
    integer fail_count;
    reg     done;
    reg signed [63:0] mem_val;
    reg signed [63:0] exp_val;
    
    reg [63:0] prev_pc;
    reg [63:0] prev_prev_pc;

    initial begin
        rst_n       = 0;
        done        = 0;
        cycle_count = 0;
        pass_count  = 0;
        fail_count  = 0;
        mem_val     = 0;
        exp_val     = 0;
        i           = 0;
        prev_pc     = 0;
        prev_prev_pc = 0;

        #25;
        rst_n = 1;

        // Load program
        //============================================================
        // PART 1: Array init {3, 9, 1, 6, 2, 8} using sw (32-bit)
        // Array at byte addr 0x200, 4-byte stride to match ARM's lw/sw
        //============================================================
        dut.u_instr_mem.mem[ 0] = 32'h20000993;  // addi x19, x0, 512     # base = 0x200
        dut.u_instr_mem.mem[ 1] = 32'h00300593;  // addi x11, x0, 3
        dut.u_instr_mem.mem[ 2] = 32'h00B9A023;  // sw   x11, 0(x19)      # arr[0] = 3
        dut.u_instr_mem.mem[ 3] = 32'h00900593;  // addi x11, x0, 9
        dut.u_instr_mem.mem[ 4] = 32'h00B9A223;  // sw   x11, 4(x19)      # arr[1] = 9
        dut.u_instr_mem.mem[ 5] = 32'h00100593;  // addi x11, x0, 1
        dut.u_instr_mem.mem[ 6] = 32'h00B9A423;  // sw   x11, 8(x19)      # arr[2] = 1
        dut.u_instr_mem.mem[ 7] = 32'h00600593;  // addi x11, x0, 6
        dut.u_instr_mem.mem[ 8] = 32'h00B9A623;  // sw   x11, 12(x19)     # arr[3] = 6
        dut.u_instr_mem.mem[ 9] = 32'h00200593;  // addi x11, x0, 2
        dut.u_instr_mem.mem[10] = 32'h00B9A823;  // sw   x11, 16(x19)     # arr[4] = 2
        dut.u_instr_mem.mem[11] = 32'h00800593;  // addi x11, x0, 8
        dut.u_instr_mem.mem[12] = 32'h00B9AA23;  // sw   x11, 20(x19)     # arr[5] = 8

        //============================================================
        // PART 1.5: Initialize fp and sp
        // fp = 0x224 (548) so [fp,#-36] = 0x200 = arr[0]
        // sp = fp - 4 = 0x220
        //============================================================
        dut.u_instr_mem.mem[13] = 32'h22400413;  // addi x8, x0, 548      # fp = 0x224
        dut.u_instr_mem.mem[14] = 32'hFFC40113;  // addi x2, x8, -4       # sp = 0x220

        //============================================================
        // PART 2: Find max algorithm (faithful ARM translation)
        //============================================================
        dut.u_instr_mem.mem[15] = 32'hFDC42683;  // lw   x13, -36(x8)     # r3 = arr[0]
        dut.u_instr_mem.mem[16] = 32'hFED42C23;  // sw   x13, -8(x8)      # max = arr[0]
        dut.u_instr_mem.mem[17] = 32'h00100693;  // addi x13, x0, 1       # i = 1
        dut.u_instr_mem.mem[18] = 32'hFED42A23;  // sw   x13, -12(x8)     # store i
        dut.u_instr_mem.mem[19] = 32'h0440006F;  // jal  x0, .L2          # goto loop check
        // [20] .L4: loop body — load arr[i] and compare with max
        dut.u_instr_mem.mem[20] = 32'hFF442683;  // lw   x13, -12(x8)     # load i
        dut.u_instr_mem.mem[21] = 32'h00269693;  // slli x13, x13, 2      # i*4
        dut.u_instr_mem.mem[22] = 32'hFFC68693;  // addi x13, x13, -4     # i*4-4
        dut.u_instr_mem.mem[23] = 32'h008686B3;  // add  x13, x13, x8     # fp + i*4-4
        dut.u_instr_mem.mem[24] = 32'hFE06A683;  // lw   x13, -32(x13)    # arr[i]
        dut.u_instr_mem.mem[25] = 32'hFF842603;  // lw   x12, -8(x8)      # load max
        dut.u_instr_mem.mem[26] = 32'h00D65E63;  // bge  x12, x13, .L3    # if max>=arr[i] skip
        // arr[i] > max → update max
        dut.u_instr_mem.mem[27] = 32'hFF442683;  // lw   x13, -12(x8)     # load i
        dut.u_instr_mem.mem[28] = 32'h00269693;  // slli x13, x13, 2
        dut.u_instr_mem.mem[29] = 32'hFFC68693;  // addi x13, x13, -4
        dut.u_instr_mem.mem[30] = 32'h008686B3;  // add  x13, x13, x8
        dut.u_instr_mem.mem[31] = 32'hFE06A683;  // lw   x13, -32(x13)    # arr[i]
        dut.u_instr_mem.mem[32] = 32'hFED42C23;  // sw   x13, -8(x8)      # max = arr[i]
        // [33] .L3: i++
        dut.u_instr_mem.mem[33] = 32'hFF442683;  // lw   x13, -12(x8)     # load i
        dut.u_instr_mem.mem[34] = 32'h00168693;  // addi x13, x13, 1      # i++
        dut.u_instr_mem.mem[35] = 32'hFED42A23;  // sw   x13, -12(x8)     # store i
        // [36] .L2: loop condition check
        dut.u_instr_mem.mem[36] = 32'hFF442683;  // lw   x13, -12(x8)     # load i
        dut.u_instr_mem.mem[37] = 32'h00500F13;  // addi x30, x0, 5       # tmp = 5
        dut.u_instr_mem.mem[38] = 32'hFADF5CE3;  // bge  x30, x13, .L4    # if 5>=i goto .L4
        // return 0
        dut.u_instr_mem.mem[39] = 32'h00000693;  // addi x13, x0, 0       # r3 = 0
        dut.u_instr_mem.mem[40] = 32'h00068513;  // addi x10, x13, 0      # return 0
        // done + halt
        dut.u_instr_mem.mem[41] = 32'h00100F93;  // addi x31, x0, 1       # done flag
        dut.u_instr_mem.mem[42] = 32'h0000006F;  // jal  x0, 0            # halt

        $display("");
        $display("============================================================");
        $display("  DEBUG: Find Max Pipeline Trace");
        $display("============================================================");
        $display("  Array: {3, 9, 1, 6, 2, 8}");
        $display("  Expected max: 9");
        $display("  fp = 0x224 (548), arr[0] at [fp-36] = 0x200");
        $display("============================================================");

        @(posedge clk);
        @(posedge clk);

        // Run with debug monitoring
        done = 0;
        for (cycle_count = 1; cycle_count <= 2000; cycle_count = cycle_count + 1) begin
            @(posedge clk);
            
            prev_prev_pc = prev_pc;
            prev_pc = dut.pc_current;

            // Monitor: BGE at [26] (addr 0x068) — max vs arr[i]
            if (dut.pc_current == 64'h0068) begin
                $display("[Cycle %0d] Compare: max(x12)=%0d  arr[i](x13)=%0d",
                    cycle_count,
                    $signed(dut.u_regfile.regs[12]),
                    $signed(dut.u_regfile.regs[13]));
            end

            // Monitor: max update SW at [32] (addr 0x080)
            if (dut.pc_current == 64'h0080) begin
                $display("[Cycle %0d] Update max: new_max(x13)=%0d",
                    cycle_count,
                    $signed(dut.u_regfile.regs[13]));
            end

            // Monitor: .L2 loop check at [36] (addr 0x090)
            if (dut.pc_current == 64'h0090) begin
                $display("[Cycle %0d] Loop check: i(x13)=%0d",
                    cycle_count,
                    $signed(dut.u_regfile.regs[13]));
            end

            // Check done flag (x31 = 1)
            if (dut.u_regfile.regs[31] === 64'd1) begin
                done = 1;
                disable main_loop;
            end
        end
        begin : main_loop
        end

        if (done)
            $display("\n  Find max completed at cycle %0d", cycle_count);
        else
            $display("\n  WARNING: Timeout at cycle %0d!", cycle_count);

        //============================================================
        // Print array (should be unchanged by find-max)
        //============================================================
        $display("");
        $display("Array (unchanged):");
        $write("  { ");
        for (i = 0; i < 6; i = i + 1) begin
            if (i > 0) $write(", ");
            // Array stored as 32-bit words packed in 64-bit memory
            // arr[0] at byte 0x200 = word64[0] lower, arr[1] = word64[0] upper
            if (i % 2 == 0)
                $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][31:0]));
            else
                $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][63:32]));
        end
        $display(" }");

        //============================================================
        // Verification
        //============================================================
        $display("");
        pass_count = 0;
        fail_count = 0;

        // Check 1: Array should be unchanged (find-max doesn't modify array)
        $display("--- Array integrity check ---");
        for (i = 0; i < 6; i = i + 1) begin
            if (i % 2 == 0)
                mem_val = $signed(dut.u_data_mem.mem[64 + i/2][31:0]);
            else
                mem_val = $signed(dut.u_data_mem.mem[64 + i/2][63:32]);
            case (i)
                0: exp_val = 3;
                1: exp_val = 9;
                2: exp_val = 1;
                3: exp_val = 6;
                4: exp_val = 2;
                5: exp_val = 8;
                default: exp_val = 0;
            endcase
            if (mem_val == exp_val) begin
                $display("  arr[%0d] = %4d  PASS", i, mem_val);
                pass_count = pass_count + 1;
            end else begin
                $display("  arr[%0d] = %4d  (expect %0d)  FAIL", i, mem_val, exp_val);
                fail_count = fail_count + 1;
            end
        end

        // Check 2: Max value should be 9
        // x12 holds the last loaded max (from lw x12, -8(x8) in compare step)
        $display("");
        $display("--- Max value check ---");
        mem_val = dut.u_regfile.regs[12];
        exp_val = 9;
        if ($signed(mem_val) == $signed(exp_val)) begin
            $display("  x12 (max) = %0d  PASS", $signed(mem_val));
            pass_count = pass_count + 1;
        end else begin
            $display("  x12 (max) = %0d  (expect %0d)  FAIL", $signed(mem_val), $signed(exp_val));
            fail_count = fail_count + 1;
        end

        $display("");
        $display("============================================================");
        if (fail_count == 0)
            $display("  ALL %0d TESTS PASSED!", pass_count);
        else
            $display("  %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("  Total cycles: %0d", cycle_count);
        $display("============================================================");

        #100;
        $finish;
    end

endmodule