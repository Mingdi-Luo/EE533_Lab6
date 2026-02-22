# Auto-generated RV64I assembly from sort_arm.s
# Base address: 0x0000

main:
    addi x2, x2, -8  # push: adjust sp
    sw x8, 0(x2)  # push fp
    sw x1, 4(x2)  # push lr
    addi x8, x2, 4  # add fp, sp, #4
    addi x2, x2, -56  # sub sp, sp, #56
    addi x13, x0, 0  # li x13, 0
    sw x13, -8(x8)  # str r3, [fp, #-8]
    jal x0, .L2  # b .L2
.L6:
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    addi x13, x13, 1  # add r3, r3, #1
    sw x13, -12(x8)  # str r3, [fp, #-12]
    jal x0, .L3  # b .L3
.L5:
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    slli x13, x13, 2  # lsl r3, r3, #2
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x12, -52(x13)  # ldr r2, [r3, #-52]
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    slli x13, x13, 2  # lsl r3, r3, #2
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x13, -52(x13)  # ldr r3, [r3, #-52]
    bge x12, x13, .L4  # bge
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    slli x13, x13, 2  # lsl r3, r3, #2
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x13, -52(x13)  # ldr r3, [r3, #-52]
    sw x13, -16(x8)  # str r3, [fp, #-16]
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    slli x13, x13, 2  # lsl r3, r3, #2
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x12, -52(x13)  # ldr r2, [r3, #-52]
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    slli x13, x13, 2  # lsl r3, r3, #2
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    sw x12, -52(x13)  # str r2, [r3, #-52]
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    slli x13, x13, 2  # lsl r3, r3, #2
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x12, -16(x8)  # ldr r2, [fp, #-16]
    sw x12, -52(x13)  # str r2, [r3, #-52]
.L4:
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    addi x13, x13, 1  # add r3, r3, #1
    sw x13, -12(x8)  # str r3, [fp, #-12]
.L3:
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    addi x30, x0, 9  # li x30, 9
    bge x30, x13, .L5  # ble→bge
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    addi x13, x13, 1  # add r3, r3, #1
    sw x13, -8(x8)  # str r3, [fp, #-8]
.L2:
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    addi x30, x0, 9  # li x30, 9
    bge x30, x13, .L6  # ble→bge
    addi x13, x0, 0  # li x13, 0
    addi x10, x13, 0  # mov r0, r3
    addi x2, x8, -4  # sub sp, fp, #4
    lw x8, 0(x2)  # pop fp
    lw x1, 4(x2)  # pop lr
    addi x2, x2, 8  # pop: adjust sp
    jalr x0, x1, 0  # bx lr