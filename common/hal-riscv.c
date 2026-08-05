#include <hal.h>
#include <stdint.h>
#include <sys/stat.h>   /* struct stat for _fstat */
#include <errno.h>

/*
 * hal-riscv.c — Hardware Abstraction Layer for QEMU RISC-V 32 "virt" machine.
 *
 * Peripherals used:
 *   NS16550A UART  @ 0x10000000  (pre-initialised by QEMU, write-only needed)
 *   RISC-V "time" CSR            (memory-mapped timer via CLINT)
 *
 * Also provides the newlib syscall stubs expected by libc so that printf /
 * vsnprintf work via UART without linker warnings.
 */

/* -------------------------------------------------------------------------
 * NS16550A UART — base address on the QEMU "virt" machine.
 * QEMU initialises the UART at boot; we only need to poll the TX ready bit
 * and write characters — no baud-rate setup required.
 * ------------------------------------------------------------------------- */
#define UART0_BASE  0x10000000UL

#define UART_THR    (*(volatile uint8_t *)(UART0_BASE + 0))  /* TX holding   */
#define UART_LSR    (*(volatile uint8_t *)(UART0_BASE + 5))  /* Line status  */
#define LSR_THRE    (1u << 5)                                 /* TX buf empty */

static inline void uart_putc(char c)
{
    while (!(UART_LSR & LSR_THRE));
    UART_THR = (uint8_t)c;
}

void hal_send_str(const char *s)
{
    while (*s) {
        if (*s == '\n')
            uart_putc('\r');
        uart_putc(*s++);
    }
    uart_putc('\n');
}

/* -------------------------------------------------------------------------
 * hal_setup — clock-mode selection.
 * On the virt machine there is no PLL to configure; this is a no-op that
 * mirrors the ARM/MPS2 interface so test.c compiles unchanged.
 * ------------------------------------------------------------------------- */
void hal_setup(const enum clock_mode clock)
{
    (void)clock;
}

/* -------------------------------------------------------------------------
 * hal_get_time — read the 64-bit M-mode timer (mtime).
 *
 * On RV32 the "time" CSR is only 32 bits wide, so we must read the upper
 * half ("timeh") and handle the carry atomically.
 *
 * QEMU's virt machine ticks the timer at 10 MHz (100 ns/tick).
 *
 * Requires GCC 12+ toolchain built with -march=rv32imac_zicsr (or newer).
 * On older GCC (≤11) the _zicsr extension was implicit — drop it from ARCH_FLAGS.
 * ------------------------------------------------------------------------- */
uint64_t hal_get_time(void)
{
    uint32_t lo, hi, hi2;
    do {
        __asm__ volatile ("csrr %0, timeh" : "=r"(hi));
        __asm__ volatile ("csrr %0, time"  : "=r"(lo));
        __asm__ volatile ("csrr %0, timeh" : "=r"(hi2));
    } while (hi != hi2);   /* retry if an overflow happened mid-read */
    return ((uint64_t)hi << 32) | lo;
}

/* -------------------------------------------------------------------------
 * hal_get_stack_size — distance between the current SP and the heap top.
 * ------------------------------------------------------------------------- */

/* Heap-end symbol provided by the linker script */
extern char end;
static char *heap_end = NULL;

size_t hal_get_stack_size(void)
{
    register char *cur_stack;
    __asm__ volatile ("mv %0, sp" : "=r"(cur_stack));
    if (!heap_end) heap_end = &end;
    return (size_t)(cur_stack - heap_end);
}

/* -------------------------------------------------------------------------
 * __wrap__sbrk — custom heap allocator called by newlib's malloc.
 *
 * The Makefile passes -Wl,--wrap=_sbrk so every newlib call to _sbrk
 * is redirected here.  Heap grows upward from the linker-defined "end"
 * symbol, matching the layout in virt.ld.
 * ------------------------------------------------------------------------- */
void *__wrap__sbrk(intptr_t incr)
{
    if (!heap_end) heap_end = &end;
    char *prev = heap_end;
    heap_end += incr;
    return (void *)prev;
}

/* =========================================================================
 * Newlib syscall stubs
 *
 * --specs=nosys.specs provides weak stubs for all POSIX syscalls but warns
 * at link time for each one that "is not implemented and will always fail".
 * Providing our own definitions here overrides those weak stubs and silences
 * the warnings.  Only _write actually does anything useful.
 * ========================================================================= */

/*
 * _write — redirect stdout (fd 1) and stderr (fd 2) to the UART.
 * This makes printf / vsnprintf output appear on the QEMU console.
 */
int _write(int fd, const char *buf, int len)
{
    int i;
    (void)fd;
    for (i = 0; i < len; i++) {
        if (buf[i] == '\n')
            uart_putc('\r');
        uart_putc(buf[i]);
    }
    return len;
}

/* _read — no stdin on bare metal */
int _read(int fd, char *buf, int len)
{
    (void)fd; (void)buf; (void)len;
    errno = ENOSYS;
    return -1;
}

/* _close — no file descriptors */
int _close(int fd)
{
    (void)fd;
    errno = ENOSYS;
    return -1;
}

/* _lseek — no seekable file descriptors */
int _lseek(int fd, int offset, int whence)
{
    (void)fd; (void)offset; (void)whence;
    errno = ENOSYS;
    return -1;
}

/* _fstat — report stdout/stderr as character devices */
int _fstat(int fd, struct stat *st)
{
    (void)fd;
    st->st_mode = S_IFCHR;   /* character device */
    return 0;
}

/* _isatty — stdout and stderr are "terminals" (so newlib flushes eagerly) */
int _isatty(int fd)
{
    return (fd == 1 || fd == 2) ? 1 : 0;
}

/* _getpid — single-process bare-metal */
int _getpid(void)
{
    return 1;
}

/* _kill — no signals */
int _kill(int pid, int sig)
{
    (void)pid; (void)sig;
    errno = ENOSYS;
    return -1;
}

/* _exit — signal QEMU to halt */
void _exit(int status)
{
    /* SiFive test device: 0x5555 = PASS exit, anything else = FAIL */
    volatile uint32_t *test_dev = (volatile uint32_t *)0x100000;
    *test_dev = (status == 0) ? 0x5555 : (0x3333 | ((status & 0x7fff) << 16));
    while (1);
}
