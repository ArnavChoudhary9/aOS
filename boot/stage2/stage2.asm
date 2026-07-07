bits 16
org 0x8000

start_stage2:
    mov si, stage2_msg
    call print_string

hang:
    hlt
    jmp hang

%include "boot/include/print.inc"

stage2_msg:
    db "Stage 2 loaded successfully!", 0
