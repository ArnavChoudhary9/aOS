bits 32

; 32-bit protected-mode debug output.
; All functions use ESI for string pointers (matching vga_print_string convention).
; Hex functions are non-destructive: they save/restore every register they touch.

global dbg_ok
global dbg_err
global dbg_info
global dbg_hex8
global dbg_hex16
global dbg_hex32
global dbg_dump_regs
global dbg_dump_frame
global dbg_panic

extern vga_putchar
extern vga_newline
extern vga_print_string
extern vga_print_line
extern vga_set_attr

; VGA attribute codes (foreground color on black background).
DBG_ATTR_NORMAL equ 0x07    ; light gray  — default body text
DBG_ATTR_OK     equ 0x0A    ; bright green — success prefix
DBG_ATTR_ERR    equ 0x0C    ; bright red   — error prefix / panic
DBG_ATTR_INFO   equ 0x0E    ; yellow       — informational prefix
DBG_ATTR_DUMP   equ 0x0B    ; bright cyan  — register dump

section .text

; ─── Log-level prefix helpers ────────────────────────────────────────────────
;
; Each prints a short colored prefix, resets to normal, then prints the caller's
; ESI message string followed by a newline.
;
; Input:  ESI = pointer to null-terminated message string.
; Output: nothing.  All registers preserved.

dbg_ok:
    push esi
    mov al, DBG_ATTR_OK
    call vga_set_attr
    mov esi, str_prefix_ok
    call vga_print_string
    mov al, DBG_ATTR_NORMAL
    call vga_set_attr
    pop esi
    call vga_print_line
    ret

dbg_err:
    push esi
    mov al, DBG_ATTR_ERR
    call vga_set_attr
    mov esi, str_prefix_err
    call vga_print_string
    mov al, DBG_ATTR_NORMAL
    call vga_set_attr
    pop esi
    call vga_print_line
    ret

dbg_info:
    push esi
    mov al, DBG_ATTR_INFO
    call vga_set_attr
    mov esi, str_prefix_info
    call vga_print_string
    mov al, DBG_ATTR_NORMAL
    call vga_set_attr
    pop esi
    call vga_print_line
    ret


; ─── Hex output ──────────────────────────────────────────────────────────────
;
; None of these emit a newline — the caller decides what follows.
; All registers are preserved.

; Print AL as two uppercase hex digits.
dbg_hex8:
    push eax
    push ebx
    mov bl, al
    shr al, 4
    call .nibble
    mov al, bl
    and al, 0x0F
    call .nibble
    pop ebx
    pop eax
    ret

.nibble:
    cmp al, 10
    jb .digit
    add al, 'A' - 10
    jmp .emit
.digit:
    add al, '0'
.emit:
    call vga_putchar
    ret

; Print AX as four uppercase hex digits (high byte first).
dbg_hex16:
    push eax
    push ebx
    movzx ebx, ax
    mov al, bh
    call dbg_hex8
    mov al, bl
    call dbg_hex8
    pop ebx
    pop eax
    ret

; Print EAX as eight uppercase hex digits (high word first).
dbg_hex32:
    push eax
    push ebx
    mov ebx, eax
    shr eax, 16
    call dbg_hex16
    mov eax, ebx
    call dbg_hex16
    pop ebx
    pop eax
    ret


; ─── Register dump ───────────────────────────────────────────────────────────

; Print registers from a pushad save area addressed by EBP.
;
; This is the shared core used by both dbg_dump_regs (normal call) and
; isr_common (exception frame) so each shows the register values that were
; live at the moment of interest, not after further setup.
;
; Input:  EBP = pointer to pushad save area with the layout:
;   [ebp+ 0] EDI    [ebp+ 4] ESI
;   [ebp+ 8] EBP    [ebp+12] ESP  (value at time of pushad)
;   [ebp+16] EBX    [ebp+20] EDX
;   [ebp+24] ECX    [ebp+28] EAX
;
; Clobbers: EBP (consumed as input, not restored).  EAX and ESI are saved.
; All other registers are unchanged.

dbg_dump_frame:
    push eax
    push esi

    mov al, DBG_ATTR_DUMP
    call vga_set_attr
    mov esi, str_dump_hdr
    call vga_print_line

    ; EAX  EBX
    mov esi, str_eax
    call vga_print_string
    mov eax, [ebp+28]
    call dbg_hex32
    mov esi, str_sep
    call vga_print_string
    mov esi, str_ebx
    call vga_print_string
    mov eax, [ebp+16]
    call dbg_hex32
    call vga_newline

    ; ECX  EDX
    mov esi, str_ecx
    call vga_print_string
    mov eax, [ebp+24]
    call dbg_hex32
    mov esi, str_sep
    call vga_print_string
    mov esi, str_edx
    call vga_print_string
    mov eax, [ebp+20]
    call dbg_hex32
    call vga_newline

    ; ESI  EDI
    mov esi, str_esi_lbl
    call vga_print_string
    mov eax, [ebp+4]
    call dbg_hex32
    mov esi, str_sep
    call vga_print_string
    mov esi, str_edi
    call vga_print_string
    mov eax, [ebp+0]
    call dbg_hex32
    call vga_newline

    ; EBP  ESP
    mov esi, str_ebp
    call vga_print_string
    mov eax, [ebp+8]
    call dbg_hex32
    mov esi, str_sep
    call vga_print_string
    mov esi, str_esp
    call vga_print_string
    mov eax, [ebp+12]
    call dbg_hex32
    call vga_newline

    mov al, DBG_ATTR_NORMAL
    call vga_set_attr

    pop esi
    pop eax
    ret


; Dump all general-purpose registers to the screen.
; Saves and restores all registers.
dbg_dump_regs:
    pushad
    mov ebp, esp
    call dbg_dump_frame
    popad
    ret


; ─── Panic ───────────────────────────────────────────────────────────────────
;
; Print an error message in red, dump all registers, then halt permanently.
; Input: ESI = pointer to null-terminated error string.

dbg_panic:
    push esi

    mov al, DBG_ATTR_ERR
    call vga_set_attr
    mov esi, str_panic_hdr
    call vga_print_string
    mov al, DBG_ATTR_NORMAL
    call vga_set_attr

    pop esi
    call vga_print_line

    call dbg_dump_regs

.halt:
    cli
    hlt
    jmp .halt


section .data

str_prefix_ok:   db "[ OK ] ", 0
str_prefix_err:  db "[ERR!] ", 0
str_prefix_info: db "[....] ", 0

str_dump_hdr:    db "--- register dump ---", 0
str_sep:         db "   ", 0
str_eax:         db "EAX ", 0
str_ebx:         db "EBX ", 0
str_ecx:         db "ECX ", 0
str_edx:         db "EDX ", 0
str_esi_lbl:     db "ESI ", 0
str_edi:         db "EDI ", 0
str_ebp:         db "EBP ", 0
str_esp:         db "ESP ", 0

str_panic_hdr:   db "!!! PANIC: ", 0
