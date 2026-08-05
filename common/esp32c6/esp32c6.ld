/* common/esp32c6/esp32c6.ld
 * Linker script for ESP32-C6 bare-metal applications (HP core).
 *
 * ── Memory map (ESP32-C6 HP core, from TRM) ───────────────────────────────
 *
 *  HP SRAM (unified — same physical memory for code and data):
 *    0x40800000 – 0x4087FFFF  (512 KB total)
 *
 *  Unlike ESP32-C3 (which has separate IRAM/DRAM bus addresses for the same
 *  SRAM), the C6 HP core uses a single unified address range.  Both
 *  instruction fetch and data loads use 0x40800000.
 *
 *  Peripherals: 0x60000000+
 *  LP core:     separate subsystem, not addressed here
 *
 * ── Size budget (448 KB conservative, leaving 64 KB for ROM scratch) ──────
 *  More headroom than C3 — all ML-KEM and ML-DSA variants fit comfortably.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

STACK_SIZE = 0x8000;    /* 32 KiB */

MEMORY {
    /* 448 KB out of 512 KB; top 64 KB reserved for ROM scratch usage */
    sram (rwx) : ORIGIN = 0x40800000, LENGTH = 448K
}

SECTIONS
{
    . = ORIGIN(sram);

    .text.entry : {
        KEEP(*(.text.entry))
    } > sram

    .text : {
        . = ALIGN(4);
        *(.text .text.*)
        *(.rodata .rodata.*)
        KEEP(*(.init))
        KEEP(*(.fini))
        . = ALIGN(4);
    } > sram

    .preinit_array : {
        . = ALIGN(4);
        PROVIDE(__preinit_array_start = .);
        KEEP(*(.preinit_array))
        PROVIDE(__preinit_array_end = .);
    } > sram

    .init_array : {
        . = ALIGN(4);
        PROVIDE(__init_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE(__init_array_end = .);
    } > sram

    .fini_array : {
        . = ALIGN(4);
        PROVIDE(__fini_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
        KEEP(*(.fini_array))
        PROVIDE(__fini_array_end = .);
    } > sram

    .data : {
        . = ALIGN(4);
        __data_start__ = .;
        *(.sdata .sdata.*)
        *(.data  .data.*)
        . = ALIGN(4);
        __data_end__ = .;
    } > sram

    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start__ = .;
        *(.sbss .sbss.*)
        *(.bss  .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > sram

    . = ALIGN(16);
    __end__ = .;
    PROVIDE(end = .);

    __stack_top = ORIGIN(sram) + LENGTH(sram);

    __global_pointer$ = MIN(__data_start__ + 0x800,
                            MAX(__data_start__, __bss_end__ - 0x800));

    ASSERT(__bss_end__ + STACK_SIZE <= __stack_top,
           "Not enough SRAM: increase LENGTH in esp32c6.ld")
}
