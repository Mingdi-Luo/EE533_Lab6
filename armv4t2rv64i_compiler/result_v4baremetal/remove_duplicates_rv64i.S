# ARM->RV64I (baremetal) from remove_duplicates.s
# Base: 0x0000, Data: 0x0200, Width: 64

    addi x19, x0, 512  # base = 0x200
    addi x11, x0, 1  # li x11, 1
    sw x11, 0(x19)  # arr[0] = 1
    addi x11, x0, 1  # li x11, 1
    sw x11, 4(x19)  # arr[1] = 1
    addi x11, x0, 2  # li x11, 2
    sw x11, 8(x19)  # arr[2] = 2
    addi x11, x0, 2  # li x11, 2
    sw x11, 12(x19)  # arr[3] = 2
    addi x11, x0, 3  # li x11, 3
    sw x11, 16(x19)  # arr[4] = 3
    addi x11, x0, 4  # li x11, 4
    sw x11, 20(x19)  # arr[5] = 4
    addi x11, x0, 4  # li x11, 4
    sw x11, 24(x19)  # arr[6] = 4
    addi x8, x0, 556  # li x8, 556
    addi x2, x8, -4  # sp = fp - 4
main:
    addi x13, x0, 7  # li x13, 7
    sw x13, -16(x8)  # str r3, [fp, #-16]
    lw x13, -16(x8)  # ldr r3, [fp, #-16]
    addi x30, x0, 0  # li x30, 0
    bne x13, x30, .L2  # bne
    addi x13, x0, 0  # li x13, 0
    jal x0, .L7  # b .L7
.L2:
    addi x13, x0, 1  # li x13, 1
    sw x13, -8(x8)  # str r3, [fp, #-8]
    addi x13, x0, 1  # li x13, 1
    sw x13, -12(x8)  # str r3, [fp, #-12]
    jal x0, .L4  # b .L4
.L6:
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x12, -40(x13)  # ldr r2, [r3, #-40]
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    addi x13, x13, -1  # sub r3, r3, #1
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x13, -40(x13)  # ldr r3, [r3, #-40]
    beq x12, x13, .L5  # beq
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x12, -40(x13)  # ldr r2, [r3, #-40]
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    sw x12, -40(x13)  # str r2, [r3, #-40]
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    addi x13, x13, 1  # add r3, r3, #1
    sw x13, -12(x8)  # str r3, [fp, #-12]
.L5:
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    addi x13, x13, 1  # add r3, r3, #1
    sw x13, -8(x8)  # str r3, [fp, #-8]
.L4:
    lw x12, -8(x8)  # ldr r2, [fp, #-8]
    lw x13, -16(x8)  # ldr r3, [fp, #-16]
    blt x12, x13, .L6  # blt
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
.L7:
    addi x10, x13, 0  # mov r0, r3
_done:
    addi x31, x0, 1  # done flag
_halt:
    jal x0, 0  # halt (infinite loop)