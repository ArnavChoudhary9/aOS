print_string:
    push ax
    push si
    
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
    pop si
    pop ax
    ret
