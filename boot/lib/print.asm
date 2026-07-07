bits 16

global print_char
global print_newline
global print_string
global print_line
global print_hex8
global print_hex16
global print_hex32
global print_hex64_mem
global dump_memory
global print_ok
global print_err
global print_info

extern hex_to_ascii

section .text

; Print a single character via BIOS teletype output.
; Input: AL = character
print_char:
    push ax
    mov ah, 0x0e
    int 0x10
    pop ax
    ret

; Print CR+LF.
print_newline:
    mov al, 0x0d
    call print_char
    mov al, 0x0a
    call print_char
    ret

; Print a null-terminated string.
; Input: SI = pointer to string
print_string:
    push ax
    push si
.loop:
    mov al, [si]
    cmp al, 0
    je .done
    call print_char
    inc si
    jmp .loop
.done:
    pop si
    pop ax
    ret

; Print a null-terminated string followed by CR+LF.
; Input: SI = pointer to string
print_line:
    call print_string
    call print_newline
    ret

; Print a byte as two uppercase hex digits.
; Input: AL = byte
print_hex8:
    push ax

    mov ah, al      ; Save original
    shr al, 4       ; High nibble
    call hex_to_ascii
    call print_char

    mov al, ah      ; Low nibble
    and al, 0x0f
    call hex_to_ascii
    call print_char

    pop ax
    ret

; Print a 16-bit word as four uppercase hex digits.
; Input: AX = word
print_hex16:
    push ax
    push bx

    mov bx, ax
    mov al, bh      ; High byte first
    call print_hex8
    mov al, bl      ; Low byte
    call print_hex8

    pop bx
    pop ax
    ret

; Print a 32-bit dword as eight uppercase hex digits.
; Input: EAX = dword
print_hex32:
    push eax
    push ax         ; Save low 16 bits

    shr eax, 16    ; High 16 bits now in AX
    call print_hex16

    pop ax         ; Restore low 16 bits
    call print_hex16

    pop eax
    ret

; Print a 64-bit little-endian value from memory.
; Input: SI = pointer to 8-byte little-endian value
print_hex64_mem:
    push ax
    push si

    mov ax, [si+6]
    call print_hex16
    mov ax, [si+4]
    call print_hex16
    mov ax, [si+2]
    call print_hex16
    mov ax, [si]
    call print_hex16

    pop si
    pop ax
    ret

; Hex dump — 16 bytes per line with ASCII sidebar.
; Input: DS:SI = start address, CX = byte count
dump_memory:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov bx, si

.next_line:
    cmp cx, 0
    je .done

    mov ax, si
    sub ax, bx
    call print_hex16
    mov al, ':'
    call print_char
    mov al, ' '
    call print_char

    push si
    push cx
    xor di, di

.hex_loop:
    cmp cx, 0
    je .hex_done
    lodsb
    call print_hex8
    mov al, ' '
    call print_char
    inc di
    dec cx
    cmp di, 16
    jne .hex_loop

.hex_done:
.pad_loop:
    cmp di, 16
    je .ascii_start
    mov al, ' '
    call print_char
    call print_char
    call print_char
    inc di
    jmp .pad_loop

.ascii_start:
    mov al, '|'
    call print_char
    pop cx
    pop si
    xor di, di

.ascii_loop:
    cmp di, 16
    je .ascii_done
    cmp cx, 0
    je .ascii_done
    lodsb
    cmp al, 32
    jb .dot
    cmp al, 126
    ja .dot
    jmp .print_it
.dot:
    mov al, '.'
.print_it:
    call print_char
    inc di
    dec cx
    jmp .ascii_loop

.ascii_done:
    mov al, '|'
    call print_char
    call print_newline
    jmp .next_line

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; Print "[OK]  " prefix then SI message + newline.
print_ok:
    push si
    mov si, str16_ok
    call print_string
    pop si
    call print_line
    ret

; Print "[ERR] " prefix then SI message + newline.
print_err:
    push si
    mov si, str16_err
    call print_string
    pop si
    call print_line
    ret

; Print "[..] " prefix then SI message + newline.
print_info:
    push si
    mov si, str16_info
    call print_string
    pop si
    call print_line
    ret

section .data

str16_ok:   db "[OK]  ", 0
str16_err:  db "[ERR] ", 0
str16_info: db "[..] ", 0
