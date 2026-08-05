#ifndef NISTRNG_H
#define NISTRNG_H

/*
 * nistrng.h — NIST AES-256-CTR DRBG  (SP 800-90A)
 *
 * This is the deterministic RNG used by the NIST PQC standardisation
 * process to generate Known Answer Test (KAT) vectors.  It is identical
 * to the rng.h / rng.c found in every NIST PQC submission package.
 *
 * Usage:
 *   1. Call randombytes_init() once with a 48-byte seed (key+nonce).
 *   2. Call randombytes() to produce deterministic pseudorandom bytes.
 *
 * The global state is a single AES-256-CTR DRBG instance.
 * Use randombytes_init() to reset / re-seed it.
 *
 * NOT suitable for production use — use the HAL-backed randombytes()
 * (randombytes.h) for real randomness on the target device.
 *
 * Public domain.
 */

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Seed the DRBG.
 *   entropy_input : 48 bytes of seed material.
 *   personalization: may be NULL.
 *   security_strength: ignored (always 256).
 */
void randombytes_init(const uint8_t entropy_input[48],
                      const uint8_t *personalization,
                      int security_strength);

/*
 * Generate `xlen` pseudorandom bytes into `x`.
 * Returns 0 on success.
 */
int randombytes_nist(uint8_t *x, size_t xlen);

#ifdef __cplusplus
}
#endif

#endif /* NISTRNG_H */
