/*
 * aOS kernel linker script.
 *
 * The kernel is a static-PIE (ET_DYN) linked at the top 2 GiB of the address
 * space. Limine sees the PT_DYNAMIC segment, treats the image as relocatable,
 * and with `kaslr: yes` slides it by a random multiple of the largest segment
 * alignment (4 KiB here), keeping it inside the top 2 GiB, and applies the
 * relocations itself.
 *
 * One PT_LOAD per permission, so the kernel can later map text RX,
 * rodata R and data RW+NX exactly (phase 1.2).
 */
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(kmain)

PHDRS
{
    limine_requests PT_LOAD;
    text            PT_LOAD;
    rodata          PT_LOAD;
    data            PT_LOAD;
    dynamic         PT_DYNAMIC;
}

SECTIONS
{
    . = 0xffffffff80000000;
    __kernel_start = .;

    /* Limine scans this region for requests between the two markers. */
    .limine_requests : {
        KEEP(*(.requests_start_marker))
        KEEP(*(.requests))
        KEEP(*(.requests_end_marker))
    } :limine_requests

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .text : {
        __text_start = .;
        *(.text .text.*)
        __text_end = .;
    } :text

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .rodata : {
        *(.rodata .rodata.*)
    } :rodata
    /* Dynamic-linking metadata must sit inside a PT_LOAD: Limine reads the
       relocations through the program headers when it applies the slide. */
    .dynsym   : { *(.dynsym) }   :rodata
    .dynstr   : { *(.dynstr) }   :rodata
    .gnu.hash : { *(.gnu.hash) } :rodata
    .hash     : { *(.hash) }     :rodata
    .rela.dyn : { *(.rela.dyn .rela.*) } :rodata

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .data : {
        *(.data .data.*)
    } :data
    .got : { *(.got .got.*) } :data
    .dynamic : { *(.dynamic) } :data :dynamic
    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    } :data

    __kernel_end = .;

    /DISCARD/ : {
        *(.eh_frame*)
        *(.note .note.*)
        *(.interp)
    }
}
