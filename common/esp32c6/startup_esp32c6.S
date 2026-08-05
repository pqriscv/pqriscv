/* common/esp32c6/startup_esp32c6.S
 * Minimal bare-metal startup for ESP32-C6 HP core (RISC-V RV32IMAC).
 *
 * Identical in structure to startup_esp32c3.S.
 * Differences vs C3:
 *   • ARCH: RV32IMAC (has A extension; still no F/D — do NOT touch mstatus.FS)
 *   • UART0 is at the same address (0x60000000) with the same register layout
 *   • HP SRAM is unified (code + data live at 0x40800000)
 *   • The ROM bootloader for C6 follows the same ESP image loading protocol
 *
 * This file is intentionally kept as a separate copy (not #included) so that
 * chip-specific tweaks (e.g. cache/WDT init) can diverge without #ifdefs.
 */

    .section .text.entry, "ax", @progbits
    .global  _start
    .type    _start, @function

_start:
    la   t0, _trap_handler
    csrw mtvec, t0

    csrw mie, zero

    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    la   sp, __stack_top

    la   a0, __bss_start__
    la   a1, __bss_end__
    bgeu a0, a1, .Lbss_done
.Lbss_loop:
    sw   zero, 0(a0)
    addi a0,   a0, 4
    bltu a0,   a1, .Lbss_loop
.Lbss_done:
     # Disable TG0 WDT @ 0x60008000
    li      t0, 0x60008000
    li      t1, 0x50D83AA1
    sw      t1, 0x64(t0)          # unlock
    sw      zero, 0x48(t0)        # clear CONFIG0 (disable)
    sw      zero, 0x64(t0)        # lock

    # Disable TG1 WDT @ 0x60009000
    li      t0, 0x60009000
    li      t1, 0x50D83AA1
    sw      t1, 0x64(t0)
    sw      zero, 0x48(t0)
    sw      zero, 0x64(t0)

    # Disable LP_WDT (RWDT) @ 0x600B1C00
    li      t0, 0x600B1C00
    li      t1, 0x50D83AA1
    sw      t1, 0x18(t0)          # unlock RWDT
    sw      zero, 0x00(t0)        # clear CONFIG0 (disable)
    sw      zero, 0x18(t0)        # lock

    # Disable LP Super-WDT (SWD) — same base, different protect reg
    li      t1, 0x50D83AA1
    sw      t1, 0x20(t0)          # unlock SWD
    lw      t1, 0x1C(t0)          # read SWD CONFIG
    li      t2, (1 << 18)         # AUTO_FEED_EN bit
    or      t1, t1, t2            # set the bit
    sw      t1, 0x1C(t0)          # write back
    sw      zero, 0x20(t0)        # lock
    
    call __libc_init_array

    li   a0, 0
    li   a1, 0
    call main

    call _exit

.Lhang:
    j    .Lhang

    .size _start, . - _start


    .section .text, "ax", @progbits
    .global  _trap_handler
    .type    _trap_handler, @function
    .align   2

_trap_handler:
    li   t6, 0x60000000

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

    j    .

_print_hex32:
    li   t3, 28
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
