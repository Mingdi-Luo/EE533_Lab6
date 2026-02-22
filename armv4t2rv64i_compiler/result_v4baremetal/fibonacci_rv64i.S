# ARM->RV64I (baremetal) from fibonacci.s
# Base: 0x0000, Data: 0x0200, Width: 64

    addi x19, x0, 512  # base = 0x200
    addi x8, x0, 540  # li x8, 540
    addi x2, x8, 0  # sp = fp
main:
    sw x8, -4(x2)  # str fp, [sp, #-4]!
    addi x2, x2, -4  # writeback
    addi x13, x0, 10  # li x13, 10
    sw x13, -20(x8)  # str r3, [fp, #-20]
    addi x13, x0, 0  # li x13, 0
    sw x13, -8(x8)  # str r3, [fp, #-8]
    addi x13, x0, 1  # li x13, 1
    sw x13, -12(x8)  # str r3, [fp, #-12]
    addi x13, x0, 2  # li x13, 2
    sw x13, -16(x8)  # str r3, [fp, #-16]
    jal x0, .L2  # b .L2
.L3:
    lw x12, -8(x8)  # ldr r2, [fp, #-8]
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    add x13, x12, x13  # add r3, r2, r3
    sw x13, -24(x8)  # str r3, [fp, #-24]
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    sw x13, -8(x8)  # str r3, [fp, #-8]
    lw x13, -24(x8)  # ldr r3, [fp, #-24]
    sw x13, -12(x8)  # str r3, [fp, #-12]
    lw x13, -16(x8)  # ldr r3, [fp, #-16]
    addi x13, x13, 1  # add r3, r3, #1
    sw x13, -16(x8)  # str r3, [fp, #-16]
.L2:
    lw x12, -16(x8)  # ldr r2, [fp, #-16]
    lw x13, -20(x8)  # ldr r3, [fp, #-20]
    blt x12, x13, .L3  # blt
    addi x13, x0, 0  # li x13, 0
    addi x10, x13, 0  # mov r0, r3
    addi x2, x8, 0  # add sp, fp, #0
    lw x8, 0(x2)  # ldr fp, [sp]
_done:
    addi x31, x0, 1  # done flag
_halt:
    jal x0, 0  # halt (infinite loop)