/* common/hal-esp-riscv.c
 * Hardware Abstraction Layer for ESP32 RISC-V variants (ESP32-C3, ESP32-C6).
 *
 * ASSUMPTIONS
 * -----------
 * The ROM first-stage bootloader runs before our code and leaves behind:
 *   • UART0 @ 115200 baud, 8-N-1, TX on the default GPIO pin
 *   • CPU clock already configured (80 MHz on C3; 80 or 96 MHz on C6)
 *   • Flash cache enabled (our code was already loaded from flash to IRAM)
 *
 * We therefore only need to implement:
 *   • hal_send_str  — write to UART0 TX FIFO
 *   • hal_get_time  — read mcycle (32-bit machine cycle counter, M-mode CSR)
 *   • hal_setup     — optional clock switch to 160 MHz for benchmarking
 *   • newlib stubs  — _write, _sbrk, _exit, etc.
 *
 * UART REGISTERS (0x60000000, same layout on C3 and C6)
 * -----------------------------------------------------
 * UART_FIFO_REG    @ 0x60000000 + 0x00  bits[7:0] = TX/RX data byte
 * UART_STATUS_REG  @ 0x60000000 + 0x1C
 *   bits[9:0]   RXFIFO_CNT  — bytes currently in RX FIFO
 *   bits[25:16] TXFIFO_CNT  — bytes currently in TX FIFO (depth = 128)
 *
 * TIMING
 * ------
 * hal_get_time() returns the 32-bit mcycle counter zero-extended to uint64_t.
 * Translate to microseconds: us = cycles / (MHz * 1).
 *
 * Default clock:   80 MHz  →  1 cycle = 12.5 ns
 * After hal_setup(CLOCK_BENCHMARK) on C3: 160 MHz → 1 cycle = 6.25 ns
 *
 * CLOCK SWITCHING (ESP32-C3 only, C6 TODO)
 * -----------------------------------------
 * ESP32-C3 SYSTEM_CPU_CLKDIV_REG @ 0x600C0000:
 *   bits[1:0]  CPUPERIOD_SEL:  0b00 = 80 MHz,  0b01 = 160 MHz
 *   bit[30]    CPU_CLK_EN      (read/preserve, do not clear)
 *
 * Reference: ESP32-C3 Technical Reference Manual, Chapter 7 (System).
 */

#include <hal.h>
#include <stdint.h>
#include <sys/stat.h>
#include <errno.h>

/* -------------------------------------------------------------------------
 * UART0 — 0x60000000
 * ------------------------------------------------------------------------- */
#define UART0_BASE         0x60000000UL
#define UART_FIFO          (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART_STATUS        (*(volatile uint32_t *)(UART0_BASE + 0x1C))

/* TXFIFO_CNT lives at bits [25:16].  FIFO depth is 128 bytes. */
#define TXFIFO_CNT(s)      (((s) >> 16) & 0x3FFu)
#define UART_FIFO_DEPTH    128u

static inline void uart_putc(char c)
{
    /* Wait until the TX FIFO has at least one free slot. */
    while (TXFIFO_CNT(UART_STATUS) >= UART_FIFO_DEPTH)
        ;
    UART_FIFO = (uint8_t)c;
}

void hal_send_str(const char *s)
{
    while (*s) {
        if (*s == '\n')
            uart_putc('\r');
        uart_putc(*s++);
    }
    uart_putc('\n');   /* always terminate with a newline on the wire */
}

/* -------------------------------------------------------------------------
/* -------------------------------------------------------------------------
 * disable_wdts — kill all hardware watchdogs the ROM left running.
 *
 * Register addresses verified against esp32c3.peripherals.ld and
 * esp32c6.peripherals.ld from esp-idf (PROVIDE statements).
 *
 * ESP32-C3:
 *   TIMERG0 @ 0x6001F000, TIMERG1 @ 0x60020000
 *   RTC_CNTL WDT: CONFIG0 @ 0x60008074, WPROTECT @ 0x6000808C
 *
 * ESP32-C6:
 *   TIMERG0 @ 0x60008000, TIMERG1 @ 0x60009000
 *   LP_WDT base @ 0x600B1C00:
 *     RWDT CONFIG0 +0x00, RWDT WPROTECT +0x18
 *     SWD  CONFIG  +0x1C, SWD  WPROTECT +0x20  (own protect register!)
 *     SWD AUTO_FEED_EN = bit 18 of SWD_CONFIG (not bit 31)
 *
 * TIMG offsets (identical on C3 and C6):
 *   WDTCONFIG0 @ base + 0x48
 *   WDTWPROTECT @ base + 0x64   key = 0x50D83AA1
 * ------------------------------------------------------------------------- */
static void disable_wdts(void)
{
#define MWDT_KEY 0x50D83AA1U
#define TIMG_WPROTECT(b) (*(volatile uint32_t *)((b) + 0x64UL))
#define TIMG_CONFIG0(b)  (*(volatile uint32_t *)((b) + 0x48UL))
/* wdt_conf_update_en = bit22 MUST be set when writing CONFIG0, otherwise
 * the hardware ignores the write entirely (config update latch).
 * wdt_en = bit31; clearing it with bit22=1 disables the WDT. */
#define TIMG_DIS(b) do { \
    TIMG_WPROTECT(b) = MWDT_KEY;     \
    TIMG_CONFIG0(b)  = (1u << 22);   \
    TIMG_WPROTECT(b) = 0U;           \
} while(0)

#if defined(ESP32C3)
    TIMG_DIS(0x6001F000UL);   /* TIMERG0 */
    TIMG_DIS(0x60020000UL);   /* TIMERG1 */
    /* RTC_CNTL WDT (ESP32-C3): WPROTECT @ 0x6000808C, CONFIG0 @ 0x60008074 */
    *(volatile uint32_t *)0x6000808CUL = MWDT_KEY;
    *(volatile uint32_t *)0x60008074UL = 0U;
    *(volatile uint32_t *)0x6000808CUL = 0U;

#elif defined(ESP32C6)
    TIMG_DIS(0x60008000UL);   /* TIMERG0 — the one that was firing */
    TIMG_DIS(0x60009000UL);   /* TIMERG1 */
    /* LP_WDT (RWDT): CONFIG0 @ base+0x00, WPROTECT @ base+0x18 */
#define LPWDT 0x600B1C00UL
    *(volatile uint32_t *)(LPWDT + 0x18UL) = MWDT_KEY;   /* unlock RWDT */
    *(volatile uint32_t *)(LPWDT + 0x00UL) = 0U;          /* clear all stages */
    *(volatile uint32_t *)(LPWDT + 0x18UL) = 0U;          /* lock */
    /* Super-WDT: own WPROTECT @ base+0x20, CONFIG @ base+0x1C, AUTO_FEED_EN = bit18 */
    *(volatile uint32_t *)(LPWDT + 0x20UL) = MWDT_KEY;   /* unlock SWD */
    *(volatile uint32_t *)(LPWDT + 0x1CUL) |= (1u << 18); /* AUTO_FEED_EN */
    *(volatile uint32_t *)(LPWDT + 0x20UL) = 0U;          /* lock */
#undef LPWDT
#endif

#undef MWDT_KEY
#undef TIMG_WPROTECT
#undef TIMG_CONFIG0
#undef TIMG_DIS
}

/* --- ESP-RISC-V custom performance counter (C3/C6) -------------------------
 * 0x7E0  MPCER  event select   (bit0 = count CPU cycles)
 * 0x7E1  MPCMR  mode           (bit0 = enable)
 * 0x7E2  MPCCR  32-bit count
 * The standard mcycle/cycle CSRs are NOT implemented on this core.
 */
static inline void perfcounter_init(void)
{
    unsigned int one = 1;
    __asm__ volatile ("csrw 0x7E0, %0" :: "r"(one));  /* select: CPU cycles */
    __asm__ volatile ("csrw 0x7E1, %0" :: "r"(one));  /* enable             */
    __asm__ volatile ("csrw 0x7E2, zero");            /* clear the counter  */
}

 /* hal_setup — optional CPU clock configuration.
 *
 * CLOCK_FAST      : leave ROM-configured clock as-is (safe default)
 * CLOCK_BENCHMARK : switch to 160 MHz for accurate cycle counts
 *
 * Only ESP32-C3 clock switching is implemented.  ESP32-C6 uses a
 * different PCR peripheral; for now it falls through to a no-op.
 * ------------------------------------------------------------------------- */
void hal_setup(const enum clock_mode clock)
{
    /* Kill watchdogs the ROM left running — must happen before any long operation */
    disable_wdts();
    perfcounter_init();

    if (clock != CLOCK_BENCHMARK)
        return;

#if defined(ESP32C3)
    /*
     * SYSTEM_CPU_CLKDIV_REG @ 0x600C0000
     *   bit[30]  : CPU_CLK_EN   (must stay 1)
     *   bits[1:0]: CPUPERIOD_SEL  0=80 MHz, 1=160 MHz
     *
     * Read-modify-write to preserve all other bits (especially CPU_CLK_EN).
     */
    volatile uint32_t *cpu_div = (volatile uint32_t *)0x600C0000UL;
    uint32_t val = *cpu_div;
    val = (val & ~0x3u) | 0x1u;   /* CPUPERIOD_SEL = 1 → 160 MHz */
    *cpu_div = val;
    /* Small delay to let the PLL stabilise before any CSR reads */
    for (volatile int i = 0; i < 100; i++) { }
#elif defined(ESP32C6)
    /*
     * ESP32-C6 uses the PCR (Peripheral Clock Reset) block.
     * Clock switching requires configuring PCR_CPU_FREQ_CONF_REG.
     * TODO: add C6-specific 160 MHz switch.
     * For now, benchmarks run at the ROM-default clock (~96 MHz).
     */
    volatile uint32_t *cpu_div = (volatile uint32_t *)0x600C0000UL;
    uint32_t val = *cpu_div;
    val = (val & ~0x3u) | 0x1u;   /* CPUPERIOD_SEL = 1 → 160 MHz */
    *cpu_div = val;
    /* Small delay to let the PLL stabilise before any CSR reads */
    for (volatile int i = 0; i < 100; i++) { }
    (void)0;
#endif
}


uint64_t hal_get_time(void)
{
    uint32_t c;
    __asm__ volatile ("csrr %0, 0x7E2" : "=r"(c));
    return (uint64_t)c;
}


/* -------------------------------------------------------------------------
 * hal_get_time — 32-bit machine cycle counter, zero-extended to uint64_t.
 *
 * ESP32-C3 and ESP32-C6 only implement a 32-bit mcycle CSR (no mcycleh).
 * Accessing mcycleh causes an Illegal Instruction trap on these chips.
 * Espressif's own IDF reads only 32-bit mcycle (esp_cpu_cycle_count_t
 * is typedef'd to uint32_t in esp_cpu.h).
 *
 * Overflow period at 160 MHz: 2^32 / 160e6 ≈ 26.8 s — more than enough
 * for any single KEM operation.  The API returns uint64_t for portability
 * (callers that compute differences still work correctly for durations
 * shorter than the overflow period).
 * ------------------------------------------------------------------------- */
/*
uint64_t hal_get_time(void)
{
    uint32_t lo;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(lo));
    return (uint64_t)lo;
}*/

/* -------------------------------------------------------------------------
 * hal_get_stack_size — distance from current SP down to the heap ceiling.
 * Useful for stack-usage reporting in bench output.
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

/* =========================================================================
 * Newlib / nosys.specs syscall stubs
 * ========================================================================= */

/* _write — redirect stdout/stderr to UART0 so printf works */
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

int _read(int fd, char *buf, int len)
{
    (void)fd; (void)buf; (void)len;
    errno = ENOSYS;
    return -1;
}

int _close(int fd)
{
    (void)fd;
    errno = ENOSYS;
    return -1;
}

int _lseek(int fd, int offset, int whence)
{
    (void)fd; (void)offset; (void)whence;
    errno = ENOSYS;
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
    errno = ENOSYS;
    return -1;
}

/* _exit — print result banner, optionally trigger chip reset, then spin.
 *
 * The test/bench harness calls _exit(0) on PASS, _exit(1) on FAIL.
 * The banner is readable in any serial terminal.
 */
void _exit(int status)
{
    hal_send_str(status == 0
        ? "\r\n========== [PASS] ==========\r\n"
        : "\r\n========== [FAIL] ==========\r\n");

    /* Flush UART TX FIFO before resetting */
    while (TXFIFO_CNT(UART_STATUS) != 0)
        ;

#if defined(ESP32C3)
    /*
     * Trigger a software system reset via RTC_CNTL_OPTIONS0_REG.
     * RTC_CNTL base: 0x60008000
     * OPTIONS0 (offset 0x0), bit 31: SW_SYS_RST
     * Writing 1 causes an immediate chip reset so esptool can re-flash
     * without pressing the RESET button.
     */
    volatile uint32_t *rtc_options0 = (volatile uint32_t *)0x60008000UL;
    *rtc_options0 |= (1u << 31);
#elif defined(ESP32C6)
    /*
     * ESP32-C6 reset via LP_AON_CFG0 or via WDT.
     * TODO: add C6-specific reset.  For now just spin — press RESET manually.
     */
#endif

    /* Should never reach here; spin in case reset doesn't fire */
    while (1) { }
}
