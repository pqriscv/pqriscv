/* common/dabao/dabao.ld
 * Linker script for bare-metal applications on the Baochip-1x "Dabao" board.
 *
 * ── Memory map (Baochip-1x) ───────────────────────────────────────────────
 *
 *  RRAM (non-volatile, execute in place), 4 MiB @ 0x60000000:
 *    0x60000000  boot0            immutable root of trust
 *    0x60020000  boot1            USB/UF2 loader, verifies the next stage
 *    0x60060000  loader/baremetal slot  ← this image
 *    0x603DA000  one-way counters, key slots (never touch)
 *
 *  SRAM, 2 MiB @ 0x61000000      .data, .bss, heap, stack
 *  IFRAM0/1, 2 x 128 KiB @ 0x50000000   the only memory UDMA can reach;
 *                                the HAL uses the first 256 bytes of IFRAM0
 *                                as UART TX buffer, nothing is linked here
 *
 * ── Image layout in the baremetal slot ────────────────────────────────────
 *
 *    0x60060000  signature block, 768 bytes. NOT produced by the linker:
 *                scripts/bao1x_image.py prepends it. Its first word is a
 *                `jal x0, 0x300` that hops over the block.
 *    0x60060300  256-byte entry header: `jal x0, 0x100` + zero padding
 *                (startup_dabao.S, section .text.entry)
 *    0x60060400  _start
 *
 * Both hops exist because boot1 changed where it enters the image:
 *   boot1 <  0.10.2 jumps to 0x60060000 and runs the two trampolines;
 *   boot1 >= 0.10.2 jumps straight to 0x60060400 (so that the first
 *                   instruction executed is inside the signed region).
 * This is the same layout xous-core's own baremetal target uses (there the
 * 256-byte header holds its StaticsInRom table), so one image boots on both.
 *
 * Unlike the QEMU and ESP32 targets nothing copies this image to RAM for us:
 * code and constants stay in RRAM, and startup_dabao.S copies .data from its
 * load address in RRAM to SRAM before main().
 *
 * ── Size budget ───────────────────────────────────────────────────────────
 * 1 MiB of RRAM for the image (signature block included). boot1 would accept
 * more, but every scheme here needs well under 300 KiB, and each 256-byte
 * page costs a write cycle on every flash.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

STACK_SIZE = 0x10000;   /* 64 KiB — link-time floor only; the stack grows
                           down from the top of SRAM towards the heap */

MEMORY {
    /* 0x300 = the signature block that scripts/bao1x_image.py prepends */
    rram (rx)  : ORIGIN = 0x60060000 + 0x300, LENGTH = 1M - 0x300
    sram (rwx) : ORIGIN = 0x61000000,         LENGTH = 2M
}

SECTIONS
{
    /* Entry header, then _start at exactly image base + 0x400. */
    .text.entry : {
        KEEP(*(.text.entry))
    } > rram

    .text : {
        . = ALIGN(4);
        *(.text .text.*)
        KEEP(*(.init))
        KEEP(*(.fini))
        . = ALIGN(4);
    } > rram

    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        . = ALIGN(4);
    } > rram

    /* Constructor/destructor tables are only ever read: keep them in RRAM. */
    .preinit_array : {
        . = ALIGN(4);
        PROVIDE(__preinit_array_start = .);
        KEEP(*(.preinit_array))
        PROVIDE(__preinit_array_end = .);
    } > rram

    .init_array : {
        . = ALIGN(4);
        PROVIDE(__init_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE(__init_array_end = .);
    } > rram

    .fini_array : {
        . = ALIGN(4);
        PROVIDE(__fini_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
        KEEP(*(.fini_array))
        PROVIDE(__fini_array_end = .);
        . = ALIGN(4);
    } > rram

    /* Initialised data: runs from SRAM, stored in RRAM right after the
     * sections above. startup_dabao.S copies __data_load__ → __data_start__. */
    .data : ALIGN(4) {
        __data_start__ = .;
        *(.sdata .sdata.*)  /* GP-relative small data — must come first */
        *(.data  .data.*)
        . = ALIGN(4);
        __data_end__ = .;
    } > sram AT > rram

    __data_load__ = LOADADDR(.data);

    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start__ = .;
        *(.sbss .sbss.*)    /* GP-relative small BSS */
        *(.bss  .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end__ = .;
    } > sram

    /* Heap begins immediately after BSS */
    . = ALIGN(16);
    __end__ = .;
    PROVIDE(end = .);   /* _sbrk anchor — matches __wrap__sbrk in the HAL */

    /* Stack at the very top of SRAM (grows downward) */
    __stack_top = ORIGIN(sram) + LENGTH(sram);

    /* GP relaxation anchor: within ±2 KiB of both .sdata and .sbss */
    __global_pointer$ = MIN(__data_start__ + 0x800,
                            MAX(__data_start__, __bss_end__ - 0x800));

    /* End of what gets written to RRAM (signature block excluded) */
    __image_end__ = __data_load__ + SIZEOF(.data);

    ASSERT(_start == ORIGIN(rram) + 0x100,
           "_start must sit at image base + 0x400: boot1 >= 0.10.2 jumps there")
    ASSERT(__image_end__ <= ORIGIN(rram) + LENGTH(rram),
           "Image too large for the RRAM budget in dabao.ld")
    ASSERT(__bss_end__ + STACK_SIZE <= __stack_top,
           "Not enough SRAM: .data + .bss + stack do not fit")
}
