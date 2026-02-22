# ARM -> RV64I (baremetal mode) from fibonacci.s
# Base: 0x0000, Data: 0x0200

init:
    addi x19, x0, 512  # base addr = 0x200
    addi x11, x0, 323  # li x11, 323
    sd x11, 0(x19)  # arr[0] = 323
    addi x11, x0, 123  # li x11, 123
    sd x11, 8(x19)  # arr[1] = 123
    addi x11, x0, -455  # li x11, -455
    sd x11, 16(x19)  # arr[2] = -455
    addi x11, x0, 2  # li x11, 2
    sd x11, 24(x19)  # arr[3] = 2
    addi x11, x0, 98  # li x11, 98
    sd x11, 32(x19)  # arr[4] = 98
    addi x11, x0, 125  # li x11, 125
    sd x11, 40(x19)  # arr[5] = 125
    addi x11, x0, 10  # li x11, 10
    sd x11, 48(x19)  # arr[6] = 10
    addi x11, x0, 65  # li x11, 65
    sd x11, 56(x19)  # arr[7] = 65
    addi x11, x0, -56  # li x11, -56
    sd x11, 64(x19)  # arr[8] = -56
    addi x11, x0, 0  # li x11, 0
    sd x11, 72(x19)  # arr[9] = 0
    addi x10, x0, 10  # N = 10
    addi x9, x0, 0  # i = 0
outer_check:
    bge x9, x10, end  # if i>=N goto end
    addi x18, x9, 1  # j = i+1
inner_check:
    bge x18, x10, inc_i  # if j>=N goto inc_i
    slli x5, x9, 3  # i*wordsize
    add x5, x5, x19  # &arr[i]
    ld x6, 0(x5)  # arr[i]
    slli x5, x18, 3  # j*wordsize
    add x5, x5, x19  # &arr[j]
    ld x7, 0(x5)  # arr[j]
    bge x7, x6, no_swap  # if arr[j]>=arr[i] skip
    addi x28, x7, 0  # temp = arr[j]
    slli x5, x18, 3  # j*wordsize
    add x5, x5, x19  # &arr[j]
    sd x6, 0(x5)  # arr[j]=arr[i]
    slli x5, x9, 3  # i*wordsize
    add x5, x5, x19  # &arr[i]
    sd x28, 0(x5)  # arr[i]=temp
no_swap:
    addi x18, x18, 1  # j++
    jal x0, inner_check  # goto inner_check
inc_i:
    addi x9, x9, 1  # i++
    jal x0, outer_check  # goto outer_check
end:
    addi x31, x0, 1  # done flag
halt:
    jal x0, halt  # halt (infinite loop)