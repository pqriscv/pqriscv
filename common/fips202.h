#ifndef FIPS202_H
#define FIPS202_H

/*
 * fips202.h — SHA-3 / SHAKE  (FIPS 202)
 *
 * Provides:
 *   SHA3-256, SHA3-512
 *   SHAKE-128, SHAKE-256  (one-shot and incremental)
 *
 * Public domain — based on the reference implementation by the Keccak Team.
 * https://keccak.team/keccak_specs_summary.html
 */

#include <stddef.h>
#include <stdint.h>

/* Sponge rate constants, in bytes */
#define SHAKE128_RATE   168
#define SHAKE256_RATE   136
#define SHA3_256_RATE   136
#define SHA3_512_RATE    72

/*
 * Incremental hashing state.
 * Initialise with shake128_init / shake256_init, absorb with
 * shake128_absorb / shake256_absorb, finalise, then squeeze.
 */
typedef struct {
    uint64_t s[25];       /* 1600-bit Keccak state, in lane (64-bit) form */
    unsigned int pos;     /* byte position within current rate-block        */
} keccak_state;

/* -----------------------------------------------------------------------
 * SHAKE-128
 * ----------------------------------------------------------------------- */
void shake128_init(keccak_state *state);
void shake128_absorb(keccak_state *state, const uint8_t *in, size_t inlen);
void shake128_finalize(keccak_state *state);
void shake128_squeezeblocks(uint8_t *out, size_t nblocks, keccak_state *state);
void shake128_squeeze(uint8_t *out, size_t outlen, keccak_state *state);

/*
 * shake128_absorb_once — reset, absorb in one call, then prepare for
 * squeezeblocks.  Equivalent to init + absorb + finalize.
 */
void shake128_absorb_once(keccak_state *state,
                          const uint8_t *in, size_t inlen);

/* -----------------------------------------------------------------------
 * SHAKE-256
 * ----------------------------------------------------------------------- */
void shake256_init(keccak_state *state);
void shake256_absorb(keccak_state *state, const uint8_t *in, size_t inlen);
void shake256_finalize(keccak_state *state);
void shake256_squeezeblocks(uint8_t *out, size_t nblocks, keccak_state *state);
void shake256_squeeze(uint8_t *out, size_t outlen, keccak_state *state);
void shake256_absorb_once(keccak_state *state,
                          const uint8_t *in, size_t inlen);

/* -----------------------------------------------------------------------
 * One-shot hash functions
 * ----------------------------------------------------------------------- */
void sha3_256(uint8_t h[32], const uint8_t *in, size_t inlen);
void sha3_512(uint8_t h[64], const uint8_t *in, size_t inlen);

void shake128(uint8_t *out, size_t outlen,
              const uint8_t *in,  size_t inlen);
void shake256(uint8_t *out, size_t outlen,
              const uint8_t *in,  size_t inlen);

#endif /* FIPS202_H */
