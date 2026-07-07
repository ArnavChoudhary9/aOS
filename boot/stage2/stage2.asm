bits 16

global stage2_start

extern print_newline
extern print_line
extern enable_a20
extern detect_memory
extern print_memory_map

section .text

stage2_start:
    call print_newline

    mov si, msg_welcome
    call print_line

    call enable_a20
    jc .a20_error

    mov si, msg_a20_ok
    call print_line

    call detect_memory
    jc .memory_error

    mov si, msg_memory_ok
    call print_line

    ; call print_memory_map

    jmp hang

.a20_error:
    mov si, msg_a20_error
    call print_line
    jmp hang

.memory_error:
    mov si, msg_memory_error
    call print_line

hang:
    hlt
    jmp hang

section .data

msg_welcome:      db "aOS Stage 2", 0
msg_a20_ok:       db "A20 enabled.", 0
msg_a20_error:    db "A20 enable failed!", 0
msg_memory_ok:    db "Memory map detected.", 0
msg_memory_error: db "Memory detection failed!", 0
