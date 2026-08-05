#ifndef SHA2_H
#define SHA2_H

/*
 * sha2.h — SHA-256 and SHA-512  (FIPS 180-4)
 *
 * Both incremental (ctx-based) and one-shot interfaces are provided.
 * Public domain.
 */

#include <stddef.h>
#include <stdint.h>

/* -----------------------------------------------------------------------
 * SHA-256
 * ----------------------------------------------------------------------- */

typedef struct {
    uint32_t state[8];
    uint64_t count;          /* total bits processed */
    uint8_t  buf[64];
    unsigned int buflen;
} sha256_ctx;

void sha256_init(sha256_ctx *ctx);
void sha256_update(sha256_ctx *ctx, const uint8_t *in, size_t inlen);
void sha256_final(sha256_ctx *ctx, uint8_t digest[32]);

/* One-shot */
void sha256(uint8_t digest[32], const uint8_t *in, size_t inlen);

/* -----------------------------------------------------------------------
 * SHA-512
 * ----------------------------------------------------------------------- */

typedef struct {
    uint64_t state[8];
    uint64_t count[2];       /* 128-bit bit count */
    uint8_t  buf[128];
    unsigned int buflen;
} sha512_ctx;

void sha512_init(sha512_ctx *ctx);
void sha512_update(sha512_ctx *ctx, const uint8_t *in, size_t inlen);
void sha512_final(sha512_ctx *ctx, uint8_t digest[64]);

/* One-shot */
void sha512(uint8_t digest[64], const uint8_t *in, size_t inlen);

#endif /* SHA2_H */
