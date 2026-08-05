/*
 * virt.ld — Linker script for QEMU RISC-V 32 "virt" machine
 *
 * QEMU "virt" memory map (relevant entries):
 *   0x00100000  SiFive test device (power-off / pass / fail)
 *   0x10000000  NS16550A UART
 *   0x80000000  DRAM — 128 MiB, this is where we run
 *
 * QEMU loads the ELF/binary at 0x80000000 and jumps to the entry point
 * when invoked with: -bios none -kernel <file>
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

STACK_SIZE = 0x4000;    /* 16 KiB — adjust as needed */

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS
{
    . = ORIGIN(RAM);

    /* ------------------------------------------------------------------
     * .text.entry MUST be the very first section in the binary so that
     * _start sits at 0x80000000 (the QEMU boot address).
     * ------------------------------------------------------------------ */
    .text.entry : {
        KEEP(*(.text.entry))
    } > RAM

    .text : {
        . = ALIGN(4);
        *(.text .text.*)
        *(.rodata .rodata.*)
        KEEP(*(.init))
        KEEP(*(.fini))
        . = ALIGN(4);
    } > RAM

    /* C++ / newlib constructor & destructor arrays */
    .preinit_array : {
        . = ALIGN(4);
        PROVIDE(__preinit_array_start = .);
        KEEP(*(.preinit_array))
        PROVIDE(__preinit_array_end = .);
    } > RAM

    .init_array : {
        . = ALIGN(4);
        PROVIDE(__init_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE(__init_array_end = .);
    } > RAM

    .fini_array : {
        . = ALIGN(4);
        PROVIDE(__fini_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
        KEEP(*(.fini_array))
        PROVIDE(__fini_array_end = .);
    } > RAM

    .data : {
        . = ALIGN(4);
        __data_start__ = .;
        *(.sdata .sdata.*)  /* GP-relative small data — must come first */
        *(.data  .data.*)
        . = ALIGN(4);
        __data_end__ = .;
    } > RAM

    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start__ = .;
        *(.sbss .sbss.*)    /* GP-relative small BSS */
        *(.bss  .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > RAM

    /* Heap begins immediately after BSS (mirroring the ARM/MPS2 layout) */
    . = ALIGN(16);
    __end__ = .;
    PROVIDE(end = .);   /* newlib _sbrk anchor — matches __wrap__sbrk in hal */

    /* Stack at the very top of RAM (grows downward) */
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /* GP relaxation anchor: within ±2 KiB of both .sdata and .sbss */
    __global_pointer$ = MIN(__data_start__ + 0x800,
                            MAX(__data_start__, __bss_end__ - 0x800));

    /* Safety check */
    ASSERT(__bss_end__ + STACK_SIZE <= __stack_top,
           "Not enough RAM: heap + stack overflow")
}
