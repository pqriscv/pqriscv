#ifndef API_H
#define API_H

#include <stddef.h>
#include <stdint.h>

#define CRYPTO_PUBLICKEYBYTES  1952
#define CRYPTO_SECRETKEYBYTES  4032
#define CRYPTO_BYTES           3309
#define CRYPTO_ALGNAME         "ml-dsa-65"

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
