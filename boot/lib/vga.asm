bits 32

global vga_init
global vga_putchar
global vga_newline
global vga_print_string
global vga_print_line

VGA_BASE equ 0xB8000    ; physical address of VGA text buffer
VGA_COLS equ 80
VGA_ROWS equ 25
VGA_ATTR equ 0x07       ; light gray on black

section .text

; Clear the screen and reset the cursor to (0, 0).
vga_init:
    push eax
    push ecx
    push edi
    mov edi, VGA_BASE
    mov ecx, VGA_COLS * VGA_ROWS
    mov ax, (VGA_ATTR << 8) | ' '
    rep stosw               ; fill every cell with space + attribute
    mov dword [vga_col], 0
    mov dword [vga_row], 0
    call vga_update_cursor
    pop edi
    pop ecx
    pop eax
    ret


; Write one character at the current cursor position and advance.
; Input: AL = ASCII character
; Handles CR (0x0D) and LF (0x0A) as control codes.
vga_putchar:
    push eax
    push edi

    cmp al, 0x0D
    je .cr
    cmp al, 0x0A
    je .lf

    ; Compute VGA cell address: (row * 80 + col) * 2 + base
    movzx edi, byte [vga_row]
    imul edi, VGA_COLS
    add edi, [vga_col]
    shl edi, 1
    add edi, VGA_BASE

    mov ah, VGA_ATTR
    mov [edi], ax           ; write [char | attr] to cell

    inc dword [vga_col]
    cmp dword [vga_col], VGA_COLS
    jl .update
    ; Column overflow: wrap to next row
    mov dword [vga_col], 0
    inc dword [vga_row]
    jmp .scroll_check

.lf:
    inc dword [vga_row]     ; advance row, then fall through to reset column
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


; Emit CR+LF (moves to the beginning of the next row).
vga_newline:
    push eax
    mov al, 0x0A
    call vga_putchar
    pop eax
    ret


; Print a null-terminated string.
; Input: ESI = pointer to string
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
; Input: ESI = pointer to string
vga_print_line:
    call vga_print_string
    call vga_newline
    ret


; Scroll all rows up by one, clearing the bottom row.
vga_scroll:
    push ecx
    push esi
    push edi
    mov edi, VGA_BASE
    mov esi, VGA_BASE + VGA_COLS * 2   ; source = start of row 1
    mov ecx, VGA_COLS * (VGA_ROWS - 1)
    rep movsw                           ; copy rows 1..24 → rows 0..23
    ; EDI now points at the start of the (now-blank) last row
    mov ecx, VGA_COLS
    mov ax, (VGA_ATTR << 8) | ' '
    rep stosw                           ; clear last row
    pop edi
    pop esi
    pop ecx
    ret


; Sync the hardware blinking cursor with our software position.
; Uses CRT controller registers 0x0E (cursor high) and 0x0F (cursor low).
vga_update_cursor:
    push eax
    push ecx
    push edx

    mov eax, [vga_row]
    imul eax, VGA_COLS
    add eax, [vga_col]      ; linear word offset into VGA buffer
    mov ecx, eax

    mov dx, 0x3D4
    mov al, 0x0E            ; select cursor-high register
    out dx, al
    inc dx
    mov eax, ecx
    shr eax, 8              ; bits 8-15 of cursor position
    out dx, al

    mov dx, 0x3D4
    mov al, 0x0F            ; select cursor-low register
    out dx, al
    inc dx
    mov eax, ecx            ; bits 0-7 of cursor position
    out dx, al

    pop edx
    pop ecx
    pop eax
    ret


section .data

vga_col: dd 0
vga_row: dd 0
