#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

#include "hal.h"
#include "params.h"
#include "reduce.h"

extern const int32_t zetas[N];
extern void mldsa_ntt_asm(int32_t a[N]);
extern void mldsa_invntt_asm(int32_t a[N]);

static char buf[128];

static void sendf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    hal_send_str(buf);
}

static inline int32_t montgomery_reduce_c(int64_t a) {
    int32_t t;
    t = (int64_t)(int32_t)a * QINV;
    t = (a - (int64_t)t * Q) >> 32;
    return t;
}

static void ntt_c_ref(int32_t a[N]) {
    unsigned int len, start, j, k;
    int32_t zeta, t;

    k = 0;
    for (len = 128; len > 0; len >>= 1) {
        for (start = 0; start < N; start = j + len) {
            zeta = zetas[++k];
            for (j = start; j < start + len; ++j) {
                t = montgomery_reduce_c((int64_t)zeta * a[j + len]);
                a[j + len] = a[j] - t;
                a[j] = a[j] + t;
            }
        }
    }
}

static void invntt_c_ref(int32_t a[N]) {
    unsigned int start, len, j, k;
    int32_t t, zeta;
    const int32_t f = 41978;

    k = 256;
    for (len = 1; len < N; len <<= 1) {
        for (start = 0; start < N; start = j + len) {
            zeta = -zetas[--k];
            for (j = start; j < start + len; ++j) {
                t = a[j];
                a[j] = t + a[j + len];
                a[j + len] = t - a[j + len];
                a[j + len] = montgomery_reduce_c((int64_t)zeta * a[j + len]);
            }
        }
    }

    for (j = 0; j < N; ++j) {
        a[j] = montgomery_reduce_c((int64_t)f * a[j]);
    }
}

static int32_t a_c[N];
static int32_t a_asm[N];

static void fill_input(int32_t a[N]) {
    for (int i = 0; i < N; i++) {
        a[i] = (int32_t)((i * 12345) - 3000000);
    }
}

int main(void) {
    hal_setup(CLOCK_BENCHMARK);

    sendf("ML-DSA NTT standalone benchmark");

    fill_input(a_c);
    memcpy(a_asm, a_c, sizeof(a_c));

    ntt_c_ref(a_c);
    mldsa_ntt_asm(a_asm);

    if (memcmp(a_c, a_asm, sizeof(a_c)) != 0) {
        sendf("FAIL: forward NTT mismatch");
        return 1;
    }

    fill_input(a_c);
    memcpy(a_asm, a_c, sizeof(a_c));

    invntt_c_ref(a_c);
    mldsa_invntt_asm(a_asm);

    if (memcmp(a_c, a_asm, sizeof(a_c)) != 0) {
        sendf("FAIL: inverse NTT mismatch");
        return 1;
    }

    sendf("Correctness: PASS");

    volatile int32_t sink = 0;
    uint64_t t0, t1;
    const int iters = 1000;

    fill_input(a_c);
    t0 = hal_get_time();
    for (int i = 0; i < iters; i++) {
        ntt_c_ref(a_c);
        sink ^= a_c[i & 255];
    }
    t1 = hal_get_time();
    sendf("forward C:   %lu", (unsigned long)(t1 - t0));

    fill_input(a_asm);
    t0 = hal_get_time();
    for (int i = 0; i < iters; i++) {
        mldsa_ntt_asm(a_asm);
        sink ^= a_asm[i & 255];
    }
    t1 = hal_get_time();
    sendf("forward asm: %lu", (unsigned long)(t1 - t0));

    fill_input(a_c);
    t0 = hal_get_time();
    for (int i = 0; i < iters; i++) {
        invntt_c_ref(a_c);
        sink ^= a_c[i & 255];
    }
    t1 = hal_get_time();
    sendf("inverse C:   %lu", (unsigned long)(t1 - t0));

    fill_input(a_asm);
    t0 = hal_get_time();
    for (int i = 0; i < iters; i++) {
        mldsa_invntt_asm(a_asm);
        sink ^= a_asm[i & 255];
    }
    t1 = hal_get_time();
    sendf("inverse asm: %lu", (unsigned long)(t1 - t0));

    (void)sink;
    sendf("RESULT: PASS");
    return 0;
}