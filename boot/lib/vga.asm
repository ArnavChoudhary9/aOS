bits 32

global vga_init
global vga_putchar
global vga_newline
global vga_print_string
global vga_print_line
global vga_set_attr

VGA_BASE     equ 0xB8000
VGA_COLS     equ 80
VGA_ROWS     equ 25
VGA_ATTR_DEF equ 0x07       ; default: light gray on black

section .text

; Clear screen, reset cursor, and restore the default color attribute.
vga_init:
    push eax
    push ecx
    push edi
    mov byte [vga_attr], VGA_ATTR_DEF
    mov edi, VGA_BASE
    mov ecx, VGA_COLS * VGA_ROWS
    mov ax, (VGA_ATTR_DEF << 8) | ' '
    rep stosw
    mov dword [vga_col], 0
    mov dword [vga_row], 0
    call vga_update_cursor
    pop edi
    pop ecx
    pop eax
    ret


; Set the current text attribute byte (color).
; Input: AL = attribute (e.g. 0x0A = bright green on black).
vga_set_attr:
    mov [vga_attr], al
    ret


; Write one character at the cursor and advance.
; Input: AL = ASCII character.
; Handles CR (0x0D) — reset column; LF (0x0A) — advance row, reset column.
vga_putchar:
    push eax
    push edi

    cmp al, 0x0D
    je .cr
    cmp al, 0x0A
    je .lf

    movzx edi, byte [vga_row]
    imul edi, VGA_COLS
    add edi, [vga_col]
    shl edi, 1
    add edi, VGA_BASE

    mov ah, [vga_attr]      ; current color attribute
    mov [edi], ax

    inc dword [vga_col]
    cmp dword [vga_col], VGA_COLS
    jl .update
    mov dword [vga_col], 0
    inc dword [vga_row]
    jmp .scroll_check

.lf:
    inc dword [vga_row]     ; LF: advance row, fall through to reset column
.cr:
    mov dword [vga_col], 0
    jmp .scroll_check

.scroll_check:
    cmp dword [vga_row], VGA_ROWS
    jl .update
    call vga_scroll
    mov dword [vga_row], VGA_ROWS - 1

.update:
    call vga_update_cursor
    pop edi
    pop eax
    ret


; Emit LF (moves to start of next row, scrolling if at the bottom).
vga_newline:
    push eax
    mov al, 0x0A
    call vga_putchar
    pop eax
    ret


; Print a null-terminated string.
; Input: ESI = pointer to string.
vga_print_string:
    push eax
    push esi
.loop:
    mov al, [esi]
    cmp al, 0
    je .done
    call vga_putchar
    inc esi
    jmp .loop
.done:
    pop esi
    pop eax
    ret


; Print a null-terminated string followed by a newline.
; Input: ESI = pointer to string.
vga_print_line:
    call vga_print_string
    call vga_newline
    ret


; Scroll the screen up by one row and clear the last row.
; Clobbers: AX (internal helper — callers already save EAX via vga_putchar).
vga_scroll:
    push ecx
    push esi
    push edi
    mov edi, VGA_BASE
    mov esi, VGA_BASE + VGA_COLS * 2
    mov ecx, VGA_COLS * (VGA_ROWS - 1)
    rep movsw                           ; shift rows 1-24 up to rows 0-23
    ; EDI now points at the start of the freed last row
    mov ecx, VGA_COLS
    movzx eax, byte [vga_attr]          ; clear with current attribute
    shl eax, 8
    or al, ' '
    rep stosw
    pop edi
    pop esi
    pop ecx
    ret


; Sync the hardware cursor via CRT controller ports 0x3D4/0x3D5.
vga_update_cursor:
    push eax
    push ecx
    push edx

    mov eax, [vga_row]
    imul eax, VGA_COLS
    add eax, [vga_col]
    mov ecx, eax            ; save linear cursor position

    mov dx, 0x3D4
    mov al, 0x0E            ; cursor high byte register
    out dx, al
    inc dx
    mov eax, ecx
    shr eax, 8
    out dx, al

    mov dx, 0x3D4
    mov al, 0x0F            ; cursor low byte register
    out dx, al
    inc dx
    mov eax, ecx
    out dx, al

    pop edx
    pop ecx
    pop eax
    ret


section .data

vga_col:  dd 0
vga_row:  dd 0
vga_attr: db VGA_ATTR_DEF
