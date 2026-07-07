bits 16

%include "boot/include/e820.inc"

global print_memory_map

extern memory_map_entries
extern memory_map_buffer
extern print_string
extern print_line
extern print_newline
extern print_hex16
extern print_hex64_mem

section .text

; Print the type label for an E820 entry type code.
; Input: AX = type code (1–5)
; Clobbers: SI
print_memory_type:
    cmp ax, E820_TYPE_USABLE
    je .usable
    cmp ax, E820_TYPE_RESERVED
    je .reserved
    cmp ax, E820_TYPE_ACPI
    je .acpi
    cmp ax, E820_TYPE_NVS
    je .nvs
    cmp ax, E820_TYPE_BAD
    je .bad
    mov si, str_unknown
    jmp .print
.usable:
    mov si, str_usable
    jmp .print
.reserved:
    mov si, str_reserved
    jmp .print
.acpi:
    mov si, str_acpi
    jmp .print
.nvs:
    mov si, str_nvs
    jmp .print
.bad:
    mov si, str_bad
.print:
    call print_line
    ret

; Print all E820 entries from memory_map_buffer.
print_memory_map:
    push ax
    push bx
    push cx
    push si
    push di

    mov si, str_map_title
    call print_line
    call print_newline

    mov cx, [memory_map_entries]
    mov di, memory_map_buffer   ; DI = pointer to current entry

    xor bx, bx                  ; BX = entry index

.loop:
    cmp bx, cx
    je .done

    mov si, str_entry
    call print_string
    mov ax, bx
    call print_hex16
    call print_newline

    mov si, str_base
    call print_string
    mov si, di                  ; SI -> entry base field (offset 0)
    call print_hex64_mem
    call print_newline

    mov si, str_length
    call print_string
    mov si, di
    add si, 8                   ; SI -> entry length field (offset 8)
    call print_hex64_mem
    call print_newline

    mov si, str_type
    call print_string
    mov ax, [di+16]             ; Type field (offset 16, read as 16-bit)
    call print_memory_type

    call print_newline          ; Blank line between entries

    add di, E820_ENTRY_SIZE
    inc bx
    jmp .loop

.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

section .data

str_map_title: db "===== E820 Memory Map =====", 0
str_entry:     db "Entry ", 0
str_base:      db "  Base   : 0x", 0
str_length:    db "  Length : 0x", 0
str_type:      db "  Type   : ", 0
str_usable:    db "Usable", 0
str_reserved:  db "Reserved", 0
str_acpi:      db "ACPI Reclaimable", 0
str_nvs:       db "ACPI NVS", 0
str_bad:       db "Bad Memory", 0
str_unknown:   db "Unknown", 0
