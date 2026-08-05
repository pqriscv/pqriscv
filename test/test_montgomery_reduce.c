#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include "hal.h"
#include "reduce.h" 
#include "ntt332.h" 
#include <string.h>
extern int32_t haetae_montgomery_reduce_asm(int64_t a);
extern int32_t haetae_2_montgomery_reduce_asm(int64_t a);

extern const int32_t zetas[N];

static void haetae_ntt332_c(int32_t a[N]) {
    unsigned int len, start, j, k;
    int32_t zeta, t;

    k = 0;
    for (len = 128; len > 0; len >>= 1) {
        for (start = 0; start < N; start = j + len) {
            zeta = zetas[++k];
            for (j = start; j < start + len; ++j) {
                t = _montgomery_reduce((int64_t)zeta * a[j + len]);
                a[j + len] = a[j] - t;
                a[j] = a[j] + t;
            }
        }
    }
}

static void hal_sendf(const char *fmt, ...)
{
    char buf[128];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    hal_send_str(buf);
}

int main(void) {
    hal_setup(CLOCK_BENCHMARK);

    int64_t tests[] = { 0, 1, -1, 64513, -64513, 6451300000LL, -6451300000LL };
    int num_tests = sizeof(tests) / sizeof(tests[0]);

    // 1. VERIFY CORRECTNESS FIRST
    for (int i = 0; i < num_tests; i++) {
        int32_t r1 = haetae_montgomery_reduce_asm(tests[i]);
        int32_t r2 = haetae_2_montgomery_reduce_asm(tests[i]);
        int32_t r3 = _montgomery_reduce(tests[i]);
        if (r1 != r3 || r2 != r3) 
        {
            hal_sendf("FAIL");
            return 1;
        }
    }
    hal_send_str("PASS\n");

    

    // 2. BENCHMARKING
    volatile int32_t dummy = 0;
    uint64_t t0, t1; 
    uint64_t time_v1, time_v2;
    int iterations = 10000;

    t0 = hal_get_time();
    for (int i = 0; i < iterations; i++) {
        dummy ^= haetae_montgomery_reduce_asm(tests[i % num_tests]);
    }
    t1 = hal_get_time();
    time_v1 = t1 - t0;

    t0 = hal_get_time();
    for (int i = 0; i < iterations; i++) {
        dummy ^= haetae_2_montgomery_reduce_asm(tests[i % num_tests]);
    }
    t1 = hal_get_time();
    time_v2 = t1 - t0;

    hal_sendf("Version 1 (original) time: %llu cycles\n", (unsigned long long)time_v1);
    hal_sendf("Version 2 (new) time:      %llu cycles\n", (unsigned long long)time_v2);

    //NTT
    static int32_t poly1[N], poly2[N], poly3[N];
    for (int i = 0; i < N; i++) poly1[i] = tests[i % num_tests];
    memcpy(poly2, poly1, sizeof(poly1));
    memcpy(poly3, poly1, sizeof(poly1));

    t0 = hal_get_time();
    for (int i = 0; i < 1000; i++) haetae_ntt332(poly1);
    t1 = hal_get_time();
    hal_sendf("NTT hand-reduce:    %llu ticks\n", (unsigned long long)(t1 - t0));

    t0 = hal_get_time();
    for (int i = 0; i < 1000; i++) haetae_ntt332_2(poly2);
    t1 = hal_get_time();
    hal_sendf("NTT godbolt-reduce: %llu ticks\n", (unsigned long long)(t1 - t0));

    t0 = hal_get_time();
    for (int i = 0; i < 1000; i++) haetae_ntt332_c(poly3);
    t1 = hal_get_time();
    hal_sendf("NTT C:              %llu ticks\n", (unsigned long long)(t1 - t0));

dummy ^= poly1[0] ^ poly2[0] ^ poly3[0];

    return 0;
}



