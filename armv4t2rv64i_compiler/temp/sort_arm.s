	.cpu arm7tdmi
	.arch armv4t
	.text
	.align 2
	.global main
	.arm
main:
	push {fp, lr}
	add fp, sp, #4
	sub sp, sp, #56
	mov r3, #0
	str r3, [fp, #-8]
	b .L2
.L6:
	ldr r3, [fp, #-8]
	add r3, r3, #1
	str r3, [fp, #-12]
	b .L3
.L5:
	ldr r3, [fp, #-12]
	lsl r3, r3, #2
	sub r3, r3, #4
	add r3, r3, fp
	ldr r2, [r3, #-52]
	ldr r3, [fp, #-8]
	lsl r3, r3, #2
	sub r3, r3, #4
	add r3, r3, fp
	ldr r3, [r3, #-52]
	cmp r2, r3
	bge .L4
	ldr r3, [fp, #-12]
	lsl r3, r3, #2
	sub r3, r3, #4
	add r3, r3, fp
	ldr r3, [r3, #-52]
	str r3, [fp, #-16]
	ldr r3, [fp, #-8]
	lsl r3, r3, #2
	sub r3, r3, #4
	add r3, r3, fp
	ldr r2, [r3, #-52]
	ldr r3, [fp, #-12]
	lsl r3, r3, #2
	sub r3, r3, #4
	add r3, r3, fp
	str r2, [r3, #-52]
	ldr r3, [fp, #-8]
	lsl r3, r3, #2
	sub r3, r3, #4
	add r3, r3, fp
	ldr r2, [fp, #-16]
	str r2, [r3, #-52]
.L4:
	ldr r3, [fp, #-12]
	add r3, r3, #1
	str r3, [fp, #-12]
.L3:
	ldr r3, [fp, #-12]
	cmp r3, #9
	ble .L5
	ldr r3, [fp, #-8]
	add r3, r3, #1
	str r3, [fp, #-8]
.L2:
	ldr r3, [fp, #-8]
	cmp r3, #9
	ble .L6
	mov r3, #0
	mov r0, r3
	sub sp, fp, #4
	pop {fp, lr}
	bx lr
