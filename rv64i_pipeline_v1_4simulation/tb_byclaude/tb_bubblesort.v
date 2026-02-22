`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   23:25:45 02/19/2026
// Design Name:   rv64i_pipeline_top
// Module Name:   C:/Documents and Settings/student/Desktop/lab6/tb_bubblesort.v
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
// Testbench: Bubble Sort on RV64I 5-Stage Pipeline
// Target: Xilinx ISE (ISim)
//
// Converted from ARM assembly (arm7tdmi, armv4t)
// Array initialized by program (ldmia/stmia translation)
//
// Array: {323, 123, -455, 2, 98, 125, 10, 65, -56, 0}
// Expected sorted: {-455, -56, 0, 2, 10, 65, 98, 123, 125, 323}
//============================================================================

module tb_bubblesort;

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
    
    // Debug: track previous PC to detect key instruction executions
    reg [63:0] prev_pc;
    reg [63:0] prev_prev_pc;

    initial begin
        rst_n      = 0;
        sort_done  = 0;
        cycle_count = 0;
        pass_count = 0;
        fail_count = 0;
        mem_val    = 0;
        exp_val    = 0;
        i          = 0;
        prev_pc    = 0;
        prev_prev_pc = 0;

        #25;
        rst_n = 1;

        // Load program
        // PART 1: Array init
        dut.u_instr_mem.mem[ 0] = 32'h20000993;
        dut.u_instr_mem.mem[ 1] = 32'h14300593;
        dut.u_instr_mem.mem[ 2] = 32'h00B9B023;
        dut.u_instr_mem.mem[ 3] = 32'h07B00593;
        dut.u_instr_mem.mem[ 4] = 32'h00B9B423;
        dut.u_instr_mem.mem[ 5] = 32'hE3900593;
        dut.u_instr_mem.mem[ 6] = 32'h00B9B823;
        dut.u_instr_mem.mem[ 7] = 32'h00200593;
        dut.u_instr_mem.mem[ 8] = 32'h00B9BC23;
        dut.u_instr_mem.mem[ 9] = 32'h06200593;
        dut.u_instr_mem.mem[10] = 32'h02B9B023;
        dut.u_instr_mem.mem[11] = 32'h07D00593;
        dut.u_instr_mem.mem[12] = 32'h02B9B423;
        dut.u_instr_mem.mem[13] = 32'h00A00593;
        dut.u_instr_mem.mem[14] = 32'h02B9B823;
        dut.u_instr_mem.mem[15] = 32'h04100593;
        dut.u_instr_mem.mem[16] = 32'h02B9BC23;
        dut.u_instr_mem.mem[17] = 32'hFC800593;
        dut.u_instr_mem.mem[18] = 32'h04B9B023;
        dut.u_instr_mem.mem[19] = 32'h00000593;
        dut.u_instr_mem.mem[20] = 32'h04B9B423;
        // PART 2: Sort
        dut.u_instr_mem.mem[21] = 32'h00A00513;
        dut.u_instr_mem.mem[22] = 32'h00000493;
        dut.u_instr_mem.mem[23] = 32'h04A4DA63;
        dut.u_instr_mem.mem[24] = 32'h00148913;
        dut.u_instr_mem.mem[25] = 32'h04A95263;
        dut.u_instr_mem.mem[26] = 32'h00349293;
        dut.u_instr_mem.mem[27] = 32'h013282B3;
        dut.u_instr_mem.mem[28] = 32'h0002B303;
        dut.u_instr_mem.mem[29] = 32'h00391293;
        dut.u_instr_mem.mem[30] = 32'h013282B3;
        dut.u_instr_mem.mem[31] = 32'h0002B383;
        dut.u_instr_mem.mem[32] = 32'h0263D063;
        dut.u_instr_mem.mem[33] = 32'h00038E13;
        dut.u_instr_mem.mem[34] = 32'h00391293;
        dut.u_instr_mem.mem[35] = 32'h013282B3;
        dut.u_instr_mem.mem[36] = 32'h0062B023;
        dut.u_instr_mem.mem[37] = 32'h00349293;
        dut.u_instr_mem.mem[38] = 32'h013282B3;
        dut.u_instr_mem.mem[39] = 32'h01C2B023;
        dut.u_instr_mem.mem[40] = 32'h00190913;
        dut.u_instr_mem.mem[41] = 32'hFC1FF06F;
        dut.u_instr_mem.mem[42] = 32'h00148493;
        dut.u_instr_mem.mem[43] = 32'hFB1FF06F;
        dut.u_instr_mem.mem[44] = 32'h00100F93;
        dut.u_instr_mem.mem[45] = 32'h0000006F;

        $display("");
        $display("============================================================");
        $display("  DEBUG: Bubble Sort Pipeline Trace");
        $display("============================================================");

        @(posedge clk);
        @(posedge clk);

        // Run with debug monitoring
        sort_done = 0;
        for (cycle_count = 1; cycle_count <= 6000; cycle_count = cycle_count + 1) begin
            @(posedge clk);
            
            prev_prev_pc = prev_pc;
            prev_pc = dut.pc_current;

            // Monitor: when BGE at [32] (addr 0x080) is about to resolve
            // It reaches EX/MEM ~3 cycles after fetch
            // We can detect it by watching when PC was at 0x080 a few cycles ago
            
            // Monitor key register values when PC is at instruction [32] (0x080)
            // The comparison happens in EX stage, so we watch when [32] is in EX
            // [32] in IF when PC=0x080
            // [32] in EX about 2-3 cycles later (with possible stall)
            
            // Simpler: monitor x6 and x7 whenever a store happens
            // Or: just print state at each inner loop entry
            
            // Detect: PC at [28] ld x6 = 0x070
            if (dut.pc_current == 64'h0070) begin
                // [28] is being fetched. x6 will be loaded ~3-4 cycles later.
                // For now, print current register state
            end
            
            // Detect: when [32] bge is being fetched (PC = 0x080)
            if (dut.pc_current == 64'h0080) begin
                $display("[Cycle %0d] Fetch BGE[32]: i=%0d j=%0d x6(arr_i)=%0d x7(arr_j)=%0d",
                    cycle_count,
                    $signed(dut.u_regfile.regs[9]),
                    $signed(dut.u_regfile.regs[18]),
                    $signed(dut.u_regfile.regs[6]),
                    $signed(dut.u_regfile.regs[7]));
            end
            
            // Detect: when swap SD [36] at addr 0x090 is fetched
            if (dut.pc_current == 64'h0090) begin
                $display("[Cycle %0d] Fetch SD[36] arr[j]=arr[i]: x5(addr)=0x%h x6(data)=%0d",
                    cycle_count,
                    dut.u_regfile.regs[5],
                    $signed(dut.u_regfile.regs[6]));
            end
            
            // Detect: when swap SD [39] at addr 0x09C is fetched  
            if (dut.pc_current == 64'h009C) begin
                $display("[Cycle %0d] Fetch SD[39] arr[i]=temp: x5(addr)=0x%h x28(data)=%0d",
                    cycle_count,
                    dut.u_regfile.regs[5],
                    $signed(dut.u_regfile.regs[28]));
            end

            // Detect: when outer loop iterates (PC at [24] addi x18=i+1, addr 0x060)
            if (dut.pc_current == 64'h0060) begin
                $display("[Cycle %0d] --- Outer loop: i=%0d ---",
                    cycle_count, $signed(dut.u_regfile.regs[9]));
                // Print array state
                $write("  Array: { ");
                for (i = 0; i < 10; i = i + 1) begin
                    if (i > 0) $write(", ");
                    $write("%0d", $signed(dut.u_data_mem.mem[64 + i]));
                end
                $display(" }");
            end

            if (dut.u_regfile.regs[31] === 64'd1) begin
                sort_done = 1;
                disable main_loop;
            end
        end
        begin : main_loop
        end

        if (sort_done)
            $display("  Sort completed at cycle %0d", cycle_count);
        else
            $display("  WARNING: Timeout!");

        // Print sorted array
        $display("");
        $display("Sorted array:");
        $write("  { ");
        for (i = 0; i < 10; i = i + 1) begin
            if (i > 0) $write(", ");
            $write("%0d", $signed(dut.u_data_mem.mem[64 + i]));
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
            mem_val = dut.u_data_mem.mem[64 + i];
            case (i)
                0: exp_val = -455;  1: exp_val = -56;
                2: exp_val = 0;     3: exp_val = 2;
                4: exp_val = 10;    5: exp_val = 65;
                6: exp_val = 98;    7: exp_val = 123;
                8: exp_val = 125;   9: exp_val = 323;
                default: exp_val = 0;
            endcase
            if (mem_val == exp_val) begin
                $display("  arr[%0d] = %0d  PASS", i, mem_val);
                pass_count = pass_count + 1;
            end else begin
                $display("  arr[%0d] = %0d (expect %0d) FAIL", i, mem_val, exp_val);
                fail_count = fail_count + 1;
            end
        end

        $display("");
        if (fail_count == 0) $display("  ALL %0d PASSED!", pass_count);
        else $display("  %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("  Cycles: %0d", cycle_count);

        #100;
        $finish;
    end

endmodule