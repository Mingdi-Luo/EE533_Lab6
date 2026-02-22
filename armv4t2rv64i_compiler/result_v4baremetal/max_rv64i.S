# ARM->RV64I (baremetal) from max.s
# Base: 0x0000, Data: 0x0200, Width: 64

    addi x19, x0, 512  # base = 0x200
    addi x11, x0, 3  # li x11, 3
    sw x11, 0(x19)  # arr[0] = 3
    addi x11, x0, 9  # li x11, 9
    sw x11, 4(x19)  # arr[1] = 9
    addi x11, x0, 1  # li x11, 1
    sw x11, 8(x19)  # arr[2] = 1
    addi x11, x0, 6  # li x11, 6
    sw x11, 12(x19)  # arr[3] = 6
    addi x11, x0, 2  # li x11, 2
    sw x11, 16(x19)  # arr[4] = 2
    addi x11, x0, 8  # li x11, 8
    sw x11, 20(x19)  # arr[5] = 8
    addi x8, x0, 548  # li x8, 548
    addi x2, x8, -4  # sp = fp - 4
main:
    lw x13, -36(x8)  # ldr r3, [fp, #-36]
    sw x13, -8(x8)  # str r3, [fp, #-8]
    addi x13, x0, 1  # li x13, 1
    sw x13, -12(x8)  # str r3, [fp, #-12]
    jal x0, .L2  # b .L2
.L4:
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x13, -32(x13)  # ldr r3, [r3, #-32]
    lw x12, -8(x8)  # ldr r2, [fp, #-8]
    bge x12, x13, .L3  # bge
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x13, -32(x13)  # ldr r3, [r3, #-32]
    sw x13, -8(x8)  # str r3, [fp, #-8]
.L3:
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    addi x13, x13, 1  # add r3, r3, #1
    sw x13, -12(x8)  # str r3, [fp, #-12]
.L2:
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    addi x30, x0, 5  # li x30, 5
    ble x30, x13, .L4  # ble->bge
    addi x13, x0, 0  # li x13, 0
    addi x10, x13, 0  # mov r0, r3
_done:
    addi x31, x0, 1  # done flag
_halt:
    jal x0, 0  # halt (infinite loop)