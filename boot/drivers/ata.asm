bits 32

global ata_read_sectors

; ATA primary controller I/O port base addresses.
; All ports are > 0xFF, so IN/OUT must use the DX-register form.
ATA_DATA    equ 0x1F0
ATA_COUNT   equ 0x1F2
ATA_LBA0    equ 0x1F3       ; LBA bits  7-0
ATA_LBA1    equ 0x1F4       ; LBA bits 15-8
ATA_LBA2    equ 0x1F5       ; LBA bits 23-16
ATA_DRIVE   equ 0x1F6       ; drive select + LBA bits 27-24
ATA_STATUS  equ 0x1F7       ; status (read)
ATA_CMD     equ 0x1F7       ; command (write)

ATA_BSY     equ 0x80
ATA_RDY     equ 0x40
ATA_DRQ     equ 0x08
ATA_ERR_BIT equ 0x01

ATA_CMD_READ equ 0x20
ATA_TIMEOUT  equ 0x3FFFFFF  ; ~67M polls ≈ several seconds on real hardware

section .text

; Read sectors from ATA primary master using LBA28 PIO polling mode.
;
; Input:  EAX = starting LBA (28-bit)
;         ECX = number of sectors (1-255)
;         EDI = destination buffer (ECX * 512 contiguous bytes)
; Output: CF clear on success, CF set on timeout or drive error.
;         All registers preserved (full pushad/popad).
ata_read_sectors:
    pushad
    mov ebx, eax            ; EBX = current LBA, walks forward each sector

.loop:
    test ecx, ecx
    jz .ok

    call .wait_rdy
    jc .err

    ; ── LBA28 register setup ─────────────────────────────────────────────────
    mov dx, ATA_COUNT
    mov al, 1               ; one sector at a time keeps the logic simple
    out dx, al

    mov al, bl              ; LBA[7:0]
    mov dx, ATA_LBA0
    out dx, al

    mov eax, ebx
    shr eax, 8
    mov dx, ATA_LBA1
    out dx, al              ; LBA[15:8]

    shr eax, 8
    mov dx, ATA_LBA2
    out dx, al              ; LBA[23:16]

    shr eax, 8
    and al, 0x0F
    or  al, 0xE0            ; LBA mode + master (bit7=1 bit6=LBA bit5=1 bit4=slave=0)
    mov dx, ATA_DRIVE
    out dx, al              ; LBA[27:24] + flags

    mov al, ATA_CMD_READ
    mov dx, ATA_CMD
    out dx, al

    call .wait_drq
    jc .err

    ; ── Transfer 512 bytes (256 words) from the drive buffer ─────────────────
    push ecx
    mov ecx, 256
    mov edx, ATA_DATA
    rep insw                ; ES:EDI ← port EDX, ECX words, EDI += 2 per word
    pop ecx

    inc ebx                 ; advance to next LBA
    dec ecx
    jmp .loop

.ok:
    popad
    clc
    ret

.err:
    popad
    stc
    ret


; ── Internal helpers ──────────────────────────────────────────────────────────
;
; Both polls keep the timeout counter in ESI so that setting DX to the port
; address does not clobber it (EDX and ESI are independent registers).

; Poll ATA_STATUS until BSY=0 and RDY=1.  Returns CF set on timeout.
.wait_rdy:
    push eax
    push esi
    push edx
    mov esi, ATA_TIMEOUT
.wr_spin:
    mov dx, ATA_STATUS
    in al, dx
    test al, ATA_BSY
    jz .wr_check_rdy
    dec esi
    jnz .wr_spin
    pop edx
    pop esi
    pop eax
    stc
    ret
.wr_check_rdy:
    test al, ATA_RDY
    jnz .wr_ok
    dec esi
    jnz .wr_spin
    pop edx
    pop esi
    pop eax
    stc
    ret
.wr_ok:
    pop edx
    pop esi
    pop eax
    clc
    ret


; Poll ATA_STATUS until BSY=0 and DRQ=1.  Returns CF set on timeout or ERR.
.wait_drq:
    push eax
    push esi
    push edx
    mov esi, ATA_TIMEOUT
.drq_spin:
    mov dx, ATA_STATUS
    in al, dx
    test al, ATA_BSY
    jnz .drq_next
    test al, ATA_ERR_BIT
    jnz .drq_fail
    test al, ATA_DRQ
    jnz .drq_ok
.drq_next:
    dec esi
    jnz .drq_spin
.drq_fail:
    pop edx
    pop esi
    pop eax
    stc
    ret
.drq_ok:
    pop edx
    pop esi
    pop eax
    clc
    ret
