#ifndef API_H
#define API_H

#include <stddef.h>
#include <stdint.h>

#define CRYPTO_PUBLICKEYBYTES  2592
#define CRYPTO_SECRETKEYBYTES  4896
#define CRYPTO_BYTES           4627
#define CRYPTO_ALGNAME         "ml-dsa-87"

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
