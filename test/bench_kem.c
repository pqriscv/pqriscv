/*
 * test/bench_kem.c — KEM benchmark harness
 *
 * Runs NBENCH iterations of keygen, enc, and dec; reports min/max/average
 * tick counts via the HAL UART.  The NIST DRBG provides fresh randomness
 * for each iteration so the compiler cannot optimise them away.
 *
 * Output format (one value per line, parseable by a host script):
 *
 *   BENCH: ML-KEM-768
 *   keygen_min: 12345678
 *   keygen_max: 12345900
 *   keygen_avg: 12345789
 *   enc_min:    ...
 *   ...
 *   BENCH_DONE
 */

#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

#include "hal.h"
#include "api.h"
#include "nistrng.h"

/* -------------------------------------------------------------------------
 * Configuration
 * ------------------------------------------------------------------------- */
#ifndef NBENCH
#define NBENCH  10     /* number of benchmark iterations */
#endif

/* -------------------------------------------------------------------------
 * Helpers
 * ------------------------------------------------------------------------- */
static char _buf[256];

static void pf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(_buf, sizeof(_buf), fmt, ap);
    va_end(ap);
    hal_send_str(_buf);
}

/* Full 64-bit decimal without %llu (not in newlib-nano, used by the ESP
 * targets). On RV32 "%lu" + (unsigned long) silently drops the top 32 bits,
 * i.e. anything above 2^32 cycles (12.3 s at 350 MHz). */
static const char *u64str(uint64_t v)
{
    static char s[21];
    char *p = s + sizeof(s) - 1;
    *p = '\0';
    do { *--p = (char)('0' + (v % 10)); v /= 10; } while (v);
    return p;
}

static uint64_t min_u64(uint64_t a, uint64_t b) { return a < b ? a : b; }
static uint64_t max_u64(uint64_t a, uint64_t b) { return a > b ? a : b; }

/* =========================================================================
 * Main
 * ========================================================================= */
int main(void)
{
    static uint8_t pk [CRYPTO_PUBLICKEYBYTES];
    static uint8_t sk [CRYPTO_SECRETKEYBYTES];
    static uint8_t ct [CRYPTO_CIPHERTEXTBYTES];
    static uint8_t ss [CRYPTO_BYTES];

    uint64_t t_kg_min = UINT64_MAX, t_kg_max = 0, t_kg_sum = 0;
    uint64_t t_en_min = UINT64_MAX, t_en_max = 0, t_en_sum = 0;
    uint64_t t_de_min = UINT64_MAX, t_de_max = 0, t_de_sum = 0;
    uint64_t t0, t1, dt;
    int i;

    hal_setup(CLOCK_BENCHMARK);

    /* Fixed seed for reproducibility */
    {
        uint8_t seed[48];
        for (i = 0; i < 48; i++) seed[i] = (uint8_t)(i ^ 0xa5);
        randombytes_init(seed, NULL, 256);
    }

    pf("BENCH: %s", CRYPTO_ALGNAME);
    pf("iterations: %d", NBENCH);

    for (i = 0; i < NBENCH; i++) {
        /* --- keygen --- */
        t0 = hal_get_time();
        crypto_kem_keypair(pk, sk);
        t1 = hal_get_time();
        dt = t1 - t0;
        t_kg_min  = min_u64(t_kg_min, dt);
        t_kg_max  = max_u64(t_kg_max, dt);
        t_kg_sum += dt;

        /* --- enc --- */
        t0 = hal_get_time();
        crypto_kem_enc(ct, ss, pk);
        t1 = hal_get_time();
        dt = t1 - t0;
        t_en_min  = min_u64(t_en_min, dt);
        t_en_max  = max_u64(t_en_max, dt);
        t_en_sum += dt;

        /* --- dec --- */
        t0 = hal_get_time();
        crypto_kem_dec(ss, ct, sk);
        t1 = hal_get_time();
        dt = t1 - t0;
        t_de_min  = min_u64(t_de_min, dt);
        t_de_max  = max_u64(t_de_max, dt);
        t_de_sum += dt;
    }

    pf("keygen_min: %s", u64str(t_kg_min));
    pf("keygen_max: %s", u64str(t_kg_max));
    pf("keygen_avg: %s", u64str((t_kg_sum / NBENCH)));

    pf("enc_min:    %s", u64str(t_en_min));
    pf("enc_max:    %s", u64str(t_en_max));
    pf("enc_avg:    %s", u64str((t_en_sum / NBENCH)));

    pf("dec_min:    %s", u64str(t_de_min));
    pf("dec_max:    %s", u64str(t_de_max));
    pf("dec_avg:    %s", u64str((t_de_sum / NBENCH)));

    

    pf("stack_remaining: %u", (unsigned)hal_get_stack_size());

    hal_send_str("BENCH_DONE");
    return 0;
}
