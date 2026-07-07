bits 32

global pic_init
global pic_mask_all
global pic_set_mask
global pic_eoi

PIC1_CMD  equ 0x20      ; Master PIC: command port
PIC1_DATA equ 0x21      ; Master PIC: data / mask port
PIC2_CMD  equ 0xA0      ; Slave  PIC: command port
PIC2_DATA equ 0xA1      ; Slave  PIC: data / mask port

PIC_EOI   equ 0x20      ; Non-specific End-of-Interrupt command

ICW1_INIT equ 0x10      ; Required bit that starts the ICW sequence
ICW1_ICW4 equ 0x01      ; ICW4 will follow
ICW4_8086 equ 0x01      ; 8086/88 mode (not MCS-80/85)

section .text

; Remap both 8259A PICs so their IRQ vectors no longer collide with CPU
; exception vectors 8-15 (the BIOS default mapping).
;
; After this call:
;   Master IRQs 0-7  → vectors  master_vec  ..  master_vec+7
;   Slave  IRQs 8-15 → vectors  slave_vec   ..  slave_vec+7
;
; Typical usage: AL=0x20, AH=0x28  (IRQ0-7 → 32-39, IRQ8-15 → 40-47)
;
; Input:  AL = master vector base (must be multiple of 8)
;         AH = slave  vector base (must be multiple of 8)
; All registers preserved.
pic_init:
    push eax
    push ecx

    mov cl, al          ; stash master_vec in CL
    mov ch, ah          ; stash slave_vec  in CH

    ; ICW1: begin initialization, edge-triggered, cascade mode, ICW4 needed
    mov al, ICW1_INIT | ICW1_ICW4
    out PIC1_CMD, al
    call io_wait
    out PIC2_CMD, al
    call io_wait

    ; ICW2: vector base offsets
    mov al, cl
    out PIC1_DATA, al
    call io_wait
    mov al, ch
    out PIC2_DATA, al
    call io_wait

    ; ICW3: cascade wiring
    mov al, 0x04        ; master: IRQ2 pin is wired to the slave
    out PIC1_DATA, al
    call io_wait
    mov al, 0x02        ; slave: its cascade identity number is 2
    out PIC2_DATA, al
    call io_wait

    ; ICW4: 8086 mode on both PICs
    mov al, ICW4_8086
    out PIC1_DATA, al
    call io_wait
    out PIC2_DATA, al
    call io_wait

    pop ecx
    pop eax
    ret


; Mask every IRQ on both PICs (all bits set = all masked).
; All registers preserved.
pic_mask_all:
    push eax
    mov al, 0xFF
    out PIC1_DATA, al
    call io_wait
    out PIC2_DATA, al
    call io_wait
    pop eax
    ret


; Write IRQ mask bytes to both PICs.
; A set bit masks (disables) the corresponding IRQ line.
;
; Input:  AL = master mask (bit N = mask IRQ N, e.g. 0xFE unmasks only IRQ0)
;         AH = slave  mask
; All registers preserved.
pic_set_mask:
    push eax
    push ecx
    mov cl, al
    mov ch, ah
    mov al, cl
    out PIC1_DATA, al
    call io_wait
    mov al, ch
    out PIC2_DATA, al
    call io_wait
    pop ecx
    pop eax
    ret


; Send the non-specific End-of-Interrupt command to the appropriate PIC(s).
;
; For slave IRQs 8-15, EOI goes to the slave first, then to the master
; (the master sees the IRQ as coming via its cascade line, IRQ2).
;
; Input:  EAX = IRQ number (0-15).
; All registers preserved.
pic_eoi:
    push eax
    cmp eax, 8
    jl .master_only
    mov al, PIC_EOI
    out PIC2_CMD, al
    call io_wait
.master_only:
    mov al, PIC_EOI
    out PIC1_CMD, al
    ; No io_wait here — the IRET that follows provides sufficient settling time.
    pop eax
    ret


; Write a zero byte to the POST debug port (0x80) for ~1-4 µs I/O delay.
; This is the standard technique for letting the 8259A settle between commands.
io_wait:
    push eax
    xor al, al
    out 0x80, al
    pop eax
    ret
