#ifndef SYMMETRIC_H
#define SYMMETRIC_H

/*
 * symmetric.h — Dilithium/ML-DSA symmetric primitive layer
 *
 * Maps the stream128/stream256 XOF abstraction used throughout
 * poly.c and polyvec.c to SHAKE-128/SHAKE-256 from fips202.h.
 *
 * stream128: SHAKE-128 seeded with rho (SEEDBYTES=32) + nonce16
 * stream256: SHAKE-256 seeded with rhoprime (CRHBYTES=64) + nonce16
 */

#include <stdint.h>
#include "fips202.h"
#include "params.h"

typedef keccak_state stream128_state;
typedef keccak_state stream256_state;

#define STREAM128_BLOCKBYTES SHAKE128_RATE
#define STREAM256_BLOCKBYTES SHAKE256_RATE

#define DILITHIUM_NAMESPACE_INTERNAL(s) dilithium_shake_##s

void DILITHIUM_NAMESPACE_INTERNAL(stream128_init)(stream128_state *state,
                                                  const uint8_t seed[SEEDBYTES],
                                                  uint16_t nonce);

void DILITHIUM_NAMESPACE_INTERNAL(stream256_init)(stream256_state *state,
                                                  const uint8_t seed[CRHBYTES],
                                                  uint16_t nonce);

#define stream128_init(STATE, SEED, NONCE) \
    DILITHIUM_NAMESPACE_INTERNAL(stream128_init)(STATE, SEED, NONCE)
#define stream128_squeezeblocks(OUT, OUTBLOCKS, STATE) \
    shake128_squeezeblocks(OUT, OUTBLOCKS, STATE)

#define stream256_init(STATE, SEED, NONCE) \
    DILITHIUM_NAMESPACE_INTERNAL(stream256_init)(STATE, SEED, NONCE)
#define stream256_squeezeblocks(OUT, OUTBLOCKS, STATE) \
    shake256_squeezeblocks(OUT, OUTBLOCKS, STATE)

#endif /* SYMMETRIC_H */
