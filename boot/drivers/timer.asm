bits 32

global timer_init
global timer_get_ticks

extern irq_handlers         ; dispatch table in idt.asm

; PIT 8253/8254 ports
PIT_CH0     equ 0x40        ; channel 0 data (connected to IRQ0)
PIT_CMD     equ 0x43        ; mode / command register

; Target frequency and divisor.
; PIT input clock = 1,193,182 Hz.  At 100 Hz: divisor = 11931.
TIMER_HZ    equ 100
TIMER_DIV   equ 1193182 / TIMER_HZ

; VGA position for the live tick counter: row 0, column 72 (top-right, 8 chars).
TIMER_VGA   equ 0xB8000 + (0 * 80 + 72) * 2

section .text

; IRQ0 handler — called by irq_common after pushad.
; Increments the tick counter and redraws it at the top-right of the VGA screen.
; Does NOT call any VGA driver functions — writes directly to the VGA buffer to
; avoid re-entrancy issues with the cursor state machine.
timer_irq_handler:
    push eax
    push ecx
    push edi

    inc dword [timer_ticks]

    ; Render [timer_ticks] as 8 hex digits at TIMER_VGA.
    ; Strategy: load EAX, shift left 4 bits per digit, extracting the MSB nibble.
    mov eax, [timer_ticks]
    mov edi, TIMER_VGA
    mov ecx, 8

.digit:
    push eax
    shr eax, 28             ; top nibble → AL (bits 3-0)
    and al, 0x0F
    add al, '0'
    cmp al, '9' + 1
    jb .write               ; 0-9: done
    add al, 'A' - '0' - 10 ; 10-15: A-F  ('0'+10=':'; ':'+'A'-'0'-10='A')
.write:
    mov ah, 0x0F            ; white on black
    mov [edi], ax
    add edi, 2
    pop eax
    shl eax, 4              ; advance to next nibble
    dec ecx
    jnz .digit

    pop edi
    pop ecx
    pop eax
    ret


; Program PIT channel 0 to fire at TIMER_HZ and install the IRQ0 handler.
; All registers preserved.
timer_init:
    push eax

    ; Command: channel 0 | lobyte/hibyte | mode 3 (square wave) | binary
    mov al, 0x36
    out PIT_CMD, al

    ; Send divisor low byte then high byte
    mov ax, TIMER_DIV
    out PIT_CH0, al
    mov al, ah
    out PIT_CH0, al

    mov dword [irq_handlers + 0*4], timer_irq_handler

    pop eax
    ret


; Return the current tick count in EAX.
timer_get_ticks:
    mov eax, [timer_ticks]
    ret


section .data

timer_ticks: dd 0
