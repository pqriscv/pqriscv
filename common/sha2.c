/*
 * sha2.c — SHA-256 and SHA-512  (FIPS 180-4)
 *
 * Public domain.
 * Both algorithms share the same structure; only the word size, constants,
 * and output length differ.
 */

#include "sha2.h"
#include <string.h>

/* =========================================================================
 * Byte order helpers — big-endian network order for SHA-2
 * ========================================================================= */

static inline uint32_t load_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] <<  8) |  (uint32_t)p[3];
}

static inline void store_be32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >>  8); p[3] = (uint8_t) v;
}

static inline uint64_t load_be64(const uint8_t *p)
{
    return ((uint64_t)p[0] << 56) | ((uint64_t)p[1] << 48) |
           ((uint64_t)p[2] << 40) | ((uint64_t)p[3] << 32) |
           ((uint64_t)p[4] << 24) | ((uint64_t)p[5] << 16) |
           ((uint64_t)p[6] <<  8) |  (uint64_t)p[7];
}

static inline void store_be64(uint8_t *p, uint64_t v)
{
    p[0]=(uint8_t)(v>>56); p[1]=(uint8_t)(v>>48);
    p[2]=(uint8_t)(v>>40); p[3]=(uint8_t)(v>>32);
    p[4]=(uint8_t)(v>>24); p[5]=(uint8_t)(v>>16);
    p[6]=(uint8_t)(v>> 8); p[7]=(uint8_t) v;
}

/* =========================================================================
 * SHA-256
 * ========================================================================= */

/* First 32 bits of the fractional parts of cube roots of the first 64 primes */
static const uint32_t sha256_K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

/* Initial hash values: fractional parts of sqrt of first 8 primes */
static const uint32_t sha256_H0[8] = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
};

#define ROR32(x, n)  (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(e,f,g)    (((e) & (f)) ^ (~(e) & (g)))
#define MAJ(a,b,c)   (((a) & (b)) ^ ((a) & (c)) ^ ((b) & (c)))
#define EP0_256(a)   (ROR32(a,2)  ^ ROR32(a,13) ^ ROR32(a,22))
#define EP1_256(e)   (ROR32(e,6)  ^ ROR32(e,11) ^ ROR32(e,25))
#define SIG0_256(x)  (ROR32(x,7)  ^ ROR32(x,18) ^ ((x) >> 3))
#define SIG1_256(x)  (ROR32(x,17) ^ ROR32(x,19) ^ ((x) >> 10))

static void sha256_compress(uint32_t state[8], const uint8_t block[64])
{
    uint32_t W[64], a, b, c, d, e, f, g, h, T1, T2;
    int i;

    for (i = 0; i < 16; i++) W[i] = load_be32(block + 4 * i);
    for (i = 16; i < 64; i++)
        W[i] = SIG1_256(W[i-2]) + W[i-7] + SIG0_256(W[i-15]) + W[i-16];

    a = state[0]; b = state[1]; c = state[2]; d = state[3];
    e = state[4]; f = state[5]; g = state[6]; h = state[7];

    for (i = 0; i < 64; i++) {
        T1 = h + EP1_256(e) + CH(e,f,g) + sha256_K[i] + W[i];
        T2 = EP0_256(a) + MAJ(a,b,c);
        h = g; g = f; f = e; e = d + T1;
        d = c; c = b; b = a; a = T1 + T2;
    }

    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

void sha256_init(sha256_ctx *ctx)
{
    memcpy(ctx->state, sha256_H0, sizeof(sha256_H0));
    ctx->count  = 0;
    ctx->buflen = 0;
}

void sha256_update(sha256_ctx *ctx, const uint8_t *in, size_t inlen)
{
    ctx->count += (uint64_t)inlen << 3;

    while (inlen > 0) {
        size_t take = 64 - ctx->buflen;
        if (take > inlen) take = inlen;
        memcpy(ctx->buf + ctx->buflen, in, take);
        ctx->buflen += take;
        in    += take;
        inlen -= take;
        if (ctx->buflen == 64) {
            sha256_compress(ctx->state, ctx->buf);
            ctx->buflen = 0;
        }
    }
}

void sha256_final(sha256_ctx *ctx, uint8_t digest[32])
{
    uint8_t pad[64] = {0};
    uint8_t len_enc[8];
    unsigned int padlen;
    int i;

    /* Capture bit-length NOW, before sha256_update adds the padding bytes
     * to ctx->count (sha256_update increments count on every call). */
    store_be64(len_enc, ctx->count);

    /* Append 0x80 byte */
    pad[0] = 0x80;
    padlen = (ctx->buflen < 56) ? (56 - ctx->buflen) : (120 - ctx->buflen);
    sha256_update(ctx, pad, padlen);

    /* Append original message bit-length */
    sha256_update(ctx, len_enc, 8);

    for (i = 0; i < 8; i++)
        store_be32(digest + 4 * i, ctx->state[i]);

    memset(ctx, 0, sizeof(*ctx));
}

void sha256(uint8_t digest[32], const uint8_t *in, size_t inlen)
{
    sha256_ctx ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, in, inlen);
    sha256_final(&ctx, digest);
}

/* =========================================================================
 * SHA-512
 * ========================================================================= */

static const uint64_t sha512_K[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL,
    0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL,
    0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL,
    0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL,
    0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL,
    0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL,
    0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL,
    0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL,
    0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL,
    0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL,
    0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL,
    0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL,
    0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL,
    0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL,
    0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL,
    0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL,
    0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL,
    0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL,
    0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL,
    0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL,
    0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL,
};

static const uint64_t sha512_H0[8] = {
    0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL,
    0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
    0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL,
    0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL,
};

#define ROR64(x, n)  (((x) >> (n)) | ((x) << (64 - (n))))
#define EP0_512(a)   (ROR64(a,28) ^ ROR64(a,34) ^ ROR64(a,39))
#define EP1_512(e)   (ROR64(e,14) ^ ROR64(e,18) ^ ROR64(e,41))
#define SIG0_512(x)  (ROR64(x, 1) ^ ROR64(x, 8) ^ ((x) >> 7))
#define SIG1_512(x)  (ROR64(x,19) ^ ROR64(x,61) ^ ((x) >> 6))

static void sha512_compress(uint64_t state[8], const uint8_t block[128])
{
    uint64_t W[80], a, b, c, d, e, f, g, h, T1, T2;
    int i;

    for (i = 0; i < 16; i++) W[i] = load_be64(block + 8 * i);
    for (i = 16; i < 80; i++)
        W[i] = SIG1_512(W[i-2]) + W[i-7] + SIG0_512(W[i-15]) + W[i-16];

    a = state[0]; b = state[1]; c = state[2]; d = state[3];
    e = state[4]; f = state[5]; g = state[6]; h = state[7];

    for (i = 0; i < 80; i++) {
        T1 = h + EP1_512(e) + CH(e,f,g) + sha512_K[i] + W[i];
        T2 = EP0_512(a) + MAJ(a,b,c);
        h = g; g = f; f = e; e = d + T1;
        d = c; c = b; b = a; a = T1 + T2;
    }

    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

void sha512_init(sha512_ctx *ctx)
{
    memcpy(ctx->state, sha512_H0, sizeof(sha512_H0));
    ctx->count[0] = ctx->count[1] = 0;
    ctx->buflen   = 0;
}

void sha512_update(sha512_ctx *ctx, const uint8_t *in, size_t inlen)
{
    uint64_t bits_lo = (uint64_t)inlen << 3;
    ctx->count[0] += bits_lo;
    if (ctx->count[0] < bits_lo) ctx->count[1]++;
    ctx->count[1] += (uint64_t)inlen >> 61;

    while (inlen > 0) {
        size_t take = 128 - ctx->buflen;
        if (take > inlen) take = inlen;
        memcpy(ctx->buf + ctx->buflen, in, take);
        ctx->buflen += take;
        in    += take;
        inlen -= take;
        if (ctx->buflen == 128) {
            sha512_compress(ctx->state, ctx->buf);
            ctx->buflen = 0;
        }
    }
}

void sha512_final(sha512_ctx *ctx, uint8_t digest[64])
{
    uint8_t pad[128] = {0};
    uint8_t len_enc[16];
    unsigned int padlen;
    int i;

    /* Capture bit-length BEFORE sha512_update adds padding to ctx->count */
    store_be64(len_enc,     ctx->count[1]);
    store_be64(len_enc + 8, ctx->count[0]);

    pad[0] = 0x80;
    padlen = (ctx->buflen < 112) ? (112 - ctx->buflen) : (240 - ctx->buflen);
    sha512_update(ctx, pad, padlen);

    sha512_update(ctx, len_enc, 16);

    for (i = 0; i < 8; i++)
        store_be64(digest + 8 * i, ctx->state[i]);

    memset(ctx, 0, sizeof(*ctx));
}

void sha512(uint8_t digest[64], const uint8_t *in, size_t inlen)
{
    sha512_ctx ctx;
    sha512_init(&ctx);
    sha512_update(&ctx, in, inlen);
    sha512_final(&ctx, digest);
}
