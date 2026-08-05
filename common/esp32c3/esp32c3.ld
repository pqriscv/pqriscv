/* common/esp32c3/esp32c3.ld
 * Linker script for ESP32-C3 bare-metal applications.
 *
 * ── Memory map (ESP32-C3, from TRM Chapter 1) ─────────────────────────────
 *
 *  IRAM (code/RW, physical SRAM0):
 *    0x4037C000 – 0x403DFFFF  (~384 KB, Instruction-bus view)
 *    Same physical bytes also accessible as data at:
 *    0x3FC80000 – 0x3FCFFFFF  (Data-bus view, alias)
 *
 *  Peripherals: 0x60000000+
 *  ROM:         0x40000000   (read-only; ROM bootloader code)
 *
 * ── Strategy ──────────────────────────────────────────────────────────────
 * Place EVERYTHING (code + data + stack) in the IRAM region (code-bus view)
 * so that instruction fetch and data loads use the same physical addresses.
 * This avoids the VMA/LMA copy dance: the ROM bootloader copies each ELF
 * PT_LOAD segment directly to its p_vaddr, so we only need correct VMAs.
 *
 * Heap starts at &end (top of BSS) and grows upward.
 * Stack sits at __stack_top (top of our IRAM allocation) and grows downward.
 *
 * ── Size budget (320 KB conservative, leaving ~64 KB for ROM scratch) ─────
 *  ML-KEM-512 code + data: ~120 KB  →  fits easily
 *  ML-KEM-1024:            ~140 KB  →  fits
 *  ML-DSA-87:              ~200 KB  →  fits (stack at 32 KB leaves margin)
 *
 * ── Bump limit if needed ──────────────────────────────────────────────────
 * Increase LENGTH below (up to 384K) and reduce STACK_SIZE if you run out.
 * The ASSERT at the bottom catches overflows at link time.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

STACK_SIZE = 0x8000;    /* 32 KiB — large enough for recursive hash stacks */

MEMORY {
    iram (rwx) : ORIGIN = 0x4037C000, LENGTH = 320K
}

SECTIONS
{
    . = ORIGIN(iram);

    /* ── _start must be at the very first byte ────────────────────────────── */
    .text.entry : {
        KEEP(*(.text.entry))
    } > iram

    /* ── Code and read-only data ─────────────────────────────────────────── */
    .text : {
        . = ALIGN(4);
        *(.text .text.*)
        *(.rodata .rodata.*)
        KEEP(*(.init))
        KEEP(*(.fini))
        . = ALIGN(4);
    } > iram

    /* ── C++ / newlib constructor and destructor arrays ─────────────────── */
    .preinit_array : {
        . = ALIGN(4);
        PROVIDE(__preinit_array_start = .);
        KEEP(*(.preinit_array))
        PROVIDE(__preinit_array_end = .);
    } > iram

    .init_array : {
        . = ALIGN(4);
        PROVIDE(__init_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE(__init_array_end = .);
    } > iram

    .fini_array : {
        . = ALIGN(4);
        PROVIDE(__fini_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
        KEEP(*(.fini_array))
        PROVIDE(__fini_array_end = .);
    } > iram

    /* ── Initialised data ────────────────────────────────────────────────── */
    .data : {
        . = ALIGN(4);
        __data_start__ = .;
        *(.sdata .sdata.*)   /* GP-relative small data must precede .data */
        *(.data  .data.*)
        . = ALIGN(4);
        __data_end__ = .;
    } > iram

    /* ── Zero-initialised data (NOT in flash; startup clears at runtime) ─── */
    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start__ = .;
        *(.sbss .sbss.*)
        *(.bss  .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > iram

    /* Heap anchor: newlib's _sbrk grows upward from here */
    . = ALIGN(16);
    __end__ = .;
    PROVIDE(end = .);

    /* Stack at the very top of the IRAM region (grows downward) */
    __stack_top = ORIGIN(iram) + LENGTH(iram);

    /* GP relaxation anchor: within ±2 KiB of both .sdata and .sbss */
    __global_pointer$ = MIN(__data_start__ + 0x800,
                            MAX(__data_start__, __bss_end__ - 0x800));

    /* Link-time sanity check */
    ASSERT(__bss_end__ + STACK_SIZE <= __stack_top,
           "Not enough IRAM: increase LENGTH in esp32c3.ld")
}
