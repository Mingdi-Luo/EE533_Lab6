`timescale 1ns / 1ps

//============================================================================
// Testbench: Fibonacci on RV64I 5-Stage Pipeline (Compiler Baremetal)
//
// C program:
//   int n = 10, a = 0, b = 1, c;
//   for (i = 2; i < n; i++) { c = a+b; a = b; b = c; }
//
// Fibonacci sequence: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34
// After loop: a = 21 (fib(8)), b = 34 (fib(9))
//
// fp = 0x21C (540)
//   a at [fp-8]  = 0x214, mem[66][63:32]
//   b at [fp-12] = 0x210, mem[66][31:0]
//   i at [fp-16] = 0x20C, mem[65][63:32]
//   n at [fp-20] = 0x208, mem[65][31:0]
//   c at [fp-24] = 0x204, mem[64][63:32]
//============================================================================

module tb_fibonacci;

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

    initial begin
        rst_n       = 0;
        done        = 0;
        cycle_count = 0;
        pass_count  = 0;
        fail_count  = 0;
        mem_val     = 0;
        exp_val     = 0;
        i           = 0;

        #25;
        rst_n = 1;

        // Load program
        //============================================================
        // PART 1: base addr (no array data, but keep x19 for consistency)
        //============================================================
        dut.u_instr_mem.mem[ 0] = 32'h20000993;  // addi x19, x0, 512     # base = 0x200

        //============================================================
        // PART 1.5: fp/sp init
        // fp = 0x21C (540), sp = fp (no push offset in this version)
        //============================================================
        dut.u_instr_mem.mem[ 1] = 32'h21C00413;  // addi x8, x0, 540      # fp = 0x21C
        dut.u_instr_mem.mem[ 2] = 32'h00040113;  // addi x2, x8, 0        # sp = fp

        //============================================================
        // PART 2: Fibonacci algorithm
        //============================================================
        // push fp (str fp, [sp, #-4]!)
        dut.u_instr_mem.mem[ 3] = 32'hFE812E23;  // sw   x8, -4(x2)
        dut.u_instr_mem.mem[ 4] = 32'hFFC10113;  // addi x2, x2, -4       # sp--
        // n = 10
        dut.u_instr_mem.mem[ 5] = 32'h00A00693;  // addi x13, x0, 10
        dut.u_instr_mem.mem[ 6] = 32'hFED42623;  // sw   x13, -20(x8)     # n = 10
        // a = 0
        dut.u_instr_mem.mem[ 7] = 32'h00000693;  // addi x13, x0, 0
        dut.u_instr_mem.mem[ 8] = 32'hFED42C23;  // sw   x13, -8(x8)      # a = 0
        // b = 1
        dut.u_instr_mem.mem[ 9] = 32'h00100693;  // addi x13, x0, 1
        dut.u_instr_mem.mem[10] = 32'hFED42A23;  // sw   x13, -12(x8)     # b = 1
        // i = 2
        dut.u_instr_mem.mem[11] = 32'h00200693;  // addi x13, x0, 2
        dut.u_instr_mem.mem[12] = 32'hFED42823;  // sw   x13, -16(x8)     # i = 2
        // goto .L2
        dut.u_instr_mem.mem[13] = 32'h0300006F;  // jal  x0, .L2          # goto [25]
        // .L3 [14]: loop body — c = a + b
        dut.u_instr_mem.mem[14] = 32'hFF842603;  // lw   x12, -8(x8)      # a
        dut.u_instr_mem.mem[15] = 32'hFF442683;  // lw   x13, -12(x8)     # b
        dut.u_instr_mem.mem[16] = 32'h00D606B3;  // add  x13, x12, x13    # c = a + b
        dut.u_instr_mem.mem[17] = 32'hFED42423;  // sw   x13, -24(x8)     # store c
        // a = b
        dut.u_instr_mem.mem[18] = 32'hFF442683;  // lw   x13, -12(x8)     # b
        dut.u_instr_mem.mem[19] = 32'hFED42C23;  // sw   x13, -8(x8)      # a = b
        // b = c
        dut.u_instr_mem.mem[20] = 32'hFE842683;  // lw   x13, -24(x8)     # c
        dut.u_instr_mem.mem[21] = 32'hFED42A23;  // sw   x13, -12(x8)     # b = c
        // i++
        dut.u_instr_mem.mem[22] = 32'hFF042683;  // lw   x13, -16(x8)     # i
        dut.u_instr_mem.mem[23] = 32'h00168693;  // addi x13, x13, 1
        dut.u_instr_mem.mem[24] = 32'hFED42823;  // sw   x13, -16(x8)     # i++
        // .L2 [25]: loop check (i < n)
        dut.u_instr_mem.mem[25] = 32'hFF042603;  // lw   x12, -16(x8)     # i
        dut.u_instr_mem.mem[26] = 32'hFEC42683;  // lw   x13, -20(x8)     # n
        dut.u_instr_mem.mem[27] = 32'hFCD646E3;  // blt  x12, x13, .L3    # if i<n goto [14]
        // return 0
        dut.u_instr_mem.mem[28] = 32'h00000693;  // addi x13, x0, 0
        dut.u_instr_mem.mem[29] = 32'h00068513;  // addi x10, x13, 0
        // epilogue
        dut.u_instr_mem.mem[30] = 32'h00040113;  // addi x2, x8, 0        # sp = fp
        dut.u_instr_mem.mem[31] = 32'h00012403;  // lw   x8, 0(x2)        # restore fp
        // done + halt
        dut.u_instr_mem.mem[32] = 32'h00100F93;  // addi x31, x0, 1       # done flag
        dut.u_instr_mem.mem[33] = 32'h0000006F;  // jal  x0, 0            # halt

        $display("");
        $display("============================================================");
        $display("  DEBUG: Fibonacci Pipeline Trace (Baremetal)");
        $display("============================================================");
        $display("  n = 10");
        $display("  Expected: fib(0..9) = 0,1,1,2,3,5,8,13,21,34");
        $display("  Final: a = 21, b = 34");
        $display("============================================================");

        @(posedge clk);
        @(posedge clk);

        done = 0;
        begin : main_loop
            for (cycle_count = 1; cycle_count <= 5000; cycle_count = cycle_count + 1) begin
                @(posedge clk);

                // Monitor: loop body at [14] .L3 (addr 0x038)
                // At this point x12=a, x13=b (just loaded)
                if (dut.pc_current == 64'h0038) begin
                    $display("[Cycle %0d] Loop: a(x12)=%0d  b(x13)=%0d",
                        cycle_count,
                        $signed(dut.u_regfile.regs[12]),
                        $signed(dut.u_regfile.regs[13]));
                end

                // Monitor: add at [16] (addr 0x040) — c = a + b
                if (dut.pc_current == 64'h0040) begin
                    $display("[Cycle %0d] c = a+b: a(x12)=%0d + b(x13)=%0d = %0d",
                        cycle_count,
                        $signed(dut.u_regfile.regs[12]),
                        $signed(dut.u_regfile.regs[13]),
                        $signed(dut.u_regfile.regs[12]) + $signed(dut.u_regfile.regs[13]));
                end

                // Monitor: loop check at [25] .L2 (addr 0x064)
                if (dut.pc_current == 64'h0064) begin
                    $display("[Cycle %0d] Check: i(x12)=%0d  n(x13)=%0d",
                        cycle_count,
                        $signed(dut.u_regfile.regs[12]),
                        $signed(dut.u_regfile.regs[13]));
                end

                // Check done flag
                if (dut.u_regfile.regs[31] === 64'd1) begin
                    done = 1;
                    disable main_loop;
                end
            end
        end // main_loop

        if (done)
            $display("\n  Fibonacci completed at cycle %0d", cycle_count);
        else
            $display("\n  WARNING: Timeout at cycle %0d!", cycle_count);

        //============================================================
        // Verification: check final variable values in memory
        //============================================================
        $display("");
        pass_count = 0;
        fail_count = 0;

        // a at [fp-8] = 0x214 → mem[66][63:32]
        mem_val = $signed(dut.u_data_mem.mem[66][63:32]);
        exp_val = 21;
        if (mem_val == exp_val) begin
            $display("  a (fib(8)) = %0d  PASS", mem_val);
            pass_count = pass_count + 1;
        end else begin
            $display("  a (fib(8)) = %0d  (expect %0d)  FAIL", mem_val, exp_val);
            fail_count = fail_count + 1;
        end

        // b at [fp-12] = 0x210 → mem[66][31:0]
        mem_val = $signed(dut.u_data_mem.mem[66][31:0]);
        exp_val = 34;
        if (mem_val == exp_val) begin
            $display("  b (fib(9)) = %0d  PASS", mem_val);
            pass_count = pass_count + 1;
        end else begin
            $display("  b (fib(9)) = %0d  (expect %0d)  FAIL", mem_val, exp_val);
            fail_count = fail_count + 1;
        end

        // i at [fp-16] = 0x20C → mem[65][63:32]
        mem_val = $signed(dut.u_data_mem.mem[65][63:32]);
        exp_val = 10;
        if (mem_val == exp_val) begin
            $display("  i (final)  = %0d  PASS", mem_val);
            pass_count = pass_count + 1;
        end else begin
            $display("  i (final)  = %0d  (expect %0d)  FAIL", mem_val, exp_val);
            fail_count = fail_count + 1;
        end

        // n at [fp-20] = 0x208 → mem[65][31:0]
        mem_val = $signed(dut.u_data_mem.mem[65][31:0]);
        exp_val = 10;
        if (mem_val == exp_val) begin
            $display("  n          = %0d  PASS", mem_val);
            pass_count = pass_count + 1;
        end else begin
            $display("  n          = %0d  (expect %0d)  FAIL", mem_val, exp_val);
            fail_count = fail_count + 1;
        end

        // c at [fp-24] = 0x204 → mem[64][63:32]
        mem_val = $signed(dut.u_data_mem.mem[64][63:32]);
        exp_val = 34;
        if (mem_val == exp_val) begin
            $display("  c (last)   = %0d  PASS", mem_val);
            pass_count = pass_count + 1;
        end else begin
            $display("  c (last)   = %0d  (expect %0d)  FAIL", mem_val, exp_val);
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