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
extern vga_putchar
extern vga_print_string
extern vga_newline
extern pic_init
extern pic_set_mask
extern load_idt
extern timer_init
extern kbd_init
extern kbd_getchar
extern ata_read_sectors
extern dbg_ok
extern dbg_err
extern dbg_info
extern dbg_hex8

section .text

stage2_start:
    call print_newline

    mov si, msg_welcome
    call print_info

    call enable_a20
    jc .a20_error

    call detect_memory
    jc .memory_error

    cli
    call load_gdt

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    jmp 0x08:pm32_start

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
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9FC00

    cld

    call vga_init

    ; ── Interrupt infrastructure ──────────────────────────────────────────────
    mov al, 0x20
    mov ah, 0x28
    call pic_init               ; remap PIC: IRQ0-7 → 32-39, IRQ8-15 → 40-47

    call load_idt               ; install exception stubs (0-31) + IRQ stubs (32-47)

    call timer_init             ; program PIT → 100 Hz, install IRQ0 handler
    call kbd_init               ; install IRQ1 handler

    mov al, 0x00
    mov ah, 0x00
    call pic_set_mask           ; unmask all IRQs
    sti                         ; enable CPU interrupt delivery

    ; ── Boot status ───────────────────────────────────────────────────────────
    mov esi, msg32_banner
    call dbg_info

    mov esi, msg32_a20
    call dbg_ok

    mov esi, msg32_mem
    call dbg_ok

    mov esi, msg32_idt
    call dbg_ok

    mov esi, msg32_pic
    call dbg_ok

    mov esi, msg32_timer
    call dbg_ok

    mov esi, msg32_kbd
    call dbg_ok

    ; ── ATA demo: read sector 0 and verify the boot signature ─────────────────
    mov eax, 0                  ; LBA 0 = first sector (boot sector)
    mov ecx, 1                  ; 1 sector
    mov edi, 0x20000            ; scratch buffer at 128 KB (safe, unused RAM)
    call ata_read_sectors
    jc .ata_err

    cmp word [0x20000 + 510], 0xAA55
    jne .ata_bad_sig

    mov esi, msg32_ata_ok
    call dbg_ok
    jmp .kbd_demo

.ata_err:
    mov esi, msg32_ata_err
    call dbg_err
    jmp .kbd_demo

.ata_bad_sig:
    mov esi, msg32_ata_sig
    call dbg_err

    ; ── Keyboard echo loop ────────────────────────────────────────────────────
    ; After setup, drop into a simple interactive prompt.
    ; The timer handler keeps the tick counter live in the top-right corner.
.kbd_demo:
    mov esi, msg32_prompt
    call dbg_info

.hang:
    hlt                         ; sleep until the next interrupt fires

    call kbd_getchar            ; any key in the buffer?
    test al, al
    jz .hang                    ; no — sleep again

    call vga_putchar            ; echo the character (backspace handled in vga_putchar)
    jmp .hang


section .data

msg32_banner:  db "aOS | 32-bit Protected Mode", 0
msg32_a20:     db "A20 line enabled", 0
msg32_mem:     db "E820 memory map detected", 0
msg32_idt:     db "IDT loaded (vectors 0-47)", 0
msg32_pic:     db "PIC remapped (IRQ0-7=0x20, IRQ8-15=0x28)", 0
msg32_timer:   db "Timer @ 100 Hz (tick counter top-right)", 0
msg32_kbd:     db "Keyboard driver ready", 0
msg32_ata_ok:  db "ATA: boot signature 0xAA55 verified", 0
msg32_ata_err: db "ATA: read failed (check QEMU -if=ide)", 0
msg32_ata_sig: db "ATA: boot signature not found", 0
msg32_prompt:  db "Ready - type something (Backspace supported):", 0
