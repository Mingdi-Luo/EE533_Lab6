`timescale 1ns / 1ps

//============================================================================
// Testbench: Bubble Sort on RV64I 5-Stage Pipeline (Compiler Baremetal)
//============================================================================

module tb_compiler_bubblesort;

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
    reg     sort_done;
    reg signed [63:0] mem_val;
    reg signed [63:0] exp_val;
    
    reg [63:0] prev_pc;
    reg [63:0] prev_prev_pc;

    initial begin
        rst_n       = 0;
        sort_done   = 0;
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

        // Load program (baremetal mode)
        dut.u_instr_mem.mem[ 0] = 32'h20000993;  // addi x19, x0, 512     # base = 0x200
        dut.u_instr_mem.mem[ 1] = 32'h14300593;  // addi x11, x0, 323
        dut.u_instr_mem.mem[ 2] = 32'h00B9A023;  // sw   x11, 0(x19)      # arr[0] = 323
        dut.u_instr_mem.mem[ 3] = 32'h07B00593;  // addi x11, x0, 123
        dut.u_instr_mem.mem[ 4] = 32'h00B9A223;  // sw   x11, 4(x19)      # arr[1] = 123
        dut.u_instr_mem.mem[ 5] = 32'hE3900593;  // addi x11, x0, -455
        dut.u_instr_mem.mem[ 6] = 32'h00B9A423;  // sw   x11, 8(x19)      # arr[2] = -455
        dut.u_instr_mem.mem[ 7] = 32'h00200593;  // addi x11, x0, 2
        dut.u_instr_mem.mem[ 8] = 32'h00B9A623;  // sw   x11, 12(x19)     # arr[3] = 2
        dut.u_instr_mem.mem[ 9] = 32'h06200593;  // addi x11, x0, 98
        dut.u_instr_mem.mem[10] = 32'h00B9A823;  // sw   x11, 16(x19)     # arr[4] = 98
        dut.u_instr_mem.mem[11] = 32'h07D00593;  // addi x11, x0, 125
        dut.u_instr_mem.mem[12] = 32'h00B9AA23;  // sw   x11, 20(x19)     # arr[5] = 125
        dut.u_instr_mem.mem[13] = 32'h00A00593;  // addi x11, x0, 10
        dut.u_instr_mem.mem[14] = 32'h00B9AC23;  // sw   x11, 24(x19)     # arr[6] = 10
        dut.u_instr_mem.mem[15] = 32'h04100593;  // addi x11, x0, 65
        dut.u_instr_mem.mem[16] = 32'h00B9AE23;  // sw   x11, 28(x19)     # arr[7] = 65
        dut.u_instr_mem.mem[17] = 32'hFC800593;  // addi x11, x0, -56
        dut.u_instr_mem.mem[18] = 32'h02B9A023;  // sw   x11, 32(x19)     # arr[8] = -56
        dut.u_instr_mem.mem[19] = 32'h00000593;  // addi x11, x0, 0
        dut.u_instr_mem.mem[20] = 32'h02B9A223;  // sw   x11, 36(x19)     # arr[9] = 0
        // fp/sp init
        dut.u_instr_mem.mem[21] = 32'h23800413;  // addi x8, x0, 568      # fp = 0x238
        dut.u_instr_mem.mem[22] = 32'hFFC40113;  // addi x2, x8, -4       # sp = 0x234
        // i = 0
        dut.u_instr_mem.mem[23] = 32'h00000693;  // addi x13, x0, 0
        dut.u_instr_mem.mem[24] = 32'hFED42C23;  // sw   x13, -8(x8)
        dut.u_instr_mem.mem[25] = 32'h0BC0006F;  // jal  x0, .L2
        // .L6: j = i+1
        dut.u_instr_mem.mem[26] = 32'hFF842683;  // lw   x13, -8(x8)
        dut.u_instr_mem.mem[27] = 32'h00168693;  // addi x13, x13, 1
        dut.u_instr_mem.mem[28] = 32'hFED42A23;  // sw   x13, -12(x8)
        dut.u_instr_mem.mem[29] = 32'h0940006F;  // jal  x0, .L3
        // .L5: inner body
        dut.u_instr_mem.mem[30] = 32'hFF442683;  // lw   x13, -12(x8)     # load j
        dut.u_instr_mem.mem[31] = 32'h00269693;  // slli x13, x13, 2
        dut.u_instr_mem.mem[32] = 32'hFFC68693;  // addi x13, x13, -4
        dut.u_instr_mem.mem[33] = 32'h008686B3;  // add  x13, x13, x8
        dut.u_instr_mem.mem[34] = 32'hFCC6A603;  // lw   x12, -52(x13)    # arr[j]
        dut.u_instr_mem.mem[35] = 32'hFF842683;  // lw   x13, -8(x8)      # load i
        dut.u_instr_mem.mem[36] = 32'h00269693;  // slli x13, x13, 2
        dut.u_instr_mem.mem[37] = 32'hFFC68693;  // addi x13, x13, -4
        dut.u_instr_mem.mem[38] = 32'h008686B3;  // add  x13, x13, x8
        dut.u_instr_mem.mem[39] = 32'hFCC6A683;  // lw   x13, -52(x13)    # arr[i]
        dut.u_instr_mem.mem[40] = 32'h04D65E63;  // bge  x12, x13, .L4    # skip if arr[j]>=arr[i]
        // swap
        dut.u_instr_mem.mem[41] = 32'hFF442683;
        dut.u_instr_mem.mem[42] = 32'h00269693;
        dut.u_instr_mem.mem[43] = 32'hFFC68693;
        dut.u_instr_mem.mem[44] = 32'h008686B3;
        dut.u_instr_mem.mem[45] = 32'hFCC6A683;  // temp = arr[j]
        dut.u_instr_mem.mem[46] = 32'hFED42823;  // sw temp
        dut.u_instr_mem.mem[47] = 32'hFF842683;
        dut.u_instr_mem.mem[48] = 32'h00269693;
        dut.u_instr_mem.mem[49] = 32'hFFC68693;
        dut.u_instr_mem.mem[50] = 32'h008686B3;
        dut.u_instr_mem.mem[51] = 32'hFCC6A603;  // arr[i]
        dut.u_instr_mem.mem[52] = 32'hFF442683;
        dut.u_instr_mem.mem[53] = 32'h00269693;
        dut.u_instr_mem.mem[54] = 32'hFFC68693;
        dut.u_instr_mem.mem[55] = 32'h008686B3;
        dut.u_instr_mem.mem[56] = 32'hFCC6A623;  // arr[j] = arr[i]
        dut.u_instr_mem.mem[57] = 32'hFF842683;
        dut.u_instr_mem.mem[58] = 32'h00269693;
        dut.u_instr_mem.mem[59] = 32'hFFC68693;
        dut.u_instr_mem.mem[60] = 32'h008686B3;
        dut.u_instr_mem.mem[61] = 32'hFF042603;  // load temp
        dut.u_instr_mem.mem[62] = 32'hFCC6A623;  // arr[i] = temp
        // .L4: j++
        dut.u_instr_mem.mem[63] = 32'hFF442683;
        dut.u_instr_mem.mem[64] = 32'h00168693;
        dut.u_instr_mem.mem[65] = 32'hFED42A23;
        // .L3: inner check
        dut.u_instr_mem.mem[66] = 32'hFF442683;
        dut.u_instr_mem.mem[67] = 32'h00900F13;
        dut.u_instr_mem.mem[68] = 32'hF6DF54E3;  // bge x30, x13, .L5
        // i++
        dut.u_instr_mem.mem[69] = 32'hFF842683;
        dut.u_instr_mem.mem[70] = 32'h00168693;
        dut.u_instr_mem.mem[71] = 32'hFED42C23;
        // .L2: outer check
        dut.u_instr_mem.mem[72] = 32'hFF842683;
        dut.u_instr_mem.mem[73] = 32'h00900F13;
        dut.u_instr_mem.mem[74] = 32'hF4DF50E3;  // bge x30, x13, .L6
        // return 0
        dut.u_instr_mem.mem[75] = 32'h00000693;
        dut.u_instr_mem.mem[76] = 32'h00068513;
        // done + halt
        dut.u_instr_mem.mem[77] = 32'h00100F93;  // addi x31, x0, 1
        dut.u_instr_mem.mem[78] = 32'h0000006F;  // jal  x0, 0

        $display("");
        $display("============================================================");
        $display("  DEBUG: Bubble Sort Pipeline Trace (Baremetal)");
        $display("============================================================");
        $display("  Array: {323, 123, -455, 2, 98, 125, 10, 65, -56, 0}");
        $display("  Expected: {-455, -56, 0, 2, 10, 65, 98, 123, 125, 323}");
        $display("============================================================");

        @(posedge clk);
        @(posedge clk);

        //==========================================================
        // FIX: for loop INSIDE named block so disable works
        //==========================================================
        sort_done = 0;
        begin : main_loop
            for (cycle_count = 1; cycle_count <= 60000; cycle_count = cycle_count + 1) begin
                @(posedge clk);
                
                prev_prev_pc = prev_pc;
                prev_pc = dut.pc_current;

                // Monitor: outer loop entry at [26] .L6 (addr 0x068)
                if (dut.pc_current == 64'h0068) begin
                    $display("[Cycle %0d] --- Outer loop: i=%0d ---",
                        cycle_count, $signed(dut.u_regfile.regs[13]));
                    $write("  Array: { ");
                    for (i = 0; i < 10; i = i + 1) begin
                        if (i > 0) $write(", ");
                        if (i % 2 == 0)
                            $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][31:0]));
                        else
                            $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][63:32]));
                    end
                    $display(" }");
                end

                // Monitor: compare at [40] (addr 0x0A0)
                if (dut.pc_current == 64'h00A0) begin
                    $display("[Cycle %0d] Compare: arr[j](x12)=%0d  arr[i](x13)=%0d",
                        cycle_count,
                        $signed(dut.u_regfile.regs[12]),
                        $signed(dut.u_regfile.regs[13]));
                end

                // Check done flag
                if (dut.u_regfile.regs[31] === 64'd1) begin
                    sort_done = 1;
                    disable main_loop;
                end
            end
        end // main_loop

        if (sort_done)
            $display("\n  Sort completed at cycle %0d", cycle_count);
        else
            $display("\n  WARNING: Timeout at cycle %0d!", cycle_count);

        // Print sorted array
        $display("");
        $display("Sorted array:");
        $write("  { ");
        for (i = 0; i < 10; i = i + 1) begin
            if (i > 0) $write(", ");
            if (i % 2 == 0)
                $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][31:0]));
            else
                $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][63:32]));
        end
        $display(" }");
        $display("");
        $display("Expected:");
        $display("  { -455, -56, 0, 2, 10, 65, 98, 123, 125, 323 }");

        // Verification
        pass_count = 0;
        fail_count = 0;
        $display("");
        for (i = 0; i < 10; i = i + 1) begin
            if (i % 2 == 0)
                mem_val = $signed(dut.u_data_mem.mem[64 + i/2][31:0]);
            else
                mem_val = $signed(dut.u_data_mem.mem[64 + i/2][63:32]);
            case (i)
                0: exp_val = -455;  1: exp_val = -56;
                2: exp_val = 0;     3: exp_val = 2;
                4: exp_val = 10;    5: exp_val = 65;
                6: exp_val = 98;    7: exp_val = 123;
                8: exp_val = 125;   9: exp_val = 323;
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