#ifndef API_H
#define API_H

#include "sign.h"

#include <stddef.h>
#include <stdint.h>
#include "params.h"


// #define CRYPTO_PUBLICKEYBYTES  1312
// #define CRYPTO_SECRETKEYBYTES  2560
// #define CRYPTO_BYTES           2420
//  CRYPTO_ALGNAME         "haetae2"

int crypto_sign_keypair(uint8_t *pk, uint8_t *sk);

int crypto_sign_signature(uint8_t *sig, size_t *siglen,
                          const uint8_t *m, size_t mlen,
                          const uint8_t *ctx, size_t ctxlen,
                          const uint8_t *sk);

int crypto_sign_verify(const uint8_t *sig, size_t siglen,
                       const uint8_t *m, size_t mlen,
                       const uint8_t *ctx, size_t ctxlen,
                       const uint8_t *pk);

#endif /* API_H */
