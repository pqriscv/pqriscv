/*
 * test/test_primitives.c — Known-Answer Tests for all symmetric primitives
 *
 * Tests (with NIST/FIPS vectors):
 *   SHA3-256  (FIPS 202)
 *   SHA3-512  (FIPS 202)
 *   SHAKE-128 (FIPS 202)
 *   SHAKE-256 (FIPS 202)
 *   SHA-256   (FIPS 180-4)
 *   SHA-512   (FIPS 180-4)
 *   AES-256   (FIPS 197)
 *   NIST DRBG (deterministic output check)
 *
 * Build and run:
 *   make run-test-primitives
 */

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

#include "hal.h"
#include "fips202.h"
#include "sha2.h"
#include "aes.h"
#include "nistrng.h"

/* =========================================================================
 * Helpers
 * ========================================================================= */

static char _buf[256];
static void pf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(_buf, sizeof(_buf), fmt, ap);
    va_end(ap);
    hal_send_str(_buf);
}

static int total_pass = 0;
static int total_fail = 0;

/* Parse a lowercase hex string into bytes. */
static void unhex(uint8_t *out, const char *hex, size_t nbytes)
{
    size_t i;
    for (i = 0; i < nbytes; i++) {
        unsigned int hi, lo;
        hi = (hex[2*i]   >= 'a') ? (hex[2*i]   - 'a' + 10) : (hex[2*i]   - '0');
        lo = (hex[2*i+1] >= 'a') ? (hex[2*i+1] - 'a' + 10) : (hex[2*i+1] - '0');
        out[i] = (uint8_t)((hi << 4) | lo);
    }
}

/*
 * check() — compare `got` with `expected` hex string of `nbytes` bytes.
 * Prints PASS/FAIL and updates counters.
 */
static void check(const char *label,
                  const uint8_t *got, const char *expected_hex,
                  size_t nbytes)
{
    uint8_t expected[128];
    int ok;

    unhex(expected, expected_hex, nbytes);
    ok = (memcmp(got, expected, nbytes) == 0);

    if (ok) {
        pf("  PASS  %s", label);
        total_pass++;
    } else {
        /* Print first differing byte to help debugging */
        size_t i;
        for (i = 0; i < nbytes; i++) {
            if (got[i] != expected[i]) {
                pf("  FAIL  %s  [byte %u: got %02x want %02x]",
                   label, (unsigned)i, got[i], expected[i]);
                break;
            }
        }
        total_fail++;
    }
}

/* =========================================================================
 * FIPS 202 — SHA-3 and SHAKE
 *
 * Vectors from NIST FIPS 202 (and the accompanying test vector package).
 * ========================================================================= */

static void test_sha3_256(void)
{
    uint8_t h[32];
    hal_send_str("SHA3-256:");

    /* Empty input */
    sha3_256(h, (const uint8_t *)"", 0);
    check("SHA3-256(\"\")  ",
          h, "a7ffc6f8bf1ed76651c14756a061d662"
             "f580ff4de43b49fa82d80a4b80f8434a", 32);

    /* "abc" */
    sha3_256(h, (const uint8_t *)"abc", 3);
    check("SHA3-256(\"abc\")",
          h, "3a985da74fe225b2045c172d6bd390bd"
             "855f086e3e9d525b46bfe24511431532", 32);

    /* 200-byte input of 0xa3 (NIST short-message vector) */
    {
        uint8_t msg[200];
        memset(msg, 0xa3, 200);
        sha3_256(h, msg, 200);
        check("SHA3-256(200*0xa3)",
              h, "79f38adec5c20307a98ef76e8324afbf"
                 "d46cfd81b22e3973c65fa1bd9de31787", 32);
    }
}

static void test_sha3_512(void)
{
    uint8_t h[64] = {0};
    hal_send_str("SHA3-512:");

    /* Empty input */
    sha3_512(h, (const uint8_t *)"", 0);
    check("SHA3-512(\"\")  ",
          h, "a69f73cca23a9ac5c8b567dc185a756e"
             "97c982164fe25859e0d1dcc1475c80a6"
             "15b2123af1f5f94c11e3e9402c3ac558"
             "f500199d95b6d3e301758586281dcd26", 64);

    /* "abc" */
    sha3_512(h, (const uint8_t *)"abc", 3);
    check("SHA3-512(\"abc\")",
          h, "b751850b1a57168a5693cd924b6b096e"
             "08f621827444f70d884f5d0240d2712e"  /* byte 31: 2e, not 2d */
             "10e116e9192af3c91a7ec57647e39340"
             "57340b4cf408d5a56592f8274eec53f0", 64);
}

static void test_shake128(void)
{
    uint8_t out[64];
    hal_send_str("SHAKE-128:");

    /* Empty input, 32 bytes output */
    shake128(out, 32, (const uint8_t *)"", 0);
    check("SHAKE128(\"\",32) ",
          out, "7f9c2ba4e88f827d616045507605853e"
               "d73b8093f6efbc88eb1a6eacfa66ef26", 32);

    /* "abc", 32 bytes output */
    shake128(out, 32, (const uint8_t *)"abc", 3);
    check("SHAKE128(\"abc\",32)",
          out, "5881092dd818bf5cf8a3ddb793fbcba7"
               "4097d5c526a6d35f97b83351940f2cc8", 32);

    /* Empty input, 64 bytes output */
    shake128(out, 64, (const uint8_t *)"", 0);
    check("SHAKE128(\"\",64) ",
          out, "7f9c2ba4e88f827d616045507605853e"
               "d73b8093f6efbc88eb1a6eacfa66ef26"
               "3cb1eea988004b93103cfb0aeefd2a68"
               "6e01fa4a58e8a3639ca8a1e3f9ae57e2", 64);

    /* Incremental API — same result as one-shot */
    {
        keccak_state st;
        uint8_t out_inc[32];
        shake128_init(&st);
        shake128_absorb(&st, (const uint8_t *)"ab", 2);
        shake128_absorb(&st, (const uint8_t *)"c", 1);
        shake128_finalize(&st);
        shake128_squeeze(out_inc, 32, &st);

        shake128(out, 32, (const uint8_t *)"abc", 3);
        if (memcmp(out, out_inc, 32) == 0) {
            hal_send_str("  PASS  SHAKE128 incremental == one-shot");
            total_pass++;
        } else {
            hal_send_str("  FAIL  SHAKE128 incremental != one-shot");
            total_fail++;
        }
    }
}

static void test_shake256(void)
{
    uint8_t out[64];
    hal_send_str("SHAKE-256:");

    /* Empty input, 32 bytes output */
    shake256(out, 32, (const uint8_t *)"", 0);
    check("SHAKE256(\"\",32) ",
          out, "46b9dd2b0ba88d13233b3feb743eeb24"
               "3fcd52ea62b81b82b50c27646ed5762f", 32);

    /* "abc", 32 bytes output */
    shake256(out, 32, (const uint8_t *)"abc", 3);
    check("SHAKE256(\"abc\",32)",
          out, "483366601360a8771c6863080cc4114d"
               "8db44530f8f1e1ee4f94ea37e78b5739", 32);

    /* Incremental API */
    {
        keccak_state st;
        uint8_t out_inc[32];
        shake256_init(&st);
        shake256_absorb(&st, (const uint8_t *)"abc", 3);
        shake256_finalize(&st);
        shake256_squeeze(out_inc, 32, &st);

        shake256(out, 32, (const uint8_t *)"abc", 3);
        if (memcmp(out, out_inc, 32) == 0) {
            hal_send_str("  PASS  SHAKE256 incremental == one-shot");
            total_pass++;
        } else {
            hal_send_str("  FAIL  SHAKE256 incremental != one-shot");
            total_fail++;
        }
    }
}

/* =========================================================================
 * FIPS 180-4 — SHA-256 and SHA-512
 * ========================================================================= */

static void test_sha256(void)
{
    uint8_t h[32];
    hal_send_str("SHA-256:");

    /* Empty string — FIPS 180-4 §B.1 */
    sha256(h, (const uint8_t *)"", 0);
    check("SHA256(\"\")    ",
          h, "e3b0c44298fc1c149afbf4c8996fb924"
             "27ae41e4649b934ca495991b7852b855", 32);

    /* "abc" — FIPS 180-4 Appendix B.1 */
    sha256(h, (const uint8_t *)"abc", 3);
    check("SHA256(\"abc\")  ",
          h, "ba7816bf8f01cfea414140de5dae2223"
             "b00361a396177a9cb410ff61f20015ad", 32);

    /* 448-bit message — FIPS 180-4 Appendix B.2 */
    sha256(h,
           (const uint8_t *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
           56);
    check("SHA256(448-bit)",
          h, "248d6a61d20638b8e5c026930c3e6039"
             "a33ce45964ff2167f6ecedd419db06c1", 32);

    /* Incremental API */
    {
        sha256_ctx ctx;
        uint8_t h_inc[32];
        sha256_init(&ctx);
        sha256_update(&ctx, (const uint8_t *)"ab", 2);
        sha256_update(&ctx, (const uint8_t *)"c", 1);
        sha256_final(&ctx, h_inc);

        sha256(h, (const uint8_t *)"abc", 3);
        if (memcmp(h, h_inc, 32) == 0) {
            hal_send_str("  PASS  SHA256 incremental == one-shot");
            total_pass++;
        } else {
            hal_send_str("  FAIL  SHA256 incremental != one-shot");
            total_fail++;
        }
    }
}

static void test_sha512(void)
{
    uint8_t h[64];
    hal_send_str("SHA-512:");

    /* "abc" — FIPS 180-4 Appendix C.1 */
    sha512(h, (const uint8_t *)"abc", 3);
    check("SHA512(\"abc\")  ",
          h, "ddaf35a193617abacc417349ae204131"
             "12e6fa4e89a97ea20a9eeee64b55d39a"
             "2192992a274fc1a836ba3c23a3feebbd"
             "454d4423643ce80e2a9ac94fa54ca49f", 64);

    /* 448-bit message — FIPS 180-4 Appendix C.2 */
    sha512(h,
           (const uint8_t *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
           56);
    check("SHA512(448-bit)",
          h, "204a8fc6dda82f0a0ced7beb8e08a416"
             "57c16ef468b228a8279be331a703c335"
             "96fd15c13b1b07f9aa1d3bea57789ca0"
             "31ad85c7a71dd70354ec631238ca3445", 64);
}

/* =========================================================================
 * FIPS 197 — AES-256 ECB
 *
 * Test vector: FIPS 197 Appendix C.3
 *   Key       = 000102030405060708090a0b0c0d0e0f
 *               101112131415161718191a1b1c1d1e1f
 *   Plaintext = 00112233445566778899aabbccddeeff
 *   Ciphertext= 8ea2b7ca516745bfeafc49904b496089
 * ========================================================================= */

static void test_aes256(void)
{
    hal_send_str("AES-256 ECB:");

    {
        static const uint8_t key[32] = {
            0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
            0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,
            0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
            0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f,
        };
        static const uint8_t pt[16] = {
            0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
            0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff,
        };
        uint8_t ct[16];

        aes256_ecb(ct, key, pt);
        check("AES-256 FIPS197-C3",
              ct, "8ea2b7ca516745bfeafc49904b496089", 16);
    }

    /* All-zero key and plaintext */
    {
        uint8_t key[32] = {0};
        uint8_t pt[16]  = {0};
        uint8_t ct[16];

        aes256_ecb(ct, key, pt);
        check("AES-256 zero key/pt",
              ct, "dc95c078a2408989ad48a21492842087", 16);
    }
}

/* =========================================================================
 * NIST AES-256-CTR DRBG — determinism check
 *
 * No external reference vector needed: seed → generate twice, verify
 * the two calls produce different output (counter advances) and that
 * re-seeding with the same seed reproduces the first block exactly.
 * ========================================================================= */

static void test_nistrng(void)
{
    hal_send_str("NIST AES-CTR DRBG:");

    uint8_t seed[48];
    uint8_t out_a[32], out_b[32], out_c[32];
    int i;

    /* Fixed seed */
    for (i = 0; i < 48; i++) seed[i] = (uint8_t)i;

    /* First run */
    randombytes_init(seed, NULL, 256);
    randombytes_nist(out_a, 32);
    randombytes_nist(out_b, 32);

    /* Consecutive outputs must differ */
    if (memcmp(out_a, out_b, 32) != 0) {
        hal_send_str("  PASS  DRBG: consecutive outputs differ");
        total_pass++;
    } else {
        hal_send_str("  FAIL  DRBG: consecutive outputs identical!");
        total_fail++;
    }

    /* Re-seed with same seed → should reproduce out_a exactly */
    randombytes_init(seed, NULL, 256);
    randombytes_nist(out_c, 32);

    if (memcmp(out_a, out_c, 32) == 0) {
        hal_send_str("  PASS  DRBG: re-seed reproduces first output");
        total_pass++;
    } else {
        hal_send_str("  FAIL  DRBG: re-seed did not reproduce first output");
        total_fail++;
    }

    /* Different seed → different output */
    {
        uint8_t seed2[48];
        uint8_t out_d[32];
        for (i = 0; i < 48; i++) seed2[i] = (uint8_t)(i ^ 0xff);
        randombytes_init(seed2, NULL, 256);
        randombytes_nist(out_d, 32);

        if (memcmp(out_a, out_d, 32) != 0) {
            hal_send_str("  PASS  DRBG: different seeds produce different output");
            total_pass++;
        } else {
            hal_send_str("  FAIL  DRBG: different seeds produced same output!");
            total_fail++;
        }
    }
}

/* =========================================================================
 * Main
 * ========================================================================= */

int main(void)
{
    hal_setup(CLOCK_BENCHMARK);

    hal_send_str("==============================");
    hal_send_str("Primitive Known-Answer Tests");
    hal_send_str("==============================");

    test_sha3_256();
    test_sha3_512();
    test_shake128();
    test_shake256();
    test_sha256();
    test_sha512();
    test_aes256();
    test_nistrng();

    hal_send_str("------------------------------");
    pf("Results: %d passed, %d failed", total_pass, total_fail);
    hal_send_str((total_fail == 0) ? "RESULT: PASS" : "RESULT: FAIL");
    hal_send_str("==============================");

    return (total_fail == 0) ? 0 : 1;
}
