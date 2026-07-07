bits 16

global stage2_start

extern print_newline
extern print_info
extern print_ok
extern print_err
extern enable_a20
extern detect_memory
extern load_gdt
extern vga_init
extern load_idt
extern dbg_ok
extern dbg_err
extern dbg_info

section .text

stage2_start:
    call print_newline

    mov si, msg_welcome
    call print_info

    call enable_a20
    jc .a20_error

    call detect_memory
    jc .memory_error

    ; Real-mode setup done — disable interrupts and enter protected mode
    cli
    call load_gdt

    mov eax, cr0
    or eax, 1              ; set PE (Protection Enable)
    mov cr0, eax

    jmp 0x08:pm32_start    ; far jump: flush pipeline, load CS = code selector (0x08)

.a20_error:
    mov si, msg_a20_error
    call print_err
    jmp hang

.memory_error:
    mov si, msg_memory_error
    call print_err

hang:
    hlt
    jmp hang

section .data

msg_welcome:      db "aOS Stage 2", 0
msg_a20_error:    db "A20 enable failed", 0
msg_memory_error: db "Memory detection failed", 0

; ─── 32-bit protected mode entry ─────────────────────────────────────────────

bits 32
section .text

pm32_start:
    ; Reload data segment registers with the flat data selector (0x10).
    ; CS was already loaded by the far jump with the code selector (0x08).
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9FC00        ; stack top just below the EBDA at 0xA0000

    cld                     ; string ops scan forward

    call vga_init           ; clear screen, reset cursor and color

    ; Load IDT for exceptions 0-31 before enabling any further work.
    ; sti is intentionally absent — the PIC is still in its BIOS default
    ; mapping (IRQ0 → INT8 = #DF) and must be remapped before hardware
    ; interrupts are unmasked.
    call load_idt

    mov esi, msg32_banner
    call dbg_info

    mov esi, msg32_a20
    call dbg_ok

    mov esi, msg32_mem
    call dbg_ok

    mov esi, msg32_idt
    call dbg_ok

.hang:
    hlt
    jmp .hang

section .data

msg32_banner: db "aOS | 32-bit Protected Mode", 0
msg32_a20:    db "A20 line enabled", 0
msg32_mem:    db "E820 memory map detected", 0
msg32_idt:    db "IDT loaded (exceptions 0-31)", 0
