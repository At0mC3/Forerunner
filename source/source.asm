format MS64 COFF

; RSI = VCODE POINTER
; RBP = Bottom of the stack
; edi = Virtual instruction holder

macro StoreRegisters {
    store_register_beg:
    pushfq ; Push the flags

    pop qword [rax]
    mov qword [rax-8], rbx
    mov qword [rax-16], rcx
    mov qword [rax-24], rdx
    mov qword [rax-32], rsp
    add qword [rax-32], 0x18; Fix the rsp register once it's in the virtual stack
    mov qword [rax-40], rbp
    mov qword [rax-48], rsi
    mov qword [rax-56], rdi
    mov qword [rax-64], r8
    mov qword [rax-72], r9
    mov qword [rax-80], r10
    mov qword [rax-88], r11
    mov qword [rax-96], r12
    mov qword [rax-104], r13
    mov qword [rax-112], r14
    mov qword [rax-120], r15
    
    ; Restore the original RAX
    pop qword [rax-128]

    store_register_end:
}

macro MountRegisters {
    ; Restore the original RAX
    mov rax, qword [rax-128]
    mov r15, qword [rbp - 120]
    mov r14, qword [rbp - 112]
    mov r13, qword [rbp - 104]
    mov r12, qword [rbp - 96]
    mov r11, qword [rbp - 88]
    mov r10, qword [rbp - 80]
    mov r9, qword [rbp - 72]
    mov r8, qword [rbp - 64]
    mov rdi, qword [rbp - 56]
    mov rsi, qword [rbp - 48]
    mov rdx, qword [rbp - 24]
    mov rcx, qword [rbp - 16]
    mov rbx, qword [rbp - 8]

    mov rsp, rbp
    popfq ; Restore the flag registers

    mov rsp, qword [rbp - 32] ; Restore the rsp

    push qword [rbp - 136] ; Push the ret address to return

    mov rbp, qword [rbp - 40] ; RBP LAST
}

; Store the return address
macro StoreRetAddres {
    pop qword [rax-136]
}

; Store the offset to the virtual code in the stack
macro StoreVCodeOffset {
    pop qword [rax-144]
}

macro StoreVirtualStack {
    mov qword [rax-160], rax ; Store the current stack pointer
    add qword [rax-160], 0x190 ; Add this amount to allocate some virtual stack space
}

macro InitVCodePtr {
    ; Setup the vcode pointer
    ; Get the delta offset
    call delta
    delta:
    pop rsi
    sub rsi, delta - start
    mov qword [rbp - 152], rsi ; Store the delta in the stack
    ; Add the vcode offset to the delta
    add rsi, qword [rbp - 144]
}

macro DecodeInstruction {
    mov edi, dword [rsi] ; The instruction is now in edi

    xor r8, r8 ; Clear the register before using
    mov r8w, di ; Move the first 
    imul r8, 0x08 ; Multiply it by 8 to adjust it to the jump table
}

macro VPush value {
    push rcx ; Save this register
    mov rcx, qword [rbp-160] ; Get the virtual stack pointer
    sub rcx, 0x08 ; Remove 8 bytes to allocate a new space for this value
    mov qword [rcx], value ; Move the value in the stack

    mov qword [rbp-160], rcx ; Save the virtual stack pointer
    pop rcx ; Resume the original state of this register
}

macro VPop target {
    push rcx ; Save this register
    mov rcx, qword [rbp-160] ; Get the virtual stack pointer

    mov target, qword [rcx] ; Move the value in the target
    add rcx, 0x08 ; Make the stack up for the next spot

    mov qword [rbp-160], rcx ; Save the virtual stack pointer
    pop rcx ; Resume the original state of this register
}

; At the entry, we need to fix the stack to account for the artificial push and call we did
section '.text' code readable executable
    start:
    push rax ; Save rax for now, we need to get a saving spot
    mov rax, [GS:0x10] ; Get the lowest address of the currently allocated stack
    add rax, 0x400 ; Allocate 80 slots

    StoreRegisters
    StoreRetAddres
    StoreVCodeOffset
    StoreVirtualStack

    ; Setup the environment for the virtual machine
    mov rsp, rax ; Set the stack
    sub rsp, 168 ; It's now pointing to a free space in the stack space
    mov rbp, rax ; RBP is holding the top of the stack

    InitVCodePtr

MachineLoopStart:
    DecodeInstruction

    add r8, jump_table - start ; Add the offset of the jump table to the index of the command
    add r8, qword [rbp - 152]  ; Add the delta offset to get the absolute address
    mov r8, qword [r8] ; Move the address of the virtual function in the register

    add r8, qword [rbp - 152]  ; Add the delta offset to get the absolute address
    call r8
    jmp MachineLoopStart

    jump_table:
        dq LdrFunction - start, 0
        dq LdImmFunction - start, kVAdd - start
        dq kVSub - start, 0
        dq kVSvr - start, kVSvm - start
        dq 0, kVmExit - start

    LdrFunction:
        shr edi, 16 ; Shift 16 bits to the right to clear out the command bytes
        mov r9, rbp
        sub r9, rdi ; r9 is holding the ptr to the register in the stack
        ; EDI is now holding the command which should be the register index from the top of the stack
        mov r9, qword [r9]
        VPush r9
        
        add rsi, 4 ; Add four to go to the next instruction
        ret

    LdImmFunction:
        add rsi, 4 ; Add four bytes to skip to the Immediate
        ; Immediates are 8 bytes in this machine
        mov rdi, qword [ rsi ] ; Move the 8 bytes into rdi
        VPush rdi ; Push the value to the virtual stack

        add rsi, 8 ; Add height bytes to jump over the immediate
        ret

    kVAdd:
        VPop r9 ; The value that will be substracted on the next pop
        VPop r10 ; The value which will get substracted
        add r10, r9 ; Do the operation
        VPush r10 ; Push back the value to the stack

        add rsi, 4 ; Add four to go to the next instruction
        ret

    kVSub:
        VPop r9 ; The value that will be substracted on the next pop
        VPop r10 ; The value which will get substracted
        sub r10, r9 ; Do the operation
        VPush r10 ; Push back the value to the stack

        add rsi, 4 ; Add four to go to the next instruction
        ret

    kVSvr:
        shr edi, 16 ; Shift 16 bits to the right to clear out the command bytes
        mov r9, rbp ; Move the top of the stack in r9
        sub r9, rdi ; r9 is holding the ptr to the register in the stack

        VPop r10 ; The virtual stack value is now in r10
        mov qword [r9], r10 ; Move the value in the store register array

        add rsi, 4 ; Add four to go to the next instruction\
        ret

    kVSvm:
        VPop r9 ; This is holding the target memory
        VPop r10 ; This is holding the value

        mov qword [r9], r10

        add rsi, 4 ; Add four to go to the next instruction
        ret

    kVmExit:
        MountRegisters
        ret