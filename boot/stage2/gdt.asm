bits 16

global load_gdt

; Selectors used by pm32_start to reload segment registers.
GDT_CODE_SEL equ 0x08
GDT_DATA_SEL equ 0x10

section .text

; Load the GDTR with our flat 32-bit descriptor table.
; No return value. Caller must immediately set CR0.PE and far-jump.
load_gdt:
    lgdt [gdt_descriptor]
    ret

section .data

align 8
gdt_start:
    ; Descriptor 0 — null (required by spec, any access faults)
    dq 0

    ; Descriptor 1 — code segment selector 0x08
    ; Base=0, Limit=4GB (with G=1 granularity gives 0xFFFFF * 4K), ring 0, 32-bit, execute/read
gdt_code:
    dw 0xFFFF           ; limit[0:15]
    dw 0x0000           ; base[0:15]
    db 0x00             ; base[16:23]
    db 0x9A             ; access: P=1 DPL=00 S=1 Type=1010 (code, exec/read, non-conforming)
    db 0xCF             ; flags: G=1 D/B=1 L=0 AVL=0 | limit[16:19]=0xF
    db 0x00             ; base[24:31]

    ; Descriptor 2 — data segment selector 0x10
    ; Base=0, Limit=4GB, ring 0, 32-bit, read/write
gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92             ; access: P=1 DPL=00 S=1 Type=0010 (data, read/write, expand-up)
    db 0xCF
    db 0x00
gdt_end:

; LGDT operand: 6 bytes = 2-byte limit + 4-byte base
gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start
