#ifndef API_H
#define API_H

/*
 * api.h — ML-KEM-512  (FIPS 203, security category 1)
 *
 * Key sizes and function declarations follow the pqclean/pqm4 convention.
 * Implement the three functions in your scheme source files.
 */

#define CRYPTO_SECRETKEYBYTES   1632
#define CRYPTO_PUBLICKEYBYTES    800
#define CRYPTO_CIPHERTEXTBYTES   768
#define CRYPTO_BYTES              32

#define CRYPTO_ALGNAME "ML-KEM-512"

int crypto_kem_keypair(unsigned char *pk, unsigned char *sk);
int crypto_kem_enc(unsigned char *ct, unsigned char *ss, const unsigned char *pk);
int crypto_kem_dec(unsigned char *ss, const unsigned char *ct, const unsigned char *sk);

#endif /* API_H */
