bits 32

global load_idt
global irq_handlers         ; exported so callers can install IRQ handlers

extern vga_set_attr
extern vga_print_string
extern vga_print_line
extern vga_newline
extern dbg_hex8
extern dbg_hex32
extern dbg_dump_frame
extern pic_eoi

DBG_ATTR_NORMAL equ 0x07
DBG_ATTR_ERR    equ 0x0C

; ─── CPU exception stubs (vectors 0-31) ──────────────────────────────────────
;
; Exceptions without an error code push a dummy 0 first so isr_common always
; sees the same stack layout:
;   [esp+ 0] vector number
;   [esp+ 4] error code  (0 for non-error exceptions)
;   [esp+ 8] EIP         (CPU)
;   [esp+12] CS          (CPU)
;   [esp+16] EFLAGS      (CPU)

%macro isr_no_err 1
isr_%1:
    push dword 0
    push dword %1
    jmp isr_common
%endmacro

%macro isr_err 1
isr_%1:
    push dword %1
    jmp isr_common
%endmacro

isr_no_err  0   ; #DE  Divide Error
isr_no_err  1   ; #DB  Debug
isr_no_err  2   ;      NMI
isr_no_err  3   ; #BP  Breakpoint
isr_no_err  4   ; #OF  Overflow
isr_no_err  5   ; #BR  Bound Range Exceeded
isr_no_err  6   ; #UD  Invalid Opcode
isr_no_err  7   ; #NM  Device Not Available
isr_err     8   ; #DF  Double Fault           (error code always = 0)
isr_no_err  9   ;      Coprocessor Segment Overrun (legacy)
isr_err    10   ; #TS  Invalid TSS
isr_err    11   ; #NP  Segment Not Present
isr_err    12   ; #SS  Stack-Segment Fault
isr_err    13   ; #GP  General Protection
isr_err    14   ; #PF  Page Fault             (CR2 = faulting address)
isr_no_err 15   ;      Reserved
isr_no_err 16   ; #MF  x87 Floating-Point
isr_err    17   ; #AC  Alignment Check
isr_no_err 18   ; #MC  Machine Check
isr_no_err 19   ; #XM  SIMD Floating-Point
isr_no_err 20   ; #VE  Virtualization
isr_no_err 21   ; #CP  Control Protection
isr_no_err 22
isr_no_err 23
isr_no_err 24
isr_no_err 25
isr_no_err 26
isr_no_err 27
isr_no_err 28   ; #HV  Hypervisor Injection
isr_no_err 29   ; #VC  VMM Communication
isr_no_err 30   ; #SX  Security Exception
isr_no_err 31   ;      Reserved


; ─── IRQ stubs (vectors 32-47) ───────────────────────────────────────────────
;
; Each stub pushes the IRQ number (0-15, not the vector) and jumps to
; irq_common.  irq_common handles EOI and IRET so these never call isr_common.
;
; Stack on entry to irq_common:
;   [esp+ 0] IRQ number (0-15)
;   [esp+ 4] EIP    (CPU)
;   [esp+ 8] CS     (CPU)
;   [esp+12] EFLAGS (CPU)

%macro irq_stub 1
irq_%1:
    push dword %1
    jmp irq_common
%endmacro

irq_stub  0     ; IRQ0  Timer (PIT ch.0)
irq_stub  1     ; IRQ1  PS/2 Keyboard
irq_stub  2     ; IRQ2  Cascade (slave PIC)
irq_stub  3     ; IRQ3  COM2
irq_stub  4     ; IRQ4  COM1
irq_stub  5     ; IRQ5  LPT2 / Sound
irq_stub  6     ; IRQ6  Floppy
irq_stub  7     ; IRQ7  LPT1 / spurious master
irq_stub  8     ; IRQ8  RTC
irq_stub  9     ; IRQ9  ACPI / redirected IRQ2
irq_stub 10     ; IRQ10 open
irq_stub 11     ; IRQ11 open
irq_stub 12     ; IRQ12 PS/2 Mouse
irq_stub 13     ; IRQ13 FPU / coprocessor
irq_stub 14     ; IRQ14 ATA Primary
irq_stub 15     ; IRQ15 ATA Secondary / spurious slave


; ─── Common CPU exception handler ────────────────────────────────────────────
;
; pushad saves the exception-time register values immediately — dbg_dump_frame
; is then passed our EBP so it shows what was live when the fault fired.
;
; Full stack frame after pushad (EBP = ESP):
;   [ebp+ 0] EDI      [ebp+ 4] ESI
;   [ebp+ 8] EBP(exc) [ebp+12] ESP(exc)
;   [ebp+16] EBX      [ebp+20] EDX
;   [ebp+24] ECX      [ebp+28] EAX
;   [ebp+32] vector   [ebp+36] error code
;   [ebp+40] EIP      [ebp+44] CS
;   [ebp+48] EFLAGS

isr_common:
    pushad
    mov ebp, esp

    ; "CPU Exception XX : <name>" — vector in red, name in normal color
    mov al, DBG_ATTR_ERR
    call vga_set_attr
    mov esi, str_exc_hdr
    call vga_print_string
    mov eax, [ebp+32]
    call dbg_hex8
    mov esi, str_exc_sep
    call vga_print_string
    mov al, DBG_ATTR_NORMAL
    call vga_set_attr

    mov ecx, [ebp+32]
    cmp ecx, 32
    jae .unknown
    mov esi, [exc_names + ecx*4]
    jmp .print_name
.unknown:
    mov esi, str_exc_unknown
.print_name:
    call vga_print_line

    ; Error code — skip if zero
    mov eax, [ebp+36]
    test eax, eax
    jz .no_errcode
    mov esi, str_errcode
    call vga_print_string
    call dbg_hex32
    call vga_newline
.no_errcode:

    ; EIP at fault
    mov esi, str_eip
    call vga_print_string
    mov eax, [ebp+40]
    call dbg_hex32
    call vga_newline

    ; #PF (14): CR2 holds the faulting linear address
    mov ecx, [ebp+32]
    cmp ecx, 14
    jne .no_cr2
    mov esi, str_cr2
    call vga_print_string
    mov eax, cr2
    call dbg_hex32
    call vga_newline
.no_cr2:

    call dbg_dump_frame     ; EBP already points to the pushad frame

.halt:
    cli
    hlt
    jmp .halt


; ─── Common IRQ handler ───────────────────────────────────────────────────────
;
; Dispatches through irq_handlers[], sends EOI, then returns with IRET.
;
; Calling convention for entries in irq_handlers[]:
;   - Called with no arguments (IRQ number is at [esp+32] if needed, but
;     the handler should read it from the table index, not the stack).
;   - No register save required: irq_common's pushad/popad handles that.
;   - Must return with RET (not IRET — irq_common does the IRET).
;
; Stack after pushad:
;   [esp+32] IRQ number (0-15)    ← pushed by stub
;   [esp+36] EIP                  ← CPU
;   [esp+40] CS                   ← CPU
;   [esp+44] EFLAGS               ← CPU

irq_common:
    pushad

    mov eax, [esp+32]           ; IRQ number
    call [irq_handlers + eax*4] ; dispatch to registered handler

    mov eax, [esp+32]           ; reload — handler may have clobbered EAX
    call pic_eoi                ; send EOI to the correct PIC(s)

    popad
    add esp, 4                  ; discard the IRQ number pushed by the stub
    iret


; Default IRQ handler — just returns so irq_common can send EOI.
irq_default:
    ret


; ─── IDT management ──────────────────────────────────────────────────────────

; Install one 32-bit interrupt gate descriptor into the IDT.
; Input: EAX = vector (0-255), ECX = handler address.
; Clobbers: nothing.
set_idt_gate:
    push eax
    push ecx
    push edi

    imul edi, eax, 8
    add edi, idt_table

    mov word [edi],   cx        ; offset[0:15]
    mov word [edi+2], 0x08      ; CS selector — our flat code segment
    mov byte [edi+4], 0         ; reserved
    mov byte [edi+5], 0x8E      ; P=1 DPL=0 type=E (32-bit interrupt gate; clears IF on entry)
    shr ecx, 16
    mov word [edi+6], cx        ; offset[16:31]

    pop edi
    pop ecx
    pop eax
    ret


; Populate IDT entries 0-31 (exceptions) and 32-47 (IRQs), then load IDTR.
; Vectors 48-255 remain zero — any hit will triple-fault until handlers are installed.
load_idt:
    push eax
    push ecx
    push esi

    ; Exceptions: vectors 0-31
    xor eax, eax
    mov esi, isr_table
.fill_exc:
    cmp eax, 32
    je .fill_irq
    mov ecx, [esi]
    call set_idt_gate
    add esi, 4
    inc eax
    jmp .fill_exc

    ; IRQs: vectors 32-47
.fill_irq:
    mov esi, irq_table
.fill_irq_loop:
    cmp eax, 48
    je .done
    mov ecx, [esi]
    call set_idt_gate
    add esi, 4
    inc eax
    jmp .fill_irq_loop

.done:
    lidt [idt_descriptor]

    pop esi
    pop ecx
    pop eax
    ret


section .data

; Exception stub pointer table (vectors 0-31).
isr_table:
    dd isr_0,  isr_1,  isr_2,  isr_3,  isr_4,  isr_5,  isr_6,  isr_7
    dd isr_8,  isr_9,  isr_10, isr_11, isr_12, isr_13, isr_14, isr_15
    dd isr_16, isr_17, isr_18, isr_19, isr_20, isr_21, isr_22, isr_23
    dd isr_24, isr_25, isr_26, isr_27, isr_28, isr_29, isr_30, isr_31

; IRQ stub pointer table (IRQs 0-15, installed at vectors 32-47).
irq_table:
    dd irq_0,  irq_1,  irq_2,  irq_3,  irq_4,  irq_5,  irq_6,  irq_7
    dd irq_8,  irq_9,  irq_10, irq_11, irq_12, irq_13, irq_14, irq_15

; IRQ dispatch table — write a function pointer here to install a handler.
; All entries initialised to irq_default (bare ret).
; Contract: handler takes no args, returns with ret, need not save registers.
irq_handlers:
    times 16 dd irq_default

; Exception name lookup table.
exc_names:
    dd exc_0,  exc_1,  exc_2,  exc_3,  exc_4,  exc_5,  exc_6,  exc_7
    dd exc_8,  exc_9,  exc_10, exc_11, exc_12, exc_13, exc_14, exc_15
    dd exc_16, exc_17, exc_18, exc_19, exc_20, exc_21, exc_22, exc_23
    dd exc_24, exc_25, exc_26, exc_27, exc_28, exc_29, exc_30, exc_31

exc_0:  db "#DE Divide Error", 0
exc_1:  db "#DB Debug", 0
exc_2:  db "NMI", 0
exc_3:  db "#BP Breakpoint", 0
exc_4:  db "#OF Overflow", 0
exc_5:  db "#BR Bound Range Exceeded", 0
exc_6:  db "#UD Invalid Opcode", 0
exc_7:  db "#NM Device Not Available", 0
exc_8:  db "#DF Double Fault", 0
exc_9:  db "Coprocessor Segment Overrun", 0
exc_10: db "#TS Invalid TSS", 0
exc_11: db "#NP Segment Not Present", 0
exc_12: db "#SS Stack-Segment Fault", 0
exc_13: db "#GP General Protection", 0
exc_14: db "#PF Page Fault", 0
exc_15: db "Reserved", 0
exc_16: db "#MF x87 Floating-Point", 0
exc_17: db "#AC Alignment Check", 0
exc_18: db "#MC Machine Check", 0
exc_19: db "#XM SIMD Floating-Point", 0
exc_20: db "#VE Virtualization", 0
exc_21: db "#CP Control Protection", 0
exc_22: db "Reserved", 0
exc_23: db "Reserved", 0
exc_24: db "Reserved", 0
exc_25: db "Reserved", 0
exc_26: db "Reserved", 0
exc_27: db "Reserved", 0
exc_28: db "#HV Hypervisor Injection", 0
exc_29: db "#VC VMM Communication", 0
exc_30: db "#SX Security Exception", 0
exc_31: db "Reserved", 0

str_exc_hdr:     db "CPU Exception ", 0
str_exc_sep:     db " : ", 0
str_exc_unknown: db "Unknown", 0
str_errcode:     db "  Error Code  0x", 0
str_eip:         db "  EIP         0x", 0
str_cr2:         db "  CR2 (fault) 0x", 0

; IDT: 256 × 8-byte descriptors, zero-filled — load_idt populates 0-47 at runtime.
align 8
idt_table:
    times 256 * 8 db 0

; IDTR operand: 2-byte limit || 4-byte linear base.
idt_descriptor:
    dw 256 * 8 - 1
    dd idt_table
