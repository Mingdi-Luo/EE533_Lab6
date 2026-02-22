`timescale 1ns / 1ps

//============================================================================
// Testbench: Selection Sort on RV64I 5-Stage Pipeline (Compiler Baremetal)
//
// C program:
//   int arr[8] = {7, 3, 9, 1, 5, 2, 8, 4};
//   for (i = 0; i < 7; i++) {
//       min = i;
//       for (j = i+1; j < 8; j++)
//           if (arr[j] < arr[min]) min = j;
//       temp=arr[i]; arr[i]=arr[min]; arr[min]=temp;
//   }
//
// Array: {7, 3, 9, 1, 5, 2, 8, 4}
// Expected sorted: {1, 2, 3, 4, 5, 7, 8, 9}
//
// fp = 0x234 (564), arr[0] at [fp-52] = 0x200
// arr[0..7] at byte 0x200..0x21C (32-bit words, sw)
//============================================================================

module tb_selectionsort;

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

        #25;
        rst_n = 1;

        // Load program
        //============================================================
        // PART 1: Array init {7,3,9,1,5,2,8,4} using sw, 4-byte stride
        //============================================================
        dut.u_instr_mem.mem[ 0] = 32'h20000993;  // addi x19, x0, 512     # base = 0x200
        dut.u_instr_mem.mem[ 1] = 32'h00700593;  // addi x11, x0, 7
        dut.u_instr_mem.mem[ 2] = 32'h00B9A023;  // sw   x11, 0(x19)      # arr[0] = 7
        dut.u_instr_mem.mem[ 3] = 32'h00300593;  // addi x11, x0, 3
        dut.u_instr_mem.mem[ 4] = 32'h00B9A223;  // sw   x11, 4(x19)      # arr[1] = 3
        dut.u_instr_mem.mem[ 5] = 32'h00900593;  // addi x11, x0, 9
        dut.u_instr_mem.mem[ 6] = 32'h00B9A423;  // sw   x11, 8(x19)      # arr[2] = 9
        dut.u_instr_mem.mem[ 7] = 32'h00100593;  // addi x11, x0, 1
        dut.u_instr_mem.mem[ 8] = 32'h00B9A623;  // sw   x11, 12(x19)     # arr[3] = 1
        dut.u_instr_mem.mem[ 9] = 32'h00500593;  // addi x11, x0, 5
        dut.u_instr_mem.mem[10] = 32'h00B9A823;  // sw   x11, 16(x19)     # arr[4] = 5
        dut.u_instr_mem.mem[11] = 32'h00200593;  // addi x11, x0, 2
        dut.u_instr_mem.mem[12] = 32'h00B9AA23;  // sw   x11, 20(x19)     # arr[5] = 2
        dut.u_instr_mem.mem[13] = 32'h00800593;  // addi x11, x0, 8
        dut.u_instr_mem.mem[14] = 32'h00B9AC23;  // sw   x11, 24(x19)     # arr[6] = 8
        dut.u_instr_mem.mem[15] = 32'h00400593;  // addi x11, x0, 4
        dut.u_instr_mem.mem[16] = 32'h00B9AE23;  // sw   x11, 28(x19)     # arr[7] = 4

        //============================================================
        // PART 1.5: fp/sp init
        // fp = 0x234 (564) so [fp-52] = 0x200 = arr[0]
        //============================================================
        dut.u_instr_mem.mem[17] = 32'h23400413;  // addi x8, x0, 564      # fp = 0x234
        dut.u_instr_mem.mem[18] = 32'hFFC40113;  // addi x2, x8, -4       # sp = 0x230

        //============================================================
        // PART 2: Selection sort algorithm
        //============================================================
        // i = 0
        dut.u_instr_mem.mem[19] = 32'h00000693;  // addi x13, x0, 0
        dut.u_instr_mem.mem[20] = 32'hFED42C23;  // sw   x13, -8(x8)      # i = 0
        dut.u_instr_mem.mem[21] = 32'h0CC0006F;  // jal  x0, .L2          # goto [72]
        // .L6 [22]: min = i; j = i+1
        dut.u_instr_mem.mem[22] = 32'hFF842683;  // lw   x13, -8(x8)      # load i
        dut.u_instr_mem.mem[23] = 32'hFED42823;  // sw   x13, -16(x8)     # min = i
        dut.u_instr_mem.mem[24] = 32'hFF842683;  // lw   x13, -8(x8)
        dut.u_instr_mem.mem[25] = 32'h00168693;  // addi x13, x13, 1
        dut.u_instr_mem.mem[26] = 32'hFED42A23;  // sw   x13, -12(x8)     # j = i+1
        dut.u_instr_mem.mem[27] = 32'h0440006F;  // jal  x0, .L3          # goto [44]
        // .L5 [28]: compare arr[j] vs arr[min]
        dut.u_instr_mem.mem[28] = 32'hFF442683;  // lw   x13, -12(x8)     # j
        dut.u_instr_mem.mem[29] = 32'h00269693;  // slli x13, x13, 2
        dut.u_instr_mem.mem[30] = 32'hFFC68693;  // addi x13, x13, -4
        dut.u_instr_mem.mem[31] = 32'h008686B3;  // add  x13, x13, x8
        dut.u_instr_mem.mem[32] = 32'hFD06A603;  // lw   x12, -48(x13)    # arr[j]
        dut.u_instr_mem.mem[33] = 32'hFF042683;  // lw   x13, -16(x8)     # min
        dut.u_instr_mem.mem[34] = 32'h00269693;  // slli x13, x13, 2
        dut.u_instr_mem.mem[35] = 32'hFFC68693;  // addi x13, x13, -4
        dut.u_instr_mem.mem[36] = 32'h008686B3;  // add  x13, x13, x8
        dut.u_instr_mem.mem[37] = 32'hFD06A683;  // lw   x13, -48(x13)    # arr[min]
        dut.u_instr_mem.mem[38] = 32'h00D65663;  // bge  x12, x13, .L4    # skip if arr[j]>=arr[min]
        // arr[j] < arr[min] → min = j
        dut.u_instr_mem.mem[39] = 32'hFF442683;  // lw   x13, -12(x8)     # j
        dut.u_instr_mem.mem[40] = 32'hFED42823;  // sw   x13, -16(x8)     # min = j
        // .L4 [41]: j++
        dut.u_instr_mem.mem[41] = 32'hFF442683;  // lw   x13, -12(x8)
        dut.u_instr_mem.mem[42] = 32'h00168693;  // addi x13, x13, 1
        dut.u_instr_mem.mem[43] = 32'hFED42A23;  // sw   x13, -12(x8)
        // .L3 [44]: inner check j <= 7
        dut.u_instr_mem.mem[44] = 32'hFF442683;  // lw   x13, -12(x8)
        dut.u_instr_mem.mem[45] = 32'h00700F13;  // addi x30, x0, 7
        dut.u_instr_mem.mem[46] = 32'hFADF5CE3;  // bge  x30, x13, .L5    # if 7>=j goto [28]
        // swap: temp = arr[i]
        dut.u_instr_mem.mem[47] = 32'hFF842683;
        dut.u_instr_mem.mem[48] = 32'h00269693;
        dut.u_instr_mem.mem[49] = 32'hFFC68693;
        dut.u_instr_mem.mem[50] = 32'h008686B3;
        dut.u_instr_mem.mem[51] = 32'hFD06A683;  // lw   x13, -48(x13)    # arr[i]
        dut.u_instr_mem.mem[52] = 32'hFED42623;  // sw   x13, -20(x8)     # temp = arr[i]
        // arr[i] = arr[min]
        dut.u_instr_mem.mem[53] = 32'hFF042683;
        dut.u_instr_mem.mem[54] = 32'h00269693;
        dut.u_instr_mem.mem[55] = 32'hFFC68693;
        dut.u_instr_mem.mem[56] = 32'h008686B3;
        dut.u_instr_mem.mem[57] = 32'hFD06A603;  // lw   x12, -48(x13)    # arr[min]
        dut.u_instr_mem.mem[58] = 32'hFF842683;
        dut.u_instr_mem.mem[59] = 32'h00269693;
        dut.u_instr_mem.mem[60] = 32'hFFC68693;
        dut.u_instr_mem.mem[61] = 32'h008686B3;
        dut.u_instr_mem.mem[62] = 32'hFCC6A823;  // sw   x12, -48(x13)    # arr[i] = arr[min]
        // arr[min] = temp
        dut.u_instr_mem.mem[63] = 32'hFF042683;
        dut.u_instr_mem.mem[64] = 32'h00269693;
        dut.u_instr_mem.mem[65] = 32'hFFC68693;
        dut.u_instr_mem.mem[66] = 32'h008686B3;
        dut.u_instr_mem.mem[67] = 32'hFEC42603;  // lw   x12, -20(x8)     # temp
        dut.u_instr_mem.mem[68] = 32'hFCC6A823;  // sw   x12, -48(x13)    # arr[min] = temp
        // i++
        dut.u_instr_mem.mem[69] = 32'hFF842683;
        dut.u_instr_mem.mem[70] = 32'h00168693;
        dut.u_instr_mem.mem[71] = 32'hFED42C23;
        // .L2 [72]: outer check i <= 6
        dut.u_instr_mem.mem[72] = 32'hFF842683;
        dut.u_instr_mem.mem[73] = 32'h00600F13;  // addi x30, x0, 6
        dut.u_instr_mem.mem[74] = 32'hF2DF58E3;  // bge  x30, x13, .L6    # if 6>=i goto [22]
        // return 0
        dut.u_instr_mem.mem[75] = 32'h00000693;
        dut.u_instr_mem.mem[76] = 32'h00068513;
        // done + halt
        dut.u_instr_mem.mem[77] = 32'h00100F93;  // addi x31, x0, 1
        dut.u_instr_mem.mem[78] = 32'h0000006F;  // jal  x0, 0

        $display("");
        $display("============================================================");
        $display("  DEBUG: Selection Sort Pipeline Trace (Baremetal)");
        $display("============================================================");
        $display("  Array: {7, 3, 9, 1, 5, 2, 8, 4}");
        $display("  Expected: {1, 2, 3, 4, 5, 7, 8, 9}");
        $display("============================================================");

        @(posedge clk);
        @(posedge clk);

        sort_done = 0;
        begin : main_loop
            for (cycle_count = 1; cycle_count <= 60000; cycle_count = cycle_count + 1) begin
                @(posedge clk);

                prev_pc = dut.pc_current;

                // Monitor: outer loop entry at [22] .L6 (addr 0x058)
                if (dut.pc_current == 64'h0058) begin
                    $display("[Cycle %0d] --- Outer loop: i=%0d ---",
                        cycle_count, $signed(dut.u_regfile.regs[13]));
                    $write("  Array: { ");
                    for (i = 0; i < 8; i = i + 1) begin
                        if (i > 0) $write(", ");
                        if (i % 2 == 0)
                            $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][31:0]));
                        else
                            $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][63:32]));
                    end
                    $display(" }");
                end

                // Monitor: compare at [38] (addr 0x098)
                if (dut.pc_current == 64'h0098) begin
                    $display("[Cycle %0d] Compare: arr[j](x12)=%0d  arr[min](x13)=%0d",
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
            $display("\n  Selection sort completed at cycle %0d", cycle_count);
        else
            $display("\n  WARNING: Timeout at cycle %0d!", cycle_count);

        // Print sorted array
        $display("");
        $display("Sorted array:");
        $write("  { ");
        for (i = 0; i < 8; i = i + 1) begin
            if (i > 0) $write(", ");
            if (i % 2 == 0)
                $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][31:0]));
            else
                $write("%0d", $signed(dut.u_data_mem.mem[64 + i/2][63:32]));
        end
        $display(" }");
        $display("");
        $display("Expected:");
        $display("  { 1, 2, 3, 4, 5, 7, 8, 9 }");

        // Verification
        pass_count = 0;
        fail_count = 0;
        $display("");
        for (i = 0; i < 8; i = i + 1) begin
            if (i % 2 == 0)
                mem_val = $signed(dut.u_data_mem.mem[64 + i/2][31:0]);
            else
                mem_val = $signed(dut.u_data_mem.mem[64 + i/2][63:32]);
            case (i)
                0: exp_val = 1;  1: exp_val = 2;
                2: exp_val = 3;  3: exp_val = 4;
                4: exp_val = 5;  5: exp_val = 7;
                6: exp_val = 8;  7: exp_val = 9;
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