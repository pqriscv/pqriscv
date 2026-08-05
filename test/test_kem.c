/*
 * test/test_kem.c — Functional test harness for any KEM
 *
 * Compile-time requirements (set by the build system):
 *   CRYPTO_ALGNAME, CRYPTO_PUBLICKEYBYTES, CRYPTO_SECRETKEYBYTES,
 *   CRYPTO_CIPHERTEXTBYTES, CRYPTO_BYTES           — from api.h
 *
 * What this test does:
 *   1. Seeds the NIST deterministic RNG (reproducible, same as KAT vectors).
 *   2. Runs NTEST iterations of keygen + encapsulate + decapsulate.
 *   3. Checks that the shared secrets match.
 *   4. Runs one additional iteration with a corrupted ciphertext and checks
 *      that the decapsulated secret DIFFERS (implicit rejection check).
 *   5. Prints timing from the HAL timer and reports PASS or FAIL.
 *
 * Output is line-oriented so a host script can parse it easily:
 *   ============================
 *   SCHEME:  ML-KEM-768
 *   PK bytes:  1184
 *   SK bytes:  2400
 *   CT bytes:  1088
 *   SS bytes:  32
 *   ---
 *   iter 0: keygen OK  enc OK  dec OK
 *   ...
 *   IMPLREJECT: OK
 *   ---
 *   RESULT: PASS
 *   ============================
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
#define NTEST  2         /* number of keygen/enc/dec iterations   */

/* -------------------------------------------------------------------------
 * Helpers
 * ------------------------------------------------------------------------- */
static char _print_buf[256];

static void pf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(_print_buf, sizeof(_print_buf), fmt, ap);
    va_end(ap);
    hal_send_str(_print_buf);
}

/* Constant-time compare: returns 0 if equal, non-zero otherwise */
static int ct_memcmp(const uint8_t *a, const uint8_t *b, size_t n)
{
    uint8_t diff = 0;
    size_t i;
    for (i = 0; i < n; i++) diff |= a[i] ^ b[i];
    return (int)diff;
}


/* =========================================================================
 * Main
 * ========================================================================= */
int main(void)
{
    /* Static buffers — avoids large stack allocations on bare metal */
    for(int i = 0; i < 9999;i++){
        asm("nop");
    }
    static uint8_t pk [CRYPTO_PUBLICKEYBYTES];
    static uint8_t sk [CRYPTO_SECRETKEYBYTES];

    static uint8_t ct [CRYPTO_CIPHERTEXTBYTES];
    static uint8_t ss_enc[CRYPTO_BYTES];
    static uint8_t ss_dec[CRYPTO_BYTES];

    uint64_t t0, t1;
    uint64_t cyc_keygen, cyc_enc, cyc_dec;
    int ok = 1;
    int i;

    hal_setup(CLOCK_BENCHMARK);

    /* Seed the NIST DRBG with a fixed, standard seed */
    {
        uint8_t seed[48];
        for (i = 0; i < 48; i++) seed[i] = (uint8_t)i;
        randombytes_init(seed, NULL, 256);
    }

    hal_send_str("============================");
    pf("SCHEME:  %s", CRYPTO_ALGNAME);
    pf("PK bytes:  %d", CRYPTO_PUBLICKEYBYTES);
    pf("SK bytes:  %d", CRYPTO_SECRETKEYBYTES);
    pf("CT bytes:  %d", CRYPTO_CIPHERTEXTBYTES);
    pf("SS bytes:  %d", CRYPTO_BYTES);
    hal_send_str("---");

    /* -----------------------------------------------------------------
     * NTT self-test: verify assembly NTT output against reference.
     * ntt_selftest_dump() lives in ntt.c (compiled into libscheme.a).
     * ----------------------------------------------------------------- */
        extern void ntt_selftest_dump(int16_t out[16]);
        static const int16_t ntt_exp[16] = {
            2429, 2845,  425,  795, 1865, 1356,  624,   31,
            2483, 2197, 2725, 2668, 2707,  517, 1488, 2194
        };
        static int16_t ntt_got[16];
        int ntt_ok = 1, j;
        ntt_selftest_dump(ntt_got);
        for (j = 0; j < 16; j++) {
            if (ntt_got[j] != ntt_exp[j]) {
                pf("NTT[%d] got=%d exp=%d", j, (int)ntt_got[j], (int)ntt_exp[j]);
                ntt_ok = 0;
            }
        }
        pf("NTT self-test: %s", ntt_ok ? "PASS" : "FAIL");
    hal_send_str("---");

    for(int i = 0; i < 999;i++){
            asm("nop");
    }
    //hal_send_str("============================");


    /* -----------------------------------------------------------------
     * Functional test loop
     * ----------------------------------------------------------------- */
    for (i = 0; i < NTEST; i++) {
        int kg_ok, enc_ok, dec_ok, ss_ok;

        /* Keygen */
        hal_send_str("Starting keygen...");
       // t0 = hal_get_time();
        kg_ok = (crypto_kem_keypair(pk, sk) == 0);
        //t1 = hal_get_time();
        hal_send_str("end keygen...");
        //cyc_keygen = t1 - t0;

        /* Encapsulate */
        hal_send_str("Starting crypto_kem_enc...");
        //t0 = hal_get_time();
        enc_ok = (crypto_kem_enc(ct, ss_enc, pk) == 0);
        //t1 = hal_get_time();
        hal_send_str("end crypto_kem_enc...");
        //cyc_enc = t1 - t0;

        /* Decapsulate */
        hal_send_str("Starting crypto_kem_dec...");
        //t0 = hal_get_time();
        dec_ok = (crypto_kem_dec(ss_dec, ct, sk) == 0);
        //t1 = hal_get_time();
        hal_send_str("end crypto_kem_dec...");
        //cyc_dec = t1 - t0;

        /* Check shared secrets match — only meaningful if enc+dec both succeeded */
        if (enc_ok && dec_ok)
            ss_ok = (ct_memcmp(ss_enc, ss_dec, CRYPTO_BYTES) == 0);
        else
            ss_ok = 0;

        if (!kg_ok || !enc_ok || !dec_ok || !ss_ok) ok = 0;

        pf("iter %d: keygen %s  enc %s  dec %s  ss %s",
           i,
           kg_ok  ? "OK" : "FAIL",
           enc_ok ? "OK" : "FAIL",
           dec_ok ? "OK" : "FAIL",
           ss_ok  ? "OK" : "FAIL");

       /* if (i == 0) {
            pf("  keygen: %llu ticks", (unsigned long long)cyc_keygen);
            pf("  enc:    %llu ticks", (unsigned long long)cyc_enc);
            pf("  dec:    %llu ticks", (unsigned long long)cyc_dec);
        }*/
    }
    hal_send_str("============================");

    /* -----------------------------------------------------------------
     * Implicit rejection test: corrupt ciphertext → ss must differ
     * ----------------------------------------------------------------- */
    {
        int kg_ok, enc_ok, dec_ok, rej_ok;

        kg_ok  = (crypto_kem_keypair(pk, sk) == 0);
        enc_ok = (crypto_kem_enc(ct, ss_enc, pk) == 0);
        ct[0] ^= 0x01;   /* flip one bit in the ciphertext */
        dec_ok = (crypto_kem_dec(ss_dec, ct, sk) == 0);

        /* After corruption, ss_dec must NOT equal ss_enc */
        rej_ok = (ct_memcmp(ss_enc, ss_dec, CRYPTO_BYTES) != 0);

        if (!kg_ok || !enc_ok || !dec_ok || !rej_ok) ok = 0;

        pf("IMPLREJECT: %s", rej_ok ? "OK" : "FAIL (shared secrets matched!)");
    }

    /* -----------------------------------------------------------------
     * Stack usage report
     * ----------------------------------------------------------------- */
    {
        size_t stack = hal_get_stack_size();
        pf("Stack remaining: %u bytes", (unsigned)stack);
    }
    hal_send_str("---");
    hal_send_str(ok ? "RESULT: PASS" : "RESULT: FAIL");
    hal_send_str("============================");

    return ok ? 0 : 1;
}
