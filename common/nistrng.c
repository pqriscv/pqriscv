/*
 * nistrng.c — NIST AES-256-CTR DRBG  (SP 800-90A)
 *
 * Identical to the rng.c shipped in all NIST PQC submission packages.
 * Produces deterministic output from a 48-byte seed, used for KAT generation.
 *
 * Public domain.
 */

#include "nistrng.h"
#include "aes.h"
#include <string.h>

/* -------------------------------------------------------------------------
 * Internal DRBG state
 * key  : 32-byte AES-256 key
 * V    : 16-byte counter block (big-endian 128-bit counter)
 * ------------------------------------------------------------------------- */
typedef struct {
    uint8_t  key[32];
    uint8_t  V[16];
} drbg_ctx;

static drbg_ctx g_drbg;

/* Increment V as a 128-bit big-endian counter */
static void inc_ctr(uint8_t V[16])
{
    int i;
    for (i = 15; i >= 0; i--) {
        if (++V[i]) break;
    }
}

/*
 * AES-256-CTR DRBG Update function (NIST SP 800-90A §10.2.1.2).
 *
 * provided_data is 48 bytes or NULL (treated as all-zero).
 */
static void drbg_update(const uint8_t *provided_data, drbg_ctx *ctx)
{
    uint8_t tmp[48];
    uint8_t out[16];
    int i;

    /* Generate 3 AES-256-ECB blocks with sequential counter values */
    for (i = 0; i < 3; i++) {
        inc_ctr(ctx->V);
        aes256_ecb(out, ctx->key, ctx->V);
        memcpy(tmp + 16 * i, out, 16);
    }

    if (provided_data) {
        for (i = 0; i < 48; i++)
            tmp[i] ^= provided_data[i];
    }

    memcpy(ctx->key, tmp,      32);
    memcpy(ctx->V,   tmp + 32, 16);
}

/* -------------------------------------------------------------------------
 * Public API
 * ------------------------------------------------------------------------- */

void randombytes_init(const uint8_t entropy_input[48],
                      const uint8_t *personalization,
                      int security_strength)
{
    uint8_t seed[48];
    int i;
    (void)security_strength;

    if (personalization) {
        for (i = 0; i < 48; i++)
            seed[i] = entropy_input[i] ^ personalization[i];
    } else {
        memcpy(seed, entropy_input, 48);
    }

    memset(&g_drbg, 0, sizeof(g_drbg));
    drbg_update(seed, &g_drbg);
}

int randombytes_nist(uint8_t *x, size_t xlen)
{
    uint8_t block[16];
    size_t  left = xlen;
    uint8_t *out = x;

    while (left > 0) {
        inc_ctr(g_drbg.V);
        aes256_ecb(block, g_drbg.key, g_drbg.V);

        if (left >= 16) {
            memcpy(out, block, 16);
            out  += 16;
            left -= 16;
        } else {
            memcpy(out, block, left);
            left = 0;
        }
    }

    drbg_update(NULL, &g_drbg);
    return 0;
}
