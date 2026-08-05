#ifndef API_H
#define API_H

/*
 * api.h — ML-KEM-768  (FIPS 203, security category 3)
 */

#define CRYPTO_SECRETKEYBYTES   2400
#define CRYPTO_PUBLICKEYBYTES   1184
#define CRYPTO_CIPHERTEXTBYTES  1088
#define CRYPTO_BYTES              32

#define CRYPTO_ALGNAME "ML-KEM-768"

int crypto_kem_keypair(unsigned char *pk, unsigned char *sk);
int crypto_kem_enc(unsigned char *ct, unsigned char *ss, const unsigned char *pk);
int crypto_kem_dec(unsigned char *ss, const unsigned char *ct, const unsigned char *sk);

#endif /* API_H */
