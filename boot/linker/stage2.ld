SECTIONS
{
    . = 0x8000;

    .text : {
        */stage2.o (.text)      /* Entry point must come first */
        *(.text)
    }

    .data : {
        *(.data)
        *(.rodata)
    }

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
