/*
 * bench_sign.c — Cycle-count benchmark for ML-DSA (Dilithium)
 *
 * Reports min / max / avg ticks for keygen, sign, and verify.
 */

#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <inttypes.h>

#include "hal.h"
#include "randombytes.h"
#include "api.h"
// extern uint64_t mldsa_prof_ntt_cycles;
// extern uint64_t mldsa_prof_invntt_cycles;
// extern uint32_t mldsa_prof_ntt_calls;
// extern uint32_t mldsa_prof_invntt_calls;
//extern void mldsa_profile_reset(void);

static void hal_sendf(const char *fmt, ...)
{
    char buf[128];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    hal_send_str(buf);
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

#define NITER   20
#define MSG_LEN 59   /* arbitrary non-power-of-two */

static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
static uint8_t sk[CRYPTO_SECRETKEYBYTES];
static uint8_t sig[CRYPTO_BYTES];
static uint8_t msg[MSG_LEN];

int main(void)
{
    hal_setup(CLOCK_BENCHMARK);
    uint64_t t_kg[NITER], t_sg[NITER], t_vf[NITER];

    // uint64_t kg_ntt[NITER], kg_invntt[NITER];
    // uint64_t sg_ntt[NITER], sg_invntt[NITER];
    // uint64_t vf_ntt[NITER], vf_invntt[NITER];

    // uint32_t kg_ntt_calls[NITER], kg_invntt_calls[NITER];
    // uint32_t sg_ntt_calls[NITER], sg_invntt_calls[NITER];
    // uint32_t vf_ntt_calls[NITER], vf_invntt_calls[NITER];
    size_t siglen;
    int i;
    int sign_failures = 0, verify_failures = 0;

    hal_sendf("===========!@!=================");
    hal_sendf("BENCH: %s", CRYPTO_ALGNAME);
    hal_sendf("iters: %d\n---", NITER);

    for (i = 0; i < NITER; i++) {
        uint64_t t0, t1;
        randombytes(msg, MSG_LEN);

        t0 = hal_get_time(); crypto_sign_keypair(pk, sk);           t1 = hal_get_time(); t_kg[i] = t1 - t0;
        t0 = hal_get_time(); int sr = crypto_sign_signature(sig, &siglen, msg, MSG_LEN, NULL, 0, sk); t1 = hal_get_time(); t_sg[i] = t1 - t0;
        if (sr != 0) sign_failures++;
        t0 = hal_get_time(); int vr = crypto_sign_verify(sig, siglen, msg, MSG_LEN, NULL, 0, pk);    t1 = hal_get_time(); t_vf[i] = t1 - t0;
        if (vr != 0) verify_failures++;
        // mldsa_profile_reset();
        // t0 = hal_get_time();
        // crypto_sign_keypair(pk, sk);
        // t1 = hal_get_time();
        // t_kg[i] = t1 - t0;
        // kg_ntt[i] = mldsa_prof_ntt_cycles;
        // kg_invntt[i] = mldsa_prof_invntt_cycles;
        // kg_ntt_calls[i] = mldsa_prof_ntt_calls;
        // kg_invntt_calls[i] = mldsa_prof_invntt_calls;

        // mldsa_profile_reset();
        // t0 = hal_get_time();
        // crypto_sign_signature(sig, &siglen, msg, MSG_LEN, NULL, 0, sk);
        // t1 = hal_get_time();
        // t_sg[i] = t1 - t0;
        // sg_ntt[i] = mldsa_prof_ntt_cycles;
        // sg_invntt[i] = mldsa_prof_invntt_cycles;
        // sg_ntt_calls[i] = mldsa_prof_ntt_calls;
        // sg_invntt_calls[i] = mldsa_prof_invntt_calls;

        // mldsa_profile_reset();
        // t0 = hal_get_time();
        // crypto_sign_verify(sig, siglen, msg, MSG_LEN, NULL, 0, pk);
        // t1 = hal_get_time();
        // t_vf[i] = t1 - t0;
        // vf_ntt[i] = mldsa_prof_ntt_cycles;
        // vf_invntt[i] = mldsa_prof_invntt_cycles;
        // vf_ntt_calls[i] = mldsa_prof_ntt_calls;
        // vf_invntt_calls[i] = mldsa_prof_invntt_calls;
    }

    hal_sendf("sign  failures: %d/%d", sign_failures, NITER);
    hal_sendf("verify failures: %d/%d", verify_failures, NITER);

    /* Compute min / max / avg */
    for (int op = 0; op < 3; op++) {
        uint64_t *t = (op == 0) ? t_kg : (op == 1) ? t_sg : t_vf;
        const char *name = (op == 0) ? "keygen" : (op == 1) ? "sign  " : "verify";
        uint64_t mn = t[0], mx = t[0], sum = 0;
        for (i = 0; i < NITER; i++) {
            if (t[i] < mn) mn = t[i];
            if (t[i] > mx) mx = t[i];
            sum += t[i];
        }
       /* hal_sendf("%s: min=%llu max=%llu avg=%llu ticks\n",
               name,
               (unsigned long long)mn,
               (unsigned long long)mx,
               (unsigned long long)(sum / NITER));
               */
        hal_sendf("%s:", name);
        hal_sendf("mn=%s", u64str(mn));
        hal_sendf("mx=%s", u64str(mx));
        hal_sendf("avg=%s", u64str((sum/NITER)));
    }
    // uint64_t sum_vf_ntt = 0;
    // uint64_t sum_vf_invntt = 0;
    // uint32_t sum_vf_ntt_calls = 0;
    // uint32_t sum_vf_invntt_calls = 0;

    // for (i = 0; i < NITER; i++) {
    //     sum_vf_ntt += vf_ntt[i];
    //     sum_vf_invntt += vf_invntt[i];
    //     sum_vf_ntt_calls += vf_ntt_calls[i];
    //     sum_vf_invntt_calls += vf_invntt_calls[i];
    // }

    // hal_sendf("verify NTT breakdown:");
    // hal_sendf("ntt avg cycles=%lu", (unsigned long)(sum_vf_ntt / NITER));
    // hal_sendf("ntt avg calls=%lu", (unsigned long)(sum_vf_ntt_calls / NITER));
    // hal_sendf("invntt avg cycles=%lu", (unsigned long)(sum_vf_invntt / NITER));
    // hal_sendf("invntt avg calls=%lu", (unsigned long)(sum_vf_invntt_calls / NITER));
    // hal_sendf("============================");
    return 0;
}
