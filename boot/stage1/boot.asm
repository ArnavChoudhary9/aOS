bits 16
org 0x7c00

STAGE2_SEGMENT  equ 0x0000
STAGE2_OFFSET   equ 0x8000
STAGE2_SECTORS  equ 16
STAGE2_CYLINDER equ 0
STAGE2_SECTOR   equ 2
STAGE2_HEAD     equ 0

start:
    cli

    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00

    mov [boot_drive], dl

    call print_newline
    mov si, msg_welcome
    call print_line

    call load_stage2
    jc .disk_error

    jmp STAGE2_SEGMENT:STAGE2_OFFSET

.disk_error:
    mov si, msg_disk_error
    call print_line

hang:
    hlt
    jmp hang

load_stage2:
    mov ax, STAGE2_SEGMENT
    mov es, ax
    mov bx, STAGE2_OFFSET

    mov ah, 0x02
    mov al, STAGE2_SECTORS
    mov ch, STAGE2_CYLINDER
    mov cl, STAGE2_SECTOR
    mov dh, STAGE2_HEAD
    mov dl, [boot_drive]

    int 0x13
    ret

; ------------------------------------------------------------------
; Minimal print routines — inlined to keep stage 1 self-contained.
; The full print library lives in boot/lib/print.asm (stage 2 only).
; ------------------------------------------------------------------

print_char:
    push ax
    mov ah, 0x0e
    int 0x10
    pop ax
    ret

print_newline:
    mov al, 0x0d
    call print_char
    mov al, 0x0a
    call print_char
    ret

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

print_line:
    call print_string
    call print_newline
    ret

; ------------------------------------------------------------------

boot_drive:     db 0

msg_welcome:    db "aOS Stage 1", 0
msg_disk_error: db "Disk read error!", 0

times 510-($-$$) db 0
dw 0xaa55
