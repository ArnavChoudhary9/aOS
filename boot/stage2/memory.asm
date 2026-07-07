bits 16

%include "boot/include/e820.inc"

global detect_memory
global memory_map_entries
global memory_map_buffer

section .text

; Populate memory_map_buffer via BIOS INT 15h/E820.
; Sets memory_map_entries to the number of entries found.
; Returns: CF clear on success, CF set on error.
detect_memory:
    xor ax, ax
    mov es, ax
    mov di, memory_map_buffer
    mov word [memory_map_entries], 0
    xor ebx, ebx

.next_entry:
    mov eax, 0xe820
    mov edx, 0x534d4150     ; 'SMAP'
    mov ecx, E820_ENTRY_SIZE

    int 0x15

    jc .error

    cmp eax, 0x534d4150
    jne .error

    inc word [memory_map_entries]
    add di, E820_ENTRY_SIZE

    test ebx, ebx           ; EBX == 0 means last entry
    jnz .next_entry

.success:
    clc
    ret

.error:
    stc
    ret

section .data

memory_map_entries: dw 0
memory_map_buffer:  times E820_BUFFER_SIZE db 0
