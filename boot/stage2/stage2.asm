bits 16

global stage2_start

extern print_newline
extern print_line
extern enable_a20
extern detect_memory
extern load_gdt
extern vga_init
extern vga_print_line

section .text

stage2_start:
    call print_newline

    mov si, msg_welcome
    call print_line

    call enable_a20
    jc .a20_error

    call detect_memory
    jc .memory_error

    ; Real-mode setup done — disable interrupts and enter protected mode
    cli
    call load_gdt

    mov eax, cr0
    or eax, 1              ; set PE (Protection Enable) bit
    mov cr0, eax

    jmp 0x08:pm32_start    ; far jump: flushes pipeline, loads CS = code selector

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
msg_a20_error:    db "A20 enable failed!", 0
msg_memory_error: db "Memory detection failed!", 0

; ─── 32-bit protected mode entry ─────────────────────────────────────────────

bits 32
section .text

pm32_start:
    ; Reload all data segment registers with the flat data selector (0x10).
    ; CS was already loaded by the far jump above with the code selector (0x08).
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9FC00        ; stack top just below the EBDA at 0xA0000

    cld                     ; ensure rep movsw/stosw scan forward

    call vga_init           ; clear screen, reset cursor

    mov esi, msg32_banner
    call vga_print_line

    mov esi, msg32_a20
    call vga_print_line

    mov esi, msg32_mem
    call vga_print_line

.hang:
    hlt
    jmp .hang

section .data

msg32_banner: db "aOS | 32-bit Protected Mode", 0
msg32_a20:    db "A20 line enabled.", 0
msg32_mem:    db "E820 memory map detected.", 0
