# ARM->RV64I (baremetal) from bubblesort.s
# Base: 0x0000, Data: 0x0200, Width: 64

    addi x19, x0, 512  # base = 0x200
    addi x11, x0, 323  # li x11, 323
    sw x11, 0(x19)  # arr[0] = 323
    addi x11, x0, 123  # li x11, 123
    sw x11, 4(x19)  # arr[1] = 123
    addi x11, x0, -455  # li x11, -455
    sw x11, 8(x19)  # arr[2] = -455
    addi x11, x0, 2  # li x11, 2
    sw x11, 12(x19)  # arr[3] = 2
    addi x11, x0, 98  # li x11, 98
    sw x11, 16(x19)  # arr[4] = 98
    addi x11, x0, 125  # li x11, 125
    sw x11, 20(x19)  # arr[5] = 125
    addi x11, x0, 10  # li x11, 10
    sw x11, 24(x19)  # arr[6] = 10
    addi x11, x0, 65  # li x11, 65
    sw x11, 28(x19)  # arr[7] = 65
    addi x11, x0, -56  # li x11, -56
    sw x11, 32(x19)  # arr[8] = -56
    addi x11, x0, 0  # li x11, 0
    sw x11, 36(x19)  # arr[9] = 0
    addi x8, x0, 568  # li x8, 568
    addi x2, x8, -4  # sp = fp - 4
main:
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
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x12, -52(x13)  # ldr r2, [r3, #-52]
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x13, -52(x13)  # ldr r3, [r3, #-52]
    bge x12, x13, .L4  # bge
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x13, -52(x13)  # ldr r3, [r3, #-52]
    sw x13, -16(x8)  # str r3, [fp, #-16]
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    lw x12, -52(x13)  # ldr r2, [r3, #-52]
    lw x13, -12(x8)  # ldr r3, [fp, #-12]
    slli x13, x13, 2  # lsl
    addi x13, x13, -4  # sub r3, r3, #4
    add x13, x13, x8  # add r3, r3, fp
    sw x12, -52(x13)  # str r2, [r3, #-52]
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    slli x13, x13, 2  # lsl
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
    ble x30, x13, .L5  # ble->bge
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    addi x13, x13, 1  # add r3, r3, #1
    sw x13, -8(x8)  # str r3, [fp, #-8]
.L2:
    lw x13, -8(x8)  # ldr r3, [fp, #-8]
    addi x30, x0, 9  # li x30, 9
    ble x30, x13, .L6  # ble->bge
    addi x13, x0, 0  # li x13, 0
    addi x10, x13, 0  # mov r0, r3
_done:
    addi x31, x0, 1  # done flag
_halt:
    jal x0, 0  # halt (infinite loop)