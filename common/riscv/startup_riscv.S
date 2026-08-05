/* startup_riscv.S
 * Minimal RISC-V 32 bare-metal startup for the QEMU "virt" machine.
 *
 * Memory layout (virt machine):
 *   0x00100000  SiFive test device  (write 0x5555=PASS, 0x3333=FAIL)
 *   0x10000000  NS16550A UART
 *   0x80000000  DRAM (128 MiB) — we are loaded here
 */

    .section .text.entry, "ax", @progbits
    .global  _start
    .type    _start, @function

_start:
    /* Install trap handler before touching anything else */
    la   t0, _trap_handler
    csrw mtvec, t0

    /* Disable all machine-mode interrupts */
    csrw mie, zero

    /* -------------------------------------------------------
     * Set up the global pointer.
     * The .option norelax pair prevents the assembler from
     * optimising this la itself via GP (which would be circular).
     * ------------------------------------------------------- */
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    /* Set up the stack pointer (grows downward from __stack_top) */
    la   sp, __stack_top

    /* -------------------------------------------------------
     * Enable the F extension (mstatus.FS = 01 = Initial).
     * QEMU virt resets with mstatus.FS = 0 (Off); any fmv.*
     * instruction with FS=Off traps as illegal.
     * MSTATUS_FS = bits [14:13] = 0x6000; write 0x2000 (= 01 << 13).
     * ------------------------------------------------------- */
    li   t0, 0x00006000     /* mask  for FS field  */
    csrc mstatus, t0        /* clear FS to 00      */
    li   t0, 0x00002000     /* FS = 01 (Initial)   */
    csrs mstatus, t0

    /* -------------------------------------------------------
     * Zero-initialise BSS
     * ------------------------------------------------------- */
    la   a0, __bss_start__
    la   a1, __bss_end__
    bgeu a0, a1, .Lbss_done
.Lbss_loop:
    sw   zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, .Lbss_loop
.Lbss_done:

    /* Run newlib/C++ global constructors */
    call __libc_init_array

    /* Jump to user code */
    li   a0, 0          /* argc = 0 */
    li   a1, 0          /* argv = NULL */
    call main

    /* -------------------------------------------------------
     * main() returned — signal PASS to QEMU and halt.
     * Writing 0x5555 to the SiFive test device causes QEMU
     * to exit with code 0.
     * ------------------------------------------------------- */
    li   t0, 0x100000
    li   t1, 0x5555
    sw   t1, 0(t0)

.Lhang:
    j    .Lhang          /* should never reach here */

    .size _start, . - _start


/* -----------------------------------------------------------------------
 * Trap handler — any unexpected exception signals FAIL and halts QEMU.
 * Writing 0x3333 to the SiFive test device exits with a non-zero code.
 * ----------------------------------------------------------------------- */
    .section .text, "ax", @progbits
    .global  _trap_handler
    .type    _trap_handler, @function
    .align   2

_trap_handler:
    /* Print "\r\n!TRAP mcause=XXXXXXXX mepc=XXXXXXXX\r\n" to UART.
     * Only clobbers t0-t6, a0, a1 — no stack needed.             */
    li   t6, 0x10000000     /* NS16550 UART base */

    li   a1, 13  ; sb a1, 0(t6)   /* \r */
    li   a1, 10  ; sb a1, 0(t6)   /* \n */
    li   a1, 33  ; sb a1, 0(t6)   /* !  */
    li   a1, 84  ; sb a1, 0(t6)   /* T  */
    li   a1, 82  ; sb a1, 0(t6)   /* R  */
    li   a1, 65  ; sb a1, 0(t6)   /* A  */
    li   a1, 80  ; sb a1, 0(t6)   /* P  */
    li   a1, 32  ; sb a1, 0(t6)   /* sp */
    li   a1, 109 ; sb a1, 0(t6)   /* m  */
    li   a1, 99  ; sb a1, 0(t6)   /* c  */
    li   a1, 97  ; sb a1, 0(t6)   /* a  */
    li   a1, 117 ; sb a1, 0(t6)   /* u  */
    li   a1, 115 ; sb a1, 0(t6)   /* s  */
    li   a1, 101 ; sb a1, 0(t6)   /* e  */
    li   a1, 61  ; sb a1, 0(t6)   /* =  */
    csrr a0, mcause
    jal  t5, _print_hex32
    li   a1, 32  ; sb a1, 0(t6)   /* sp */
    li   a1, 109 ; sb a1, 0(t6)   /* m  */
    li   a1, 101 ; sb a1, 0(t6)   /* e  */
    li   a1, 112 ; sb a1, 0(t6)   /* p  */
    li   a1, 99  ; sb a1, 0(t6)   /* c  */
    li   a1, 61  ; sb a1, 0(t6)   /* =  */
    csrr a0, mepc
    jal  t5, _print_hex32
    li   a1, 13  ; sb a1, 0(t6)   /* \r */
    li   a1, 10  ; sb a1, 0(t6)   /* \n */

    li   t0, 0x100000
    li   t1, 0x3333             /* FAIL */
    sw   t1, 0(t0)
    j    .                      /* halt */

/* _print_hex32: print a0 as 8 hex digits to UART at t6. Returns via t5. */
_print_hex32:
    li   t3, 28         /* shift counter: 28, 24, .. 0 */
.Lhex_loop:
    srl  t4, a0, t3
    andi t4, t4, 0xF
    li   t2, 10
    blt  t4, t2, .Lhex_digit
    addi t4, t4, 'a' - 10
    j    .Lhex_emit
.Lhex_digit:
    addi t4, t4, '0'
.Lhex_emit:
    sb   t4, 0(t6)
    addi t3, t3, -4
    bge  t3, zero, .Lhex_loop
    jr   t5

    .size _trap_handler, . - _trap_handler
