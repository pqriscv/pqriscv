#ifndef AES_H
#define AES_H

/*
 * aes.h — AES-128 and AES-256 (ECB, used by nistrng)
 *
 * Only ECB encryption is provided here since that is all the NIST CTR-DRBG
 * needs.  Add CBC/CTR wrappers if you need them for scheme implementations.
 *
 * NOTE: this implementation is NOT constant-time and is suitable for use
 *       in the test harness (KAT generation) only, NOT for secret-key
 *       operations in the scheme itself.
 *
 * Public domain.
 */

#include <stdint.h>

/* Key lengths in bytes */
#define AES128_KEY_BYTES  16
#define AES256_KEY_BYTES  32
#define AES_BLOCK_BYTES   16

/* Expanded key context — 15 round-keys × 4 words each (covers AES-256) */
typedef struct {
    uint32_t rk[60];   /* round-key words            */
    int      nr;        /* number of rounds (10 or 14) */
} aes_ctx;

/*
 * Expand a 128-bit or 256-bit key.
 * key_bytes must be AES128_KEY_BYTES (16) or AES256_KEY_BYTES (32).
 */
void aes_key_expand(aes_ctx *ctx, const uint8_t *key, int key_bytes);

/*
 * Encrypt a single 16-byte block in ECB mode.
 */
void aes_encrypt_block(const aes_ctx *ctx,
                       uint8_t        out[AES_BLOCK_BYTES],
                       const uint8_t  in [AES_BLOCK_BYTES]);

/*
 * Convenience: AES-256 ECB (as needed by nistrng).
 */
void aes256_ecb(uint8_t       out[AES_BLOCK_BYTES],
                const uint8_t key[AES256_KEY_BYTES],
                const uint8_t in [AES_BLOCK_BYTES]);

#endif /* AES_H */
