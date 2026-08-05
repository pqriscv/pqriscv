/*
 * symmetric-shake.c — Dilithium/ML-DSA XOF stream initialisers
 *
 * Implements the two stream init functions declared in symmetric.h.
 * The SHAKE state is absorbed with seed || nonce16le, then finalised
 * so that subsequent shake{128,256}_squeezeblocks calls produce the
 * pseudorandom output needed by poly_uniform / poly_uniform_eta /
 * poly_uniform_gamma1.
 */

#include <stdint.h>
#include <string.h>
#include "params.h"
#include "symmetric.h"
#include "fips202.h"

/*
 * dilithium_shake_stream128_init
 *
 * Seed SHAKE-128 with rho (32 bytes) || nonce16le (2 bytes).
 * Used by poly_uniform to expand the public matrix A.
 */
void dilithium_shake_stream128_init(stream128_state *state,
                                    const uint8_t seed[SEEDBYTES],
                                    uint16_t nonce)
{
    uint8_t t[2];
    t[0] = (uint8_t)(nonce);
    t[1] = (uint8_t)(nonce >> 8);

    shake128_init(state);
    shake128_absorb(state, seed, SEEDBYTES);
    shake128_absorb(state, t, 2);
    shake128_finalize(state);
}

/*
 * dilithium_shake_stream256_init
 *
 * Seed SHAKE-256 with rhoprime/key (64 bytes) || nonce16le (2 bytes).
 * Used by poly_uniform_eta and poly_uniform_gamma1.
 */
void dilithium_shake_stream256_init(stream256_state *state,
                                    const uint8_t seed[CRHBYTES],
                                    uint16_t nonce)
{
    uint8_t t[2];
    t[0] = (uint8_t)(nonce);
    t[1] = (uint8_t)(nonce >> 8);

    shake256_init(state);
    shake256_absorb(state, seed, CRHBYTES);
    shake256_absorb(state, t, 2);
    shake256_finalize(state);
}
