#============================================================================
# RV64I Bubble Sort Assembly
# Converted from ARM (arm7tdmi, armv4t) assembly
#
# Original C program: selection-sort style bubble sort on int array[10]
# Array: {323, 123, -455, 2, 98, 125, 10, 65, -56, 0}
# Expected sorted: {-455, -56, 0, 2, 10, 65, 98, 123, 125, 323}
#
# ARM -> RV64I conversion notes:
#   ARM push/pop     -> RV64I sd/ld with sp  (not needed, no function calls)
#   ARM add r, r, #i -> RV64I addi
#   ARM sub r, r, #i -> RV64I addi (negative immediate)
#   ARM mov r, #i    -> RV64I addi rd, x0, imm
#   ARM ldr r, [r,#] -> RV64I ld rd, imm(rs1)
#   ARM str r, [r,#] -> RV64I sd rs2, imm(rs1)
#   ARM lsl r, r, #i -> RV64I slli
#   ARM cmp + bge    -> RV64I bge (comparison built into branch)
#   ARM b label      -> RV64I jal x0, label
#   ARM ldmia/stmia  -> RV64I multiple ld/sd (expanded)
#
# Register allocation:
#   x9  (s1) = i         (outer loop counter, 0..N-1)
#   x18 (s2) = j         (inner loop counter, i+1..N-1)
#   x19 (s3) = 0x200     (base address of array in data memory)
#   x5  (t0) = temp      (address calculation scratch)
#   x6  (t1) = arr[i]    (loaded value)
#   x7  (t2) = arr[j]    (loaded value)
#   x28 (t3) = temp      (swap temporary)
#   x10 (a0) = 10        (array size N)
#   x31      = done flag  (1 when sort completes)
#
# Memory layout:
#   Instruction memory: 0x000 - 0x064 (26 instructions)
#   Data memory:        0x200 - 0x24F (10 × 8 bytes, 64-bit elements)
#============================================================================

    .text
    .globl main

main:
    # Initialize registers
    addi    x19, x0, 512        # s3 = 0x200 = array base address
    addi    x10, x0, 10         # a0 = N = 10 (array size)
    addi    x9,  x0, 0          # s1 = i = 0 (outer loop counter)

L_outer_check:
    # Outer loop: for (i = 0; i < N; i++)
    bge     x9, x10, end        # if i >= N, sorting is done

L_outer_body:
    addi    x18, x9, 1          # s2 = j = i + 1

L_inner_check:
    # Inner loop: for (j = i+1; j < N; j++)
    bge     x18, x10, L_inc_i   # if j >= N, go to next i

L_inner_body:
    # Load arr[i]
    slli    x5, x9, 3           # t0 = i * 8 (byte offset, 64-bit elements)
    add     x5, x5, x19         # t0 = &arr[i]
    ld      x6, 0(x5)           # t1 = arr[i]

    # Load arr[j]
    slli    x5, x18, 3          # t0 = j * 8
    add     x5, x5, x19         # t0 = &arr[j]
    ld      x7, 0(x5)           # t2 = arr[j]

    # Compare: if arr[j] >= arr[i], no swap needed
    bge     x7, x6, L_no_swap   # skip swap if arr[j] >= arr[i]

    # --- Swap arr[i] and arr[j] ---
    addi    x28, x7, 0          # t3 = arr[j] (save in temp)

    # arr[j] = arr[i]
    slli    x5, x18, 3          # t0 = j * 8
    add     x5, x5, x19         # t0 = &arr[j]
    sd      x6, 0(x5)           # arr[j] = arr[i] (t1)

    # arr[i] = temp (old arr[j])
    slli    x5, x9, 3           # t0 = i * 8
    add     x5, x5, x19         # t0 = &arr[i]
    sd      x28, 0(x5)          # arr[i] = temp (t3)

L_no_swap:
    addi    x18, x18, 1         # j++
    jal     x0, L_inner_check   # jump back to inner loop check

L_inc_i:
    addi    x9, x9, 1           # i++
    jal     x0, L_outer_check   # jump back to outer loop check

end:
    addi    x31, x0, 1          # set done flag = 1

halt:
    jal     x0, halt            # infinite loop (halt processor)
