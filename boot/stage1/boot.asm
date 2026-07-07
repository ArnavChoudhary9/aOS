bits 16
org 0x7c00

start:
    ; Blocks interrupts, so we can setup the stack without being interrupted
    ; Intrupts before the stack is setup can cause a crash, so we block them until the stack is setup
    cli

    xor ax, ax ; Clear AX

    ; Zero out the data segment registers
    mov ds, ax ; Data Segment
    mov es, ax ; Extra Segment
    mov ss, ax ; Stack Segment

    ; Setup the stack pointer
    mov sp, 0x7c00 ; Set the stack pointer to the top of the bootloader area

    mov [boot_drive], dl ; Store the boot drive number passed by BIOS into boot_drive

    call load_stage2
    jc disk_error ; If there was an error loading stage 2, jump to disk_error

    jmp 0x0000:0x8000 ; Jump to the start of stage 2

load_stage2:
    ; Load stage 2 of the bootloader from disk into memory at 0x8000
    mov ax, 0x0000 ; Clear AX register
    mov es, ax     ; Set ES to 0x0000 (segment for loading stage 2)
    mov bx, 0x8000 ; Set BX to 0x8000

    mov ah, 0x02 ; BIOS function to read sectors from disk
    mov al, 4    ; Number of sectors to read (4 sectors for stage 2)
   
    mov ch, 0    ; Cylinder number (0 for the first cylinder)
    mov cl, 2    ; Sector number (2 for the second sector, as stage 1 is in sector 1)
    
    mov dh, 0    ; Head number (0 for the first head)
    mov dl, [boot_drive] ; Drive number passed by BIOS
    
    int 0x13      ; Call BIOS interrupt
    ret

disk_error:
    mov si, disk_error_msg
    call print_string

    jmp hang

hang:
    hlt
    jmp hang

%include "boot/include/print.inc"

boot_drive:
    db 0x00 ; Placeholder for the boot drive number, will be filled by BIOS

disk_error_msg:
    db "Disk read error. Please check the disk and try again.", 0

times 510-($-$$) db 0
dw 0xaa55 ; Boot signature
