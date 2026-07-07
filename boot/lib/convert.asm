bits 16

global hex_to_ascii

section .text

; Convert a nibble to an uppercase ASCII hex digit.
; Input:  AL = value (0–15)
; Output: AL = '0'–'9' or 'A'–'F'
hex_to_ascii:
    cmp al, 10
    jb .digit
    add al, 'A' - 10
    ret
.digit:
    add al, '0'
    ret
