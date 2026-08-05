/*
 * test_sign.c — Functional test for ML-DSA (Dilithium) schemes
 *
 * Tests:
 *   1. Keygen + sign + verify (5 iterations with random messages)
 *   2. Signature rejection when message is tampered
 *   3. Signature rejection when signature is tampered
 */

#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>

#include "hal.h"
#include "randombytes.h"
#include "api.h"

static void hal_sendf(const char *fmt, ...)
{
    char buf[128];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    hal_send_str(buf);
}

#define MSG_LEN  32
#define NITER     5

/* Static to avoid blowing the stack — sk can be up to 4896 bytes */
static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
static uint8_t sk[CRYPTO_SECRETKEYBYTES];
static uint8_t sig[CRYPTO_BYTES];
static uint8_t msg[MSG_LEN];


int main(void)
{
    hal_setup(CLOCK_BENCHMARK);
    size_t siglen;
    int i, ret, fail = 0;

    hal_sendf("============================");
    hal_sendf("SCHEME:  %s", CRYPTO_ALGNAME);
    hal_sendf("PK bytes:  %d", CRYPTO_PUBLICKEYBYTES);
    hal_sendf("SK bytes:  %d", CRYPTO_SECRETKEYBYTES);
    hal_sendf("Sig bytes: %d", CRYPTO_BYTES);
    hal_sendf("---");

    for (i = 0; i < NITER; i++) {
        uint64_t t0, t1;

        randombytes(msg, MSG_LEN);

        /* --- Keygen --- */
        t0 = hal_get_time();
        ret = crypto_sign_keypair(pk, sk);
        t1 = hal_get_time();
        int kg_ok = (ret == 0);

        /* --- Sign --- */
        //uint64_t ts0 = hal_get_time();
        ret = crypto_sign_signature(sig, &siglen, msg, MSG_LEN,
                                    NULL, 0, sk);
        //uint64_t ts1 = hal_get_time();
        int sg_ok = (ret == 0);

        /* --- Verify --- */
        //uint64_t tv0 = hal_get_time();
        ret = crypto_sign_verify(sig, siglen, msg, MSG_LEN, NULL, 0, pk);
        //uint64_t tv1 = hal_get_time();
        int vf_ok = (ret == 0);

        if (!kg_ok || !sg_ok || !vf_ok) fail = 1;

        hal_sendf("iter %d: keygen %s  sign %s  verify %s", i,
               kg_ok ? "OK" : "FAIL",
               sg_ok ? "OK" : "FAIL",
               vf_ok ? "OK" : "FAIL");
        hal_sendf("  keygen: %llu ticks", (unsigned long long)(t1 - t0));
        //hal_sendf("  sign:   %llu ticks", (unsigned long long)(ts1 - ts0));
        //hal_sendf("  verify: %llu ticks", (unsigned long long)(tv1 - tv0));
    }
    for (int i=0; i<=9999; i++){

    }

    /* --- Rejection test: tampered message --- */
    {
        crypto_sign_keypair(pk, sk);
        randombytes(msg, MSG_LEN);
        crypto_sign_signature(sig, &siglen, msg, MSG_LEN, NULL, 0, sk);
        msg[0] ^= 0xFF;  /* flip a bit */
        ret = crypto_sign_verify(sig, siglen, msg, MSG_LEN, NULL, 0, pk);
        int reject_ok = (ret != 0);
        hal_sendf("MSGTAMPER: %s", reject_ok ? "OK" : "FAIL");
        if (!reject_ok) fail = 1;
    }

    /* --- Rejection test: tampered signature --- */
    {
        crypto_sign_keypair(pk, sk);
        randombytes(msg, MSG_LEN);
        crypto_sign_signature(sig, &siglen, msg, MSG_LEN, NULL, 0, sk);
        sig[siglen / 2] ^= 0xFF;  /* corrupt middle of signature */
        ret = crypto_sign_verify(sig, siglen, msg, MSG_LEN, NULL, 0, pk);
        int reject_ok = (ret != 0);
        hal_sendf("SIGTAMPER: %s", reject_ok ? "OK" : "FAIL");
        if (!reject_ok) fail = 1;
    }

   // hal_sendf("Stack remaining: %u bytes", (unsigned)hal_get_stack_size());

    hal_sendf("---");
    hal_sendf("RESULT: %s", fail ? "FAIL" : "PASS");
    hal_sendf("============================");
    return fail;
}
