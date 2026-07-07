bits 16

global enable_a20

section .text

; Enable the A20 address line.
; Tries BIOS INT 15h/2401h, keyboard controller (8042), Fast A20 port 0x92.
; Returns: CF clear on success, CF set if all methods failed.
enable_a20:
    call a20_check
    test ax, ax
    jnz .ok

    ; Method 1: BIOS
    mov ax, 0x2401
    int 0x15

    call a20_check
    test ax, ax
    jnz .ok

    ; Method 2: keyboard controller (8042)
    call a20_kbd
    call a20_check
    test ax, ax
    jnz .ok

    ; Method 3: Fast A20 port 0x92
    in al, 0x92
    test al, 0x02       ; already set?
    jnz .fast_check
    or al, 0x02
    and al, 0xFE        ; keep bit 0 clear (avoid system reset)
    out 0x92, al

.fast_check:
    call a20_check
    test ax, ax
    jnz .ok

    stc
    ret

.ok:
    clc
    ret


; Keyboard controller A20 enable sequence.
a20_kbd:
    call a20_kbd_wait
    mov al, 0xD1        ; write output port
    out 0x64, al

    call a20_kbd_wait
    mov al, 0xDF        ; enable A20 gate (bit 1)
    out 0x60, al

    call a20_kbd_wait
    ret


; Wait for 8042 input buffer to be empty (port 0x64 bit 1 clear).
a20_kbd_wait:
    in al, 0x64
    test al, 0x02
    jnz a20_kbd_wait
    ret


; Check if A20 line is enabled.
; Writes distinct values to 0x0000:0x0500 and 0xFFFF:0x0510 (physical 0x100500).
; If A20 is off they alias to the same physical address.
; Returns: AX = 1 if enabled, AX = 0 if disabled.
; Clobbers: nothing (saves and restores all used registers and flags).
a20_check:
    pushf
    push ds
    push es
    push bx

    cli

    xor ax, ax
    mov es, ax          ; ES = 0x0000

    mov ax, 0xFFFF
    mov ds, ax          ; DS = 0xFFFF → DS:0x0510 = physical 0x100500 (if A20 on)

    mov al, [es:0x0500]
    push ax
    mov al, [ds:0x0510]
    push ax

    mov byte [es:0x0500], 0x00
    mov byte [ds:0x0510], 0xFF

    ; If A20 off, 0xFFFF:0x0510 wraps to 0x0500, so [es:0x0500] becomes 0xFF
    cmp byte [es:0x0500], 0xFF
    je .off

    mov bx, 1
    jmp .restore

.off:
    xor bx, bx

.restore:
    pop ax
    mov [ds:0x0510], al
    pop ax
    mov [es:0x0500], al

    mov ax, bx

    pop bx
    pop es
    pop ds
    popf
    ret
