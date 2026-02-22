`timescale 1ns / 1ps

//============================================================================
// Testbench: Remove Duplicates on RV64I 5-Stage Pipeline (Compiler Baremetal)
//
// C program:
//   int nums[] = {1, 1, 2, 2, 3, 4, 4};  n = 7;
//   fast = 1; slow = 1;
//   while (fast < n) {
//       if (nums[fast] != nums[fast-1]) { nums[slow]=nums[fast]; slow++; }
//       fast++;
//   }
//   return slow;  // expected: 4
//
// Array after: {1, 2, 3, 4, 3, 4, 4}  (first 4 elements are unique)
// Return value: slow = 4 (in x10)
//
// fp = 0x22C (556), nums[0] at [fp-44] = 0x200
// nums[0..6] at byte 0x200..0x218 (32-bit words, sw)
//   fast at [fp-8]  = 0x224, mem[68][63:32]
//   slow at [fp-12] = 0x220, mem[68][31:0]
//   n    at [fp-16] = 0x21C, mem[67][63:32]
//============================================================================

module tb_remove_duplicate;

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

        // Load program (exact compiler baremetal output)
        //============================================================
        // PART 1: Array init {1,1,2,2,3,4,4}
        //============================================================
        dut.u_instr_mem.mem[ 0] = 32'h20000993;  // addi x19, x0, 512     # base = 0x200
        dut.u_instr_mem.mem[ 1] = 32'h00100593;  // addi x11, x0, 1
        dut.u_instr_mem.mem[ 2] = 32'h00B9A023;  // sw   x11, 0(x19)      # nums[0] = 1
        dut.u_instr_mem.mem[ 3] = 32'h00100593;  // addi x11, x0, 1
        dut.u_instr_mem.mem[ 4] = 32'h00B9A223;  // sw   x11, 4(x19)      # nums[1] = 1
        dut.u_instr_mem.mem[ 5] = 32'h00200593;  // addi x11, x0, 2
        dut.u_instr_mem.mem[ 6] = 32'h00B9A423;  // sw   x11, 8(x19)      # nums[2] = 2
        dut.u_instr_mem.mem[ 7] = 32'h00200593;  // addi x11, x0, 2
        dut.u_instr_mem.mem[ 8] = 32'h00B9A623;  // sw   x11, 12(x19)     # nums[3] = 2
        dut.u_instr_mem.mem[ 9] = 32'h00300593;  // addi x11, x0, 3
        dut.u_instr_mem.mem[10] = 32'h00B9A823;  // sw   x11, 16(x19)     # nums[4] = 3
        dut.u_instr_mem.mem[11] = 32'h00400593;  // addi x11, x0, 4
        dut.u_instr_mem.mem[12] = 32'h00B9AA23;  // sw   x11, 20(x19)     # nums[5] = 4
        dut.u_instr_mem.mem[13] = 32'h00400593;  // addi x11, x0, 4
        dut.u_instr_mem.mem[14] = 32'h00B9AC23;  // sw   x11, 24(x19)     # nums[6] = 4

        //============================================================
        // PART 1.5: fp/sp init
        // fp = 0x22C (556), [fp-44] = 0x200 = nums[0]
        //============================================================
        dut.u_instr_mem.mem[15] = 32'h22C00413;  // addi x8, x0, 556      # fp = 0x22C
        dut.u_instr_mem.mem[16] = 32'hFFC40113;  // addi x2, x8, -4       # sp = 0x228

        //============================================================
        // PART 2: Remove duplicates algorithm
        //============================================================
        // n = 7
        dut.u_instr_mem.mem[17] = 32'h00700693;  // addi x13, x0, 7
        dut.u_instr_mem.mem[18] = 32'hFED42823;  // sw   x13, -16(x8)     # n = 7
        // if (n == 0) return 0
        dut.u_instr_mem.mem[19] = 32'hFF042683;  // lw   x13, -16(x8)     # load n
        dut.u_instr_mem.mem[20] = 32'h00000F13;  // addi x30, x0, 0
        dut.u_instr_mem.mem[21] = 32'h01E69663;  // bne  x13, x30, .L2    # if n!=0 goto [24]
        dut.u_instr_mem.mem[22] = 32'h00000693;  // addi x13, x0, 0       # return 0
        dut.u_instr_mem.mem[23] = 32'h0980006F;  // jal  x0, .L7          # goto [61]
        // .L2 [24]: fast = 1, slow = 1
        dut.u_instr_mem.mem[24] = 32'h00100693;  // addi x13, x0, 1
        dut.u_instr_mem.mem[25] = 32'hFED42C23;  // sw   x13, -8(x8)      # fast = 1
        dut.u_instr_mem.mem[26] = 32'h00100693;  // addi x13, x0, 1
        dut.u_instr_mem.mem[27] = 32'hFED42A23;  // sw   x13, -12(x8)     # slow = 1
        dut.u_instr_mem.mem[28] = 32'h0740006F;  // jal  x0, .L4          # goto [57]
        // .L6 [29]: load nums[fast]
        dut.u_instr_mem.mem[29] = 32'hFF842683;  // lw   x13, -8(x8)      # fast
        dut.u_instr_mem.mem[30] = 32'h00269693;  // slli x13, x13, 2
        dut.u_instr_mem.mem[31] = 32'hFFC68693;  // addi x13, x13, -4
        dut.u_instr_mem.mem[32] = 32'h008686B3;  // add  x13, x13, x8
        dut.u_instr_mem.mem[33] = 32'hFD86A603;  // lw   x12, -40(x13)    # nums[fast]
        // load nums[fast-1]
        dut.u_instr_mem.mem[34] = 32'hFF842683;  // lw   x13, -8(x8)      # fast
        dut.u_instr_mem.mem[35] = 32'hFFF68693;  // addi x13, x13, -1     # fast-1
        dut.u_instr_mem.mem[36] = 32'h00269693;  // slli x13, x13, 2
        dut.u_instr_mem.mem[37] = 32'hFFC68693;  // addi x13, x13, -4
        dut.u_instr_mem.mem[38] = 32'h008686B3;  // add  x13, x13, x8
        dut.u_instr_mem.mem[39] = 32'hFD86A683;  // lw   x13, -40(x13)    # nums[fast-1]
        // compare
        dut.u_instr_mem.mem[40] = 32'h02D60C63;  // beq  x12, x13, .L5    # if equal skip → [54]
        // not equal: nums[slow] = nums[fast]
        dut.u_instr_mem.mem[41] = 32'hFF842683;  // lw   x13, -8(x8)      # fast
        dut.u_instr_mem.mem[42] = 32'h00269693;  // slli
        dut.u_instr_mem.mem[43] = 32'hFFC68693;  // addi
        dut.u_instr_mem.mem[44] = 32'h008686B3;  // add
        dut.u_instr_mem.mem[45] = 32'hFD86A603;  // lw   x12, -40(x13)    # nums[fast]
        dut.u_instr_mem.mem[46] = 32'hFF442683;  // lw   x13, -12(x8)     # slow
        dut.u_instr_mem.mem[47] = 32'h00269693;  // slli
        dut.u_instr_mem.mem[48] = 32'hFFC68693;  // addi
        dut.u_instr_mem.mem[49] = 32'h008686B3;  // add
        dut.u_instr_mem.mem[50] = 32'hFCC6AC23;  // sw   x12, -40(x13)    # nums[slow]=nums[fast]
        // slow++
        dut.u_instr_mem.mem[51] = 32'hFF442683;  // lw   x13, -12(x8)
        dut.u_instr_mem.mem[52] = 32'h00168693;  // addi x13, x13, 1
        dut.u_instr_mem.mem[53] = 32'hFED42A23;  // sw   x13, -12(x8)     # slow++
        // .L5 [54]: fast++
        dut.u_instr_mem.mem[54] = 32'hFF842683;  // lw   x13, -8(x8)
        dut.u_instr_mem.mem[55] = 32'h00168693;  // addi x13, x13, 1
        dut.u_instr_mem.mem[56] = 32'hFED42C23;  // sw   x13, -8(x8)      # fast++
        // .L4 [57]: while (fast < n)
        dut.u_instr_mem.mem[57] = 32'hFF842603;  // lw   x12, -8(x8)      # fast
        dut.u_instr_mem.mem[58] = 32'hFF042683;  // lw   x13, -16(x8)     # n
        dut.u_instr_mem.mem[59] = 32'hF8D644E3;  // blt  x12, x13, .L6    # if fast<n goto [29]
        // return slow
        dut.u_instr_mem.mem[60] = 32'hFF442683;  // lw   x13, -12(x8)     # slow
        // .L7 [61]:
        dut.u_instr_mem.mem[61] = 32'h00068513;  // addi x10, x13, 0      # return slow
        // done + halt
        dut.u_instr_mem.mem[62] = 32'h00100F93;  // addi x31, x0, 1       # done flag
        dut.u_instr_mem.mem[63] = 32'h0000006F;  // jal  x0, 0            # halt

        $display("");
        $display("============================================================");
        $display("  DEBUG: Remove Duplicates Pipeline Trace (Baremetal)");
        $display("============================================================");
        $display("  Array: {1, 1, 2, 2, 3, 4, 4}");
        $display("  Expected unique: {1, 2, 3, 4}  slow = 4");
        $display("============================================================");

        @(posedge clk);
        @(posedge clk);

        done = 0;
        begin : main_loop
            for (cycle_count = 1; cycle_count <= 10000; cycle_count = cycle_count + 1) begin
                @(posedge clk);

                // Monitor: compare at [40] beq (addr 40*4=0x0A0)
                if (dut.pc_current == 64'h00A0) begin
                    $display("[Cycle %0d] Compare: nums[fast](x12)=%0d  nums[fast-1](x13)=%0d  %s",
                        cycle_count,
                        $signed(dut.u_regfile.regs[12]),
                        $signed(dut.u_regfile.regs[13]),
                        (dut.u_regfile.regs[12] == dut.u_regfile.regs[13]) ? "EQUAL(skip)" : "DIFF(copy)");
                end

                // Monitor: while check at [57] .L4 (addr 57*4=0x0E4)
                if (dut.pc_current == 64'h00E4) begin
                    $display("[Cycle %0d] While: fast(x12)=%0d  n(x13)=%0d",
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
            $display("\n  Remove duplicates completed at cycle %0d", cycle_count);
        else
            $display("\n  WARNING: Timeout at cycle %0d!", cycle_count);

        // Print array after dedup
        $display("");
        $display("Array after dedup:");
        $write("  { ");
        for (i = 0; i < 7; i = i + 1) begin
            if (i > 0) $write(", ");
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

        // Check 1: return value (slow) in x10
        $display("--- Return value check ---");
        mem_val = dut.u_regfile.regs[10];
        exp_val = 4;
        if ($signed(mem_val) == $signed(exp_val)) begin
            $display("  x10 (slow) = %0d  PASS", $signed(mem_val));
            pass_count = pass_count + 1;
        end else begin
            $display("  x10 (slow) = %0d  (expect %0d)  FAIL", $signed(mem_val), $signed(exp_val));
            fail_count = fail_count + 1;
        end

        // Check 2: unique portion {1, 2, 3, 4}
        $display("");
        $display("--- Unique portion check (first 4 elements) ---");
        for (i = 0; i < 4; i = i + 1) begin
            if (i % 2 == 0)
                mem_val = $signed(dut.u_data_mem.mem[64 + i/2][31:0]);
            else
                mem_val = $signed(dut.u_data_mem.mem[64 + i/2][63:32]);
            case (i)
                0: exp_val = 1;
                1: exp_val = 2;
                2: exp_val = 3;
                3: exp_val = 4;
                default: exp_val = 0;
            endcase
            if (mem_val == exp_val) begin
                $display("  nums[%0d] = %0d  PASS", i, mem_val);
                pass_count = pass_count + 1;
            end else begin
                $display("  nums[%0d] = %0d  (expect %0d)  FAIL", i, mem_val, exp_val);
                fail_count = fail_count + 1;
            end
        end

        // Check 3: variables in memory
        $display("");
        $display("--- Variable check ---");
        // slow at [fp-12] = 0x220 → mem[68][31:0]
        mem_val = $signed(dut.u_data_mem.mem[68][31:0]);
        exp_val = 4;
        if (mem_val == exp_val) begin
            $display("  slow (mem) = %0d  PASS", mem_val);
            pass_count = pass_count + 1;
        end else begin
            $display("  slow (mem) = %0d  (expect %0d)  FAIL", mem_val, exp_val);
            fail_count = fail_count + 1;
        end

        // fast at [fp-8] = 0x224 → mem[68][63:32]
        mem_val = $signed(dut.u_data_mem.mem[68][63:32]);
        exp_val = 7;
        if (mem_val == exp_val) begin
            $display("  fast (mem) = %0d  PASS", mem_val);
            pass_count = pass_count + 1;
        end else begin
            $display("  fast (mem) = %0d  (expect %0d)  FAIL", mem_val, exp_val);
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