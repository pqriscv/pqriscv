/* common/hal-dabao.c
 * Hardware Abstraction Layer for the Baochip-1x "Dabao" evaluation board
 * (VexRiscv RV32IMAC @ 350 MHz, 2 MiB SRAM, 4 MiB RRAM).
 *
 * ASSUMPTIONS
 * -----------
 * boot0/boot1 run before our code and leave behind:
 *   • PLL at 700 MHz, CPU clock (ACLK) = 350 MHz, peripheral clock ≈ 99.8 MHz
 *   • UART2 on PB13 (RX) / PB14 (TX) at 1 000 000 baud, 8-N-1
 *   • interrupts masked, no watchdog armed
 *
 * We therefore only need to implement:
 *   • hal_send_str  — UART2 transmit
 *   • hal_get_time  — 64-bit cycle counter (mcycle / mcycleh)
 *   • hal_setup     — make sure UART2 is routed and at DABAO_BAUD
 *   • libc stubs    — _write, _sbrk, _exit (which resets back to boot1), etc.
 *   • hal_trap      — fatal trap report, called from startup_dabao.S
 *
 * CONSOLE
 * -------
 * The Dabao has no on-board USB-UART bridge, and boot1 shuts its own USB
 * console down before jumping to us. Output goes to UART2:
 *   PB14 = TX (header pin 15)  →  adapter RX
 *   PB13 = RX (header pin 16)  ←  adapter TX   (unused by this HAL)
 * 3.3 V logic, 115200 baud by default (DABAO_BAUD). boot1's own messages
 * on the same pin are at 1 000 000 baud and show up as noise before ours.
 *
 * UDMA UART (0x50103000) — the UART has no TX data register. Bytes are sent
 * by DMA: put them in a buffer, point TX_SADDR/TX_SIZE at it, set TX_CFG.EN.
 *   TX_SADDR @ +0x10   buffer address
 *   TX_SIZE  @ +0x14   bytes to send (reads back bytes left)
 *   TX_CFG   @ +0x18   bit 4 = EN: write 1 to start, reads 1 while running
 *   STATUS   @ +0x20   bit 0 = TX shifter busy
 *   SETUP    @ +0x24   [31:16] divider (perclk / baud), [9] RX en, [8] TX en,
 *                      [4] RX polling, [2:1] = 3 for 8 data bits
 * UDMA can only reach IFRAM (0x50000000), not SRAM. The TX buffer is the
 * first 256 bytes of IFRAM0; nothing else in this image uses IFRAM.
 *
 * TIMING
 * ------
 * hal_get_time() returns the VexRiscv cycle counter: a true 64-bit count of
 * CPU clock (ACLK) cycles since reset — 350 per microsecond at the clock
 * boot1 leaves. Code runs in place from RRAM behind 16 KiB I/D caches, so
 * cycle counts include cache-miss fetches from RRAM.
 *
 * References: baochip/baochip-1x (RTL: udma_uart_reg_if.sv, GenCramSoC.scala;
 * docs: I/O configuration, clock generation) and betrusted-io/xous-core
 * (bao1x-boot/boot1, libs/bao1x-hal).
 */

#include <hal.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/stat.h>

#ifndef DABAO_BAUD
#define DABAO_BAUD 115200
#endif

#define REG32(addr)        (*(volatile uint32_t *)(addr))

/* -------------------------------------------------------------------------
 * UDMA UART2 — 0x50103000
 * ------------------------------------------------------------------------- */
#define UDMA_CLKGATE       REG32(0x50100000UL)
#define UDMA_CLKGATE_UART2 (1u << 2)

#define UART2_BASE         0x50103000UL
#define UART_TX_SADDR      REG32(UART2_BASE + 0x10)
#define UART_TX_SIZE       REG32(UART2_BASE + 0x14)
#define UART_TX_CFG        REG32(UART2_BASE + 0x18)
#define UART_STATUS        REG32(UART2_BASE + 0x20)
#define UART_SETUP         REG32(UART2_BASE + 0x24)

#define UDMA_CFG_EN        (1u << 4)
#define UART_STATUS_TXBUSY (1u << 0)
#define UART_SETUP_8N1     0x0316u   /* RX+TX enable, RX polling, 8 data bits */

/* TX DMA buffer: start of IFRAM0 */
#define UART_TXBUF         ((volatile uint8_t *)0x50000000UL)
#define UART_TXBUF_SIZE    256u

/* -------------------------------------------------------------------------
 * IOX (pin mux) — 0x5012F000. PB13/PB14 carry UART2 on alternate function 1.
 * ------------------------------------------------------------------------- */
#define IOX_AFSELBH        REG32(0x5012F00CUL)   /* PB[15:8], 2 bits per pin */
#define IOX_GPIOOEB        REG32(0x5012F14CUL)   /* PB output enable         */
#define IOX_GPIOPUB        REG32(0x5012F164UL)   /* PB pull-up enable        */

static void uart_wait_idle(void)
{
    while (UART_TX_CFG & UDMA_CFG_EN)           /* DMA still reading the buffer */
        ;
    while (UART_STATUS & UART_STATUS_TXBUSY)    /* last byte still shifting out */
        ;
}

static void uart_flush(size_t n)
{
    if (n == 0)
        return;
    __asm__ volatile ("fence" ::: "memory");
    UART_TX_SADDR = (uint32_t)(uintptr_t)UART_TXBUF;
    UART_TX_SIZE  = (uint32_t)n;
    UART_TX_CFG   = UDMA_CFG_EN;                /* 8-bit, one-shot */
    uart_wait_idle();
}

/* Blocking write; '\n' goes out as "\r\n". */
static void uart_write(const char *buf, size_t len)
{
    size_t i, n = 0;

    for (i = 0; i < len; i++) {
        if (buf[i] == '\n')
            UART_TXBUF[n++] = '\r';
        UART_TXBUF[n++] = (uint8_t)buf[i];
        if (n >= UART_TXBUF_SIZE - 1) {         /* keep room for a "\r\n" pair */
            uart_flush(n);
            n = 0;
        }
    }
    uart_flush(n);
}

void hal_send_str(const char *s)
{
    size_t len = 0;
    while (s[len])
        len++;
    uart_write(s, len);
    uart_write("\n", 1);
}

/* -------------------------------------------------------------------------
 * hal_setup — console setup. The clock is left as boot1 configured it.
 *
 * CLOCK_FAST and CLOCK_BENCHMARK are the same thing here: 350 MHz, the
 * chip's rated maximum for the CPU clock. Changing it means reprogramming
 * the PLL, the core LDO and the SRAM trims together (init_clock_asic() in
 * xous-core); boot1 has done that already and this HAL does not touch it.
 *
 * Same sequence as boot1's own console setup, at our baud rate: clock gate,
 * pin mux, then SETUP cleared and rewritten.
 * ------------------------------------------------------------------------- */
void hal_setup(const enum clock_mode clock)
{
    /* Divider for 1 Mbaud, i.e. the peripheral clock in MHz. boot1 has
     * programmed it; fall back to the nominal 100 MHz if it has not. */
    static uint32_t div_1m;
    uint32_t setup;

    (void)clock;

    UDMA_CLKGATE |= UDMA_CLKGATE_UART2;

    if (div_1m == 0) {
        div_1m = UART_SETUP >> 16;
        if (div_1m == 0)
            div_1m = 100;
    }

    /* PB13 = RX: AF1, input, pull-up.  PB14 = TX: AF1, output. */
    IOX_AFSELBH = (IOX_AFSELBH & ~(0xFu << 10)) | (0x5u << 10);
    IOX_GPIOOEB = (IOX_GPIOOEB & ~(1u << 13)) | (1u << 14);
    IOX_GPIOPUB |= (1u << 13);

    setup = UART_SETUP_8N1
          | ((uint32_t)(((uint64_t)div_1m * 1000000u + DABAO_BAUD / 2) / DABAO_BAUD) << 16);
    if (UART_SETUP != setup) {
        uart_wait_idle();
        UART_SETUP = 0;             /* disable before changing the divider */
        __asm__ volatile ("fence" ::: "memory");
        UART_SETUP = setup;
        __asm__ volatile ("fence" ::: "memory");
    }
}

/* -------------------------------------------------------------------------
 * hal_get_time — 64-bit machine cycle counter.
 *
 * Unlike the ESP32-C3/C6 cores, this VexRiscv build implements the standard
 * mcycle/mcycleh pair (and minstret/minstreth, should instruction counts
 * ever be wanted). Read high-low-high to be safe across the carry.
 * ------------------------------------------------------------------------- */
uint64_t hal_get_time(void)
{
    uint32_t lo, hi, hi2;
    do {
        __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi));
        __asm__ volatile ("csrr %0, mcycle"  : "=r"(lo));
        __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

/* -------------------------------------------------------------------------
 * hal_get_stack_size — distance from current SP down to the heap ceiling.
 * ------------------------------------------------------------------------- */
extern char end;           /* linker-defined symbol: top of BSS = heap base */
static char *heap_end = NULL;

size_t hal_get_stack_size(void)
{
    register char *sp;
    __asm__ volatile ("mv %0, sp" : "=r"(sp));
    if (!heap_end) heap_end = &end;
    return (size_t)(sp - heap_end);
}

/* -------------------------------------------------------------------------
 * __wrap__sbrk — simple bump-pointer heap allocator.
 *
 * Linked via -Wl,--wrap=_sbrk so newlib's malloc calls us.
 * Heap grows upward from the &end linker symbol.
 * ------------------------------------------------------------------------- */
void *__wrap__sbrk(intptr_t incr)
{
    if (!heap_end) heap_end = &end;
    char *prev = heap_end;
    heap_end += incr;
    return (void *)prev;
}

/* -------------------------------------------------------------------------
 * hal_trap — fatal trap report, entered from _trap_handler on a fresh stack.
 * No printf: keep the path to the UART as short as possible.
 * ------------------------------------------------------------------------- */
static char *put_hex32(char *p, uint32_t v)
{
    int shift;
    for (shift = 28; shift >= 0; shift -= 4)
        *p++ = "0123456789abcdef"[(v >> shift) & 0xF];
    return p;
}

static char *put_str(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    return p;
}

void hal_trap(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    char msg[64];
    char *p = msg;

    p = put_str(p, "\n!TRAP mcause=");
    p = put_hex32(p, mcause);
    p = put_str(p, " mepc=");
    p = put_hex32(p, mepc);
    p = put_str(p, " mtval=");
    p = put_hex32(p, mtval);
    p = put_str(p, "\n");
    uart_write(msg, (size_t)(p - msg));

    while (1) { }
}

/* =========================================================================
 * Newlib / nosys.specs syscall stubs (unused, and discarded, with picolibc)
 * ========================================================================= */

/* _write — redirect stdout/stderr to UART2 so printf works */
int _write(int fd, const char *buf, int len)
{
    (void)fd;
    uart_write(buf, (size_t)len);
    return len;
}

int _read(int fd, char *buf, int len)
{
    (void)fd; (void)buf; (void)len;
    return -1;
}

int _close(int fd)
{
    (void)fd;
    return -1;
}

int _lseek(int fd, int offset, int whence)
{
    (void)fd; (void)offset; (void)whence;
    return -1;
}

int _fstat(int fd, struct stat *st)
{
    (void)fd;
    st->st_mode = S_IFCHR;   /* character device — makes newlib flush eagerly */
    return 0;
}

int _isatty(int fd)
{
    return (fd == 1 || fd == 2) ? 1 : 0;
}

int _getpid(void) { return 1; }

int _kill(int pid, int sig)
{
    (void)pid; (void)sig;
    return -1;
}

/* _exit — print result banner, then return to boot1.
 *
 * The test/bench harness returns 0 from main() on PASS, non-zero on FAIL;
 * startup_dabao.S passes that value on.
 *
 * With DABAO_RESET_ON_EXIT (default 1, see mk/dabao.mk) the chip is then
 * reset the way boot1's own `reset` command does it. With bootwait enabled,
 * as boards ship, boot1 stays in its loader with the BAOCHIP drive mounted,
 * ready for the next image: that is what lets `make run-all-bench` go
 * through every scheme unattended. Build with DABAO_RESET_ON_EXIT=0 if
 * bootwait is disabled on your board, or the image would run in a loop.
 */
#ifndef DABAO_RESET_ON_EXIT
#define DABAO_RESET_ON_EXIT 1
#endif

#define SYSCTRL_RCURST0    REG32(0x40040080UL)   /* write 0x55AA: system reset */

void _exit(int status)
{
    hal_send_str(status == 0
        ? "\n========== [PASS] ==========\n"
        : "\n========== [FAIL] ==========\n");

#if DABAO_RESET_ON_EXIT
    {
        /* hal_send_str returns once the last byte has left the shifter;
         * give the receiving adapter ~10 ms before the line glitches. */
        uint64_t t = hal_get_time();
        while (hal_get_time() - t < 3500000u)
            ;
        SYSCTRL_RCURST0 = 0x55AAu;
    }
#endif
    while (1) { }
}
