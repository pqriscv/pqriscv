#ifndef PARAMS_H
#define PARAMS_H

/* ml-dsa-44 — Dilithium mode 2 (FIPS 204 ML-DSA) */

#define DILITHIUM_MODE        2
#define DILITHIUM_RANDOMIZED_SIGNING

#define CRYPTO_ALGNAME        "ml-dsa-44"
#define DILITHIUM_NAMESPACETOP pqcrystals_dilithium2_ref
#define DILITHIUM_NAMESPACE(s) pqcrystals_dilithium2_ref_##s

#define SEEDBYTES 32
#define CRHBYTES 64
#define TRBYTES 64
#define RNDBYTES 32
#define N 256
#define Q 8380417
#define D 13
#define ROOT_OF_UNITY 1753

#define POLYT1_PACKEDBYTES  320
#define POLYT0_PACKEDBYTES  416
#define K               4
#define L               4
#define ETA             2
#define TAU             39
#define BETA            78
#define GAMMA1          (1 << 17)
#define GAMMA2          ((Q-1)/88)
#define OMEGA           80
#define CTILDEBYTES     32

#if GAMMA1 == (1 << 17)
#define POLYZ_PACKEDBYTES   576
#elif GAMMA1 == (1 << 19)
#define POLYZ_PACKEDBYTES   640
#endif

#if GAMMA2 == (Q-1)/88
#define POLYW1_PACKEDBYTES  192
#elif GAMMA2 == (Q-1)/32
#define POLYW1_PACKEDBYTES  128
#endif

#if ETA == 2
#define POLYETA_PACKEDBYTES  96
#elif ETA == 4
#define POLYETA_PACKEDBYTES 128
#endif

#define POLYVECH_PACKEDBYTES (OMEGA + K)

#define CRYPTO_PUBLICKEYBYTES (SEEDBYTES + K*POLYT1_PACKEDBYTES)
#define CRYPTO_SECRETKEYBYTES (2*SEEDBYTES + TRBYTES \
                               + L*POLYETA_PACKEDBYTES \
                               + K*POLYETA_PACKEDBYTES \
                               + K*POLYT0_PACKEDBYTES)
#define CRYPTO_BYTES (CTILDEBYTES + L*POLYZ_PACKEDBYTES + POLYVECH_PACKEDBYTES)

#endif /* PARAMS_H */
