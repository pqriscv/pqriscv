#include <stddef.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include "hal.h"

#include "api.h"
#include "fndsa.h"
#include "randombytes.h"


static void hal_sendf_debug(const char *fmt, ...)
{
    char buf[128];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    hal_send_str(buf);
}

/* We use the signature size to autodetect the degree. */
#define LOGN (CRYPTO_BYTES == FNDSA_SIGNATURE_SIZE(9) ? 9 : 10)

int crypto_sign_keypair(unsigned char *pk, unsigned char *sk)
{
	uint8_t seed[40];
	randombytes(seed, sizeof seed);
	fndsa_keygen_seeded(LOGN, seed, sizeof seed, sk, pk);
	return 0;
}

int crypto_sign(unsigned char *sm, size_t *smlen,
				const unsigned char *m, size_t mlen,
				const unsigned char *sk)
{
	if (m != sm)
	{
		memmove(sm, m, mlen);
	}
	uint8_t seed[40];
	randombytes(seed, sizeof seed);
	size_t j = fndsa_sign_seeded(sk, FNDSA_SIGN_KEY_SIZE(LOGN),
								 NULL, 0, FNDSA_HASH_ID_RAW, m, mlen,
								 seed, sizeof seed, sm + mlen, FNDSA_SIGNATURE_SIZE(LOGN));
	if (j == 0)
	{
		return -1;
	}
	*smlen = mlen + FNDSA_SIGNATURE_SIZE(LOGN);
	return 0;
}

int crypto_sign_open(unsigned char *m, size_t *mlen,
					 const unsigned char *sm, size_t smlen,
					 const unsigned char *pk)
{
	hal_sendf_debug("============================");
	if (smlen < FNDSA_SIGNATURE_SIZE(LOGN))
	{
		return -1;
	}
	hal_sendf_debug("==============@==============");

	size_t dlen = smlen - FNDSA_SIGNATURE_SIZE(LOGN);
	uint8_t tmp[((size_t)4 << LOGN) + 31];
	if (!fndsa_verify_temp(sm + dlen, FNDSA_SIGNATURE_SIZE(LOGN),
						   pk, FNDSA_VRFY_KEY_SIZE(LOGN),
						   NULL, 0, FNDSA_HASH_ID_RAW, sm, dlen, tmp, sizeof tmp))
	{
		hal_sendf_debug("==============return -1 fndsa_verify_temp==============");
		return -1;
	}
	if (m != sm)
	{
		memmove(m, sm, dlen);
	}
	*mlen = dlen;
	return 0;
}

/* Detached-signature API: unlike crypto_sign()/crypto_sign_open() above,
 * these write/read only the signature itself (FNDSA_SIGNATURE_SIZE(LOGN)
 * bytes) into/from sig, never the message. crypto_sign()'s combined
 * "sm = m || sig" layout needs a buffer of mlen + FNDSA_SIGNATURE_SIZE(LOGN)
 * bytes; delegating to it here would overflow a sig buffer sized for the
 * detached signature alone. */
int crypto_sign_signature(uint8_t *sig, size_t *siglen,
						  const uint8_t *m, size_t mlen,
						  const uint8_t *ctx, size_t ctxlen,
						  const uint8_t *sk)
{
	uint8_t seed[40];
	randombytes(seed, sizeof seed);
	size_t j = fndsa_sign_seeded(sk, FNDSA_SIGN_KEY_SIZE(LOGN),
								 ctx, ctxlen, FNDSA_HASH_ID_RAW, m, mlen,
								 seed, sizeof seed, sig, FNDSA_SIGNATURE_SIZE(LOGN));
	if (j == 0)
	{
		return -1;
	}
	*siglen = FNDSA_SIGNATURE_SIZE(LOGN);
	return 0;
}

int crypto_sign_verify(const uint8_t *sig, size_t siglen,
					   const uint8_t *m, size_t mlen,
					   const uint8_t *ctx, size_t ctxlen,
					   const uint8_t *pk)
{
	if (siglen != FNDSA_SIGNATURE_SIZE(LOGN))
	{
		return -1;
	}
	uint8_t tmp[((size_t)4 << LOGN) + 31];
	if (!fndsa_verify_temp(sig, siglen, pk, FNDSA_VRFY_KEY_SIZE(LOGN),
						   ctx, ctxlen, FNDSA_HASH_ID_RAW, m, mlen, tmp, sizeof tmp))
	{
		return -1;
	}
	return 0;
}