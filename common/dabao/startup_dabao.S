/* common/dabao/startup_dabao.S
 * Minimal bare-metal startup for the Baochip-1x "Dabao" board
 * (VexRiscv, RV32IMAC, machine mode).
 *
 * How we get here
 * ---------------
 * boot0 → boot1 → this image. boot1 checks the Ed25519ph signature of the
 * baremetal slot at 0x60060000 and jumps into it with:
 *   • interrupts masked (mstatus.MIE = 0, mie.MEIE = 0, VexRiscv MIM = 0)
 *   • PLL locked, CPU clock (ACLK) at 350 MHz, SRAM trimmed for it
 *   • UART2 on PB13 (RX) / PB14 (TX) at 1 Mbaud, 8N1
 *   • mtvec pointing into boot1, a0/a1 holding loader arguments we ignore
 *
 * Differences vs the QEMU / ESP32 startups:
 *   • Execute in place. Nothing loads us into RAM, so .data has to be copied
 *     from RRAM to SRAM here, before .bss is cleared.
 *   • Two entry addresses (see dabao.ld): boot1 < 0.10.2 enters at the
 *     signature block's trampoline and lands on the header below;
 *     boot1 >= 0.10.2 jumps directly to _start at image + 0x400.
 *   • No F/D extension — do NOT touch mstatus.FS.
 *   • No watchdog is armed by boot0/boot1 on the Dabao, so there is none to
 *     disable.
 */

    .section .text.entry, "ax", @progbits

/* -----------------------------------------------------------------------
 * 256-byte entry header at 0x60060300.
 * First word must be exactly `jal x0, 0x100` (0x1000006f); the rest is
 * padding so that _start is at image base + 0x400. dabao.ld asserts this.
 * ----------------------------------------------------------------------- */
    .option push
    .option norvc
    .global  _entry_header
_entry_header:
    j    _start
    .option pop
    .space 252, 0

    .global  _start
    .type    _start, @function

_start:
    /* boot1 already masked everything; make sure, in case of other loaders */
    csrci mstatus, 0x8          /* MIE = 0                                */
    csrw  mie, zero
    csrw  0xBC0, zero           /* VexRiscv external-interrupt mask (MIM) */

    la   t0, _trap_handler
    csrw mtvec, t0

    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    la   sp, __stack_top

    /* Copy .data from its load address in RRAM to SRAM */
    la   a0, __data_load__
    la   a1, __data_start__
    la   a2, __data_end__
    bgeu a1, a2, .Ldata_done
.Ldata_loop:
    lw   t0, 0(a0)
    sw   t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    bltu a1, a2, .Ldata_loop
.Ldata_done:

    /* Zero-initialise BSS */
    la   a0, __bss_start__
    la   a1, __bss_end__
    bgeu a0, a1, .Lbss_done
.Lbss_loop:
    sw   zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, .Lbss_loop
.Lbss_done:

    call __libc_init_array

    li   a0, 0
    li   a1, 0
    call main

    call _exit                  /* a0 = main's return value */

.Lhang:
    j    .Lhang

    .size _start, . - _start


/* -----------------------------------------------------------------------
 * Trap handler — any trap is fatal (interrupts are never enabled).
 *
 * The console is a UDMA UART, which transmits by DMA from a buffer and so
 * cannot be driven with a couple of `sb` instructions like the NS16550 or
 * ESP32 UARTs. Hand over to C instead: hal_trap() in hal-dabao.c prints
 *   !TRAP mcause=XXXXXXXX mepc=XXXXXXXX mtval=XXXXXXXX
 * and halts. We never return, so gp is reloaded and the main stack simply
 * reused from the top — that keeps the report working when the trap was
 * caused by a runaway sp, or by assembly that borrowed gp as a scratch
 * register (hence norelax: no gp-relative addressing in here).
 * ----------------------------------------------------------------------- */
    .section .text, "ax", @progbits
    .global  _trap_handler
    .type    _trap_handler, @function
    .align   2

_trap_handler:
    .option push
    .option norelax
    la   gp, __global_pointer$
    la   sp, __stack_top
    .option pop
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call hal_trap
.Ltrap_hang:
    j    .Ltrap_hang

    .size _trap_handler, . - _trap_handler
