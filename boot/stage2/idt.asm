bits 32

global load_idt

extern vga_set_attr
extern vga_print_string
extern vga_print_line
extern vga_newline
extern dbg_hex8
extern dbg_hex32
extern dbg_dump_frame

DBG_ATTR_NORMAL equ 0x07
DBG_ATTR_ERR    equ 0x0C

; ─── ISR stubs ────────────────────────────────────────────────────────────────
;
; CPU exceptions that do NOT push an error code: we push a dummy 0 first so
; isr_common always sees the same stack layout regardless of exception type.
;
; Normalized frame on entry to isr_common (lowest address first):
;   [esp+ 0] vector number
;   [esp+ 4] error code  (0 for exceptions that don't have one)
;   [esp+ 8] EIP         (pushed by CPU)
;   [esp+12] CS          (pushed by CPU)
;   [esp+16] EFLAGS      (pushed by CPU)

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
isr_err     8   ; #DF  Double Fault           (error code = 0, always)
isr_no_err  9   ;      Coprocessor Segment Overrun (legacy, no error code)
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
isr_no_err 22   ;      Reserved
isr_no_err 23   ;      Reserved
isr_no_err 24   ;      Reserved
isr_no_err 25   ;      Reserved
isr_no_err 26   ;      Reserved
isr_no_err 27   ;      Reserved
isr_no_err 28   ; #HV  Hypervisor Injection
isr_no_err 29   ; #VC  VMM Communication
isr_no_err 30   ; #SX  Security Exception
isr_no_err 31   ;      Reserved


; ─── Common exception handler ─────────────────────────────────────────────────
;
; All ISR stubs jump here.  pushad saves the exception-time register values
; immediately so dbg_dump_frame shows what was live when the fault fired.
;
; Full stack frame after pushad (EBP = ESP):
;   [ebp+ 0] EDI      [ebp+ 4] ESI        ← pushad save area
;   [ebp+ 8] EBP(exc) [ebp+12] ESP(exc)
;   [ebp+16] EBX      [ebp+20] EDX
;   [ebp+24] ECX      [ebp+28] EAX
;   [ebp+32] vector   [ebp+36] error code  ← stubs
;   [ebp+40] EIP      [ebp+44] CS          ← CPU
;   [ebp+48] EFLAGS                        ← CPU

isr_common:
    pushad
    mov ebp, esp

    ; Print "CPU Exception XX : <name>" with the vector in red
    mov al, DBG_ATTR_ERR
    call vga_set_attr
    mov esi, str_exc_hdr
    call vga_print_string       ; "CPU Exception "
    mov eax, [ebp+32]
    call dbg_hex8               ; two-digit vector number
    mov esi, str_exc_sep
    call vga_print_string       ; " : "
    mov al, DBG_ATTR_NORMAL
    call vga_set_attr

    ; Look up exception name by vector
    mov ecx, [ebp+32]
    cmp ecx, 32
    jae .unknown
    mov esi, [exc_names + ecx*4]
    jmp .print_name
.unknown:
    mov esi, str_exc_unknown
.print_name:
    call vga_print_line

    ; Error code (skip if zero — most faults with error codes have non-zero ones)
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

    ; For #PF (vector 14) also show CR2 (the faulting linear address)
    mov ecx, [ebp+32]
    cmp ecx, 14
    jne .no_cr2
    mov esi, str_cr2
    call vga_print_string
    mov eax, cr2
    call dbg_hex32
    call vga_newline
.no_cr2:

    ; Register dump — EBP already points to the pushad frame so
    ; dbg_dump_frame shows the exception-time values directly.
    call dbg_dump_frame

.halt:
    cli
    hlt
    jmp .halt


; ─── IDT management ──────────────────────────────────────────────────────────

; Install one 32-bit interrupt gate into the IDT.
; Input: EAX = vector (0-255), ECX = handler address.
; Clobbers: nothing.
set_idt_gate:
    push eax
    push ecx
    push edi

    imul edi, eax, 8
    add edi, idt_table

    mov word [edi],   cx        ; offset[0:15]
    mov word [edi+2], 0x08      ; code segment selector
    mov byte [edi+4], 0         ; reserved
    mov byte [edi+5], 0x8E      ; P=1 DPL=0 type=E (32-bit interrupt gate)
    shr ecx, 16
    mov word [edi+6], cx        ; offset[16:31]

    pop edi
    pop ecx
    pop eax
    ret


; Populate IDT entries 0-31 with the exception stubs and load IDTR.
; Vectors 32-255 are left as zero (any hit triple-faults until we add them).
load_idt:
    push eax
    push ecx
    push esi

    xor eax, eax
    mov esi, isr_table
.fill:
    cmp eax, 32
    je .done
    mov ecx, [esi]          ; stub address from the pointer table
    call set_idt_gate
    add esi, 4
    inc eax
    jmp .fill
.done:
    lidt [idt_descriptor]

    pop esi
    pop ecx
    pop eax
    ret


section .data

; Stub pointer table — load_idt iterates this to populate the IDT.
; Using a runtime loop avoids the R_386_HI16 relocation problems that
; arise when trying to split label addresses in static IDT data.
isr_table:
    dd isr_0,  isr_1,  isr_2,  isr_3,  isr_4,  isr_5,  isr_6,  isr_7
    dd isr_8,  isr_9,  isr_10, isr_11, isr_12, isr_13, isr_14, isr_15
    dd isr_16, isr_17, isr_18, isr_19, isr_20, isr_21, isr_22, isr_23
    dd isr_24, isr_25, isr_26, isr_27, isr_28, isr_29, isr_30, isr_31

; Exception name lookup table, indexed by vector number.
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

; IDT: 256 * 8-byte descriptors, zeroed — entries are filled at runtime by load_idt.
align 8
idt_table:
    times 256 * 8 db 0

; IDTR operand: 2-byte limit + 4-byte linear base address
idt_descriptor:
    dw 256 * 8 - 1
    dd idt_table
