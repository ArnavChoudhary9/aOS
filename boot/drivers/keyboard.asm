bits 32

global kbd_init
global kbd_getchar

extern irq_handlers

KBD_DATA    equ 0x60
KBD_STATUS  equ 0x64

; Diagnostic VGA position: keyboard IRQ counter at row 0, col 64 (8 hex digits).
; Timer counter sits at row 0, col 72 — 8 cols to the right.
KBD_VGA     equ 0xB8000 + (0 * 80 + 64) * 2

section .text

; IRQ1 handler — called by irq_common after pushad (no register save needed).
kbd_irq_handler:
    ; ── Diagnostic: increment IRQ counter and display it at KBD_VGA ──────────
    inc dword [kbd_irq_count]
    push eax
    push ecx
    push edi
    mov eax, [kbd_irq_count]
    mov edi, KBD_VGA
    mov ecx, 8
.diag:
    push eax
    shr eax, 28
    and al, 0x0F
    add al, '0'
    cmp al, '9' + 1
    jb .diag_write
    add al, 'A' - '0' - 10
.diag_write:
    mov ah, 0x0A            ; bright green on black
    mov [edi], ax
    add edi, 2
    pop eax
    shl eax, 4
    dec ecx
    jnz .diag
    pop edi
    pop ecx
    pop eax
    ; ── End diagnostic ────────────────────────────────────────────────────────

    in al, KBD_DATA         ; read scancode (must be done to de-assert IRQ1)

    test al, 0x80           ; bit 7 = break (key release) code
    jnz .release

    cmp al, 0x2A            ; left shift
    je .shift_on
    cmp al, 0x36            ; right shift
    je .shift_on
    cmp al, 0x3A            ; caps lock
    je .caps_toggle

    movzx eax, al
    cmp eax, 128
    jae .done

    cmp byte [kbd_shift], 0
    jne .shifted
    mov al, [kbd_normal_map + eax]
    jmp .apply_caps
.shifted:
    mov al, [kbd_shift_map + eax]

.apply_caps:
    test al, al
    jz .done
    cmp byte [kbd_caps], 0
    je .enqueue
    cmp al, 'a'
    jb .check_upper
    cmp al, 'z'
    ja .check_upper
    sub al, 32
    jmp .enqueue
.check_upper:
    cmp al, 'A'
    jb .enqueue
    cmp al, 'Z'
    ja .enqueue
    add al, 32

.enqueue:
    mov ecx, [kbd_tail]
    mov [kbd_buf + ecx], al

    ; Diagnostic: write translated char with white-on-red at VGA[0][56].
    ; This fires only for key-press events that produce non-zero ASCII.
    ; If something appears here when typing → translation works.
    ; If nothing appears → char mapped to 0 (check scancode set / translation).
    push edi
    mov edi, 0xB8000 + (0 * 80 + 56) * 2
    mov ah, 0x4F                    ; white on red
    mov [edi], ax
    pop edi

    inc ecx
    and ecx, 0xFF
    cmp ecx, [kbd_head]
    je .done
    mov [kbd_tail], ecx
    jmp .done

.shift_on:
    mov byte [kbd_shift], 1
    jmp .done
.caps_toggle:
    xor byte [kbd_caps], 1
    jmp .done
.release:
    and al, 0x7F
    cmp al, 0x2A
    je .shift_off
    cmp al, 0x36
    je .shift_off
    jmp .done
.shift_off:
    mov byte [kbd_shift], 0
.done:
    ret


; Return the next ASCII byte from the key buffer in AL (0 = empty).
kbd_getchar:
    push ecx
    mov ecx, [kbd_head]
    cmp ecx, [kbd_tail]
    je .empty
    movzx eax, byte [kbd_buf + ecx]
    inc ecx
    and ecx, 0xFF
    mov [kbd_head], ecx
    jmp .ret
.empty:
    xor eax, eax
.ret:
    pop ecx
    ret


; Initialize the PS/2 keyboard and install the IRQ1 handler.
;
; Correct ordering matters:
;   1. Drain output buffer (stale BIOS data would block future IRQ1 assertions).
;   2. Read and patch the CCB *before* sending 0xAE — sending 0xAE causes the
;      keyboard to clock out 0xAA (BAT result) into the output buffer, which
;      would be read as the CCB if we read it afterwards.
;   3. Send 0xAE to (re-)enable the keyboard port.
;   4. Drain the 0xAA that the keyboard sends after 0xAE.
;   5. Install the handler.
kbd_init:
    push eax
    push ecx

    ; Step 1: drain output buffer
.drain1:
    in al, KBD_STATUS
    test al, 0x01
    jz .drained
    in al, KBD_DATA
    jmp .drain1
.drained:

    ; Step 2a: read Controller Configuration Byte
.wait_rcb_cmd:
    in al, KBD_STATUS
    test al, 0x02
    jnz .wait_rcb_cmd
    mov al, 0x20            ; read CCB command
    out KBD_STATUS, al
.wait_rcb_data:
    in al, KBD_STATUS
    test al, 0x01
    jz .wait_rcb_data
    in al, KBD_DATA         ; AL = CCB

    ; Step 2b: ensure keyboard IRQ (bit 0) AND PS/2→set1 translation (bit 6) are on.
    or al, 0x41
    mov cl, al              ; save modified CCB in CL

    ; Step 2c: write modified CCB back
.wait_wcb_cmd:
    in al, KBD_STATUS
    test al, 0x02
    jnz .wait_wcb_cmd
    mov al, 0x60            ; write CCB command
    out KBD_STATUS, al
.wait_wcb_data:
    in al, KBD_STATUS
    test al, 0x02
    jnz .wait_wcb_data
    mov al, cl
    out KBD_DATA, al

    ; Step 3: enable first PS/2 port — this may cause keyboard to assert IRQ1
    ;         with BAT result 0xAA in the output buffer.
.wait_en:
    in al, KBD_STATUS
    test al, 0x02
    jnz .wait_en
    mov al, 0xAE
    out KBD_STATUS, al

    ; Step 4: small delay then drain 0xAA (keyboard self-test result)
    mov ecx, 0x4000
.delay:
    dec ecx
    jnz .delay
.drain2:
    in al, KBD_STATUS
    test al, 0x01
    jz .drained2
    in al, KBD_DATA
    jmp .drain2
.drained2:

    ; Step 5: install IRQ1 handler
    mov dword [irq_handlers + 1*4], kbd_irq_handler

    pop ecx
    pop eax
    ret


section .data

kbd_irq_count: dd 0         ; incremented on every IRQ1 — displayed at KBD_VGA

kbd_shift: db 0
kbd_caps:  db 0
kbd_head:  dd 0
kbd_tail:  dd 0
kbd_buf:   times 256 db 0

kbd_normal_map:
    db  0,  27, '1', '2', '3', '4', '5', '6'   ; 00h
    db '7', '8', '9', '0', '-', '=',   8,   9   ; 08h
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i'  ; 10h
    db 'o', 'p', '[', ']',  10,   0, 'a', 's'   ; 18h
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';'  ; 20h
    db  39,  96,   0,  92, 'z', 'x', 'c', 'v'  ; 28h
    db 'b', 'n', 'm', ',', '.', '/',   0, '*'   ; 30h
    db   0, ' ',   0,   0,   0,   0,   0,   0   ; 38h
    times 64 db 0

kbd_shift_map:
    db  0,  27, '!', '@', '#', '$', '%', '^'    ; 00h
    db '&', '*', '(', ')', '_', '+',   8,   9   ; 08h
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I'  ; 10h
    db 'O', 'P', '{', '}',  10,   0, 'A', 'S'   ; 18h
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':'  ; 20h
    db  34, 126,   0, 124, 'Z', 'X', 'C', 'V'  ; 28h
    db 'B', 'N', 'M', '<', '>',  '?',  0, '*'  ; 30h
    db   0, ' ',   0,   0,   0,   0,   0,   0   ; 38h
    times 64 db 0
