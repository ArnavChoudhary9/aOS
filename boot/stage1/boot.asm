bits 16
org 0x7c00

start:
    ; Blocks interrupts, so we can setup the stack without being interrupted
    ; Intrupts before the stack is setup can cause a crash, so we block them until the stack is setup
    cli

    xor ax, ax ; Clear the AX register

    ; Zero out the data segment registers
    mov ds, ax ; Data Segment
    mov es, ax ; Extra Segment
    mov ss, ax ; Stack Segment

    ; Setup the stack pointer
    mov sp, 0x7c00 ; Set the stack pointer to the top of the bootloader area

    mov si, welcome_msg
    call print_string

; Hang the system
hang:
    hlt
    jmp hang ; Infinite loop to hang the system

welcome_msg:
    db 'Welcome to the bootloader!', 0

print_string:
    ; ah -> high byte of the function number (0x0e for teletype output)
    ; al -> low byte of the character to print
.loop:
    mov al, [si]  ; Character to print

    cmp al, 0     ; Check for null terminator
    je .done      ; If null terminator, we're done

    mov ah, 0x0e  ; Function number for teletype output
    int 0x10      ; Call BIOS interrupt to print character
    inc si         ; Move to the next character
    jmp .loop ; Repeat for the next character

.done:
    ret

times 510-($-$$) db 0
dw 0xaa55 ; Boot signature
