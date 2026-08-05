/* common/esp32c3/startup_esp32c3.S
 * Minimal bare-metal startup for ESP32-C3 (RISC-V RV32IMC).
 *
 * By the time this code runs, the ROM bootloader has already:
 *   ✓ Enabled flash cache and loaded our code/data segments into IRAM
 *   ✓ Initialised UART0 @ 115200 baud
 *   ✓ Set CPU clock (typically 80 MHz via internal PLL)
 *   ✓ Left the CPU in M-mode with interrupts disabled
 *
 * Our job (before calling main):
 *   1. Install mtvec so unexpected traps print diagnostics
 *   2. Disable all M-mode interrupts (mie = 0) — paranoia
 *   3. Set up the global pointer (gp) for GP-relaxation
 *   4. Set the stack pointer (sp) to __stack_top (linker-defined)
 *   5. Zero-initialise the BSS section
 *   6. Run C++ / newlib global constructors (__libc_init_array)
 *   7. Call main()
 *   8. Call _exit() if main returns
 *
 * ⚠  RV32IMC — NO F or D extensions.  Do NOT touch mstatus.FS.
 *    The QEMU startup enables the F extension; we deliberately omit that
 *    here because any mstatus write with FS != 0 traps on cores without FPU.
 */

    .section .text.entry, "ax", @progbits
    .global  _start
    .type    _start, @function

_start:
    /* ── 1. Trap handler ─────────────────────────────────────────────────── */
    la   t0, _trap_handler
    csrw mtvec, t0

    /* ── 2. Disable M-mode interrupts ────────────────────────────────────── */
    csrw mie, zero

    /* ── 3. Global pointer ───────────────────────────────────────────────── */
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    /* ── 4. Stack pointer ────────────────────────────────────────────────── */
    la   sp, __stack_top

    /* ── 5. Zero BSS ─────────────────────────────────────────────────────── */
    la   a0, __bss_start__
    la   a1, __bss_end__
    bgeu a0, a1, .Lbss_done
.Lbss_loop:
    sw   zero, 0(a0)
    addi a0,   a0, 4
    bltu a0,   a1, .Lbss_loop
.Lbss_done:

    /* ── 6. Global constructors ──────────────────────────────────────────── */
    call __libc_init_array

    /* ── 7. Application entry point ──────────────────────────────────────── */
    li   a0, 0          /* argc = 0 */
    li   a1, 0          /* argv = NULL */
    call main

    /* ── 8. main() returned — call _exit with its return value ───────────── */
    /* a0 already holds main()'s return value */
    call _exit

.Lhang:
    j    .Lhang         /* should never reach here */

    .size _start, . - _start


/* ─────────────────────────────────────────────────────────────────────────────
 * Minimal trap handler
 *
 * Prints:  \r\n!TRAP mcause=XXXXXXXX mepc=XXXXXXXX\r\n
 * to UART0 and then spins.
 *
 * We write directly to the UART FIFO without FIFO-level polling because:
 *   (a) The message is ≤ 40 bytes — well within the 128-byte TX FIFO depth.
 *   (b) We cannot use the stack safely inside a trap (might be corrupt).
 *
 * Uses only t0-t6, a0, a1 (all caller-saved; no ABI damage).
 * ───────────────────────────────────────────────────────────────────────────── */
    .section .text, "ax", @progbits
    .global  _trap_handler
    .type    _trap_handler, @function
    .align   2

_trap_handler:
    li   t6, 0x60000000     /* UART0 FIFO register */

    li   a1, '\r'  ; sb a1, 0(t6)
    li   a1, '\n'  ; sb a1, 0(t6)
    li   a1, '!'   ; sb a1, 0(t6)
    li   a1, 'T'   ; sb a1, 0(t6)
    li   a1, 'R'   ; sb a1, 0(t6)
    li   a1, 'A'   ; sb a1, 0(t6)
    li   a1, 'P'   ; sb a1, 0(t6)
    li   a1, ' '   ; sb a1, 0(t6)
    li   a1, 'm'   ; sb a1, 0(t6)
    li   a1, 'c'   ; sb a1, 0(t6)
    li   a1, 'a'   ; sb a1, 0(t6)
    li   a1, 'u'   ; sb a1, 0(t6)
    li   a1, 's'   ; sb a1, 0(t6)
    li   a1, 'e'   ; sb a1, 0(t6)
    li   a1, '='   ; sb a1, 0(t6)
    csrr a0, mcause
    jal  t5, _print_hex32
    li   a1, ' '   ; sb a1, 0(t6)
    li   a1, 'm'   ; sb a1, 0(t6)
    li   a1, 'e'   ; sb a1, 0(t6)
    li   a1, 'p'   ; sb a1, 0(t6)
    li   a1, 'c'   ; sb a1, 0(t6)
    li   a1, '='   ; sb a1, 0(t6)
    csrr a0, mepc
    jal  t5, _print_hex32
    li   a1, '\r'  ; sb a1, 0(t6)
    li   a1, '\n'  ; sb a1, 0(t6)

    j    .                  /* spin forever */

/* _print_hex32: emit a0 as 8 hex digits to UART at t6.  Returns via t5. */
_print_hex32:
    li   t3, 28             /* bit-shift counter: 28, 24, …, 0 */
.Lhex_loop:
    srl  t4, a0, t3
    andi t4, t4, 0xF
    li   t2, 10
    blt  t4, t2, .Lhex_digit
    addi t4, t4, ('a' - 10)
    j    .Lhex_emit
.Lhex_digit:
    addi t4, t4, '0'
.Lhex_emit:
    sb   t4, 0(t6)
    addi t3, t3, -4
    bge  t3, zero, .Lhex_loop
    jr   t5

    .size _trap_handler, . - _trap_handler
