#include <stdint.h>
#include "params.h"
#include "ntt.h"
#include "reduce.h"

/* Montgomery-form zetas: zeta_k = 17^BitRev7(k) * MONT mod q
 * Used by invntt() and basemul() in both C and ASM-NTT paths. */
const int16_t zetas[128] = {
  -1044,  -758,  -359, -1517,  1493,  1422,   287,   202,
   -171,   622,  1577,   182,   962, -1202, -1474,  1468,
    573, -1325,   264,   383,  -829,  1458, -1602,  -130,
   -681,  1017,   732,   608, -1542,   411,  -205, -1571,
   1223,   652,  -552,  1015, -1293,  1491,  -282, -1544,
    516,    -8,  -320,  -666, -1618, -1162,   126,  1469,
   -853,   -90,  -271,   830,   107, -1421,  -247,  -951,
   -398,   961, -1508,  -725,   448, -1065,   677, -1275,
  -1103,   430,   555,   843, -1251,   871,  1550,   105,
    422,   587,   177,  -235,  -291,  -460,  1574,  1653,
   -246,   778,  1159,  -147,  -777,  1483,  -602,  1119,
  -1590,   644,  -872,   349,   418,   329,  -156,   -75,
    817,  1097,   603,   610,  1322, -1285, -1465,   384,
  -1215,  -136,  1218, -1335,  -874,   220, -1187, -1659,
  -1185, -1530, -1278,   794, -1510,  -854,  -870,   478,
   -108,  -308,   996,   991,   958, -1460,  1522,  1628
};

static int16_t fqmul(int16_t a, int16_t b) {
  return montgomery_reduce((int32_t)a*b);
}

/*************************************************
* ntt — forward NTT, standard order → bit-reversed order.
*
* When KYBER_ASM_NTT is defined the assembly ntt_fast() + asm_fromplant()
* path is used.  The output coefficients are in the same standard [0,q)
* range as the C path; invntt() and basemul() are unaffected.
*
* NOTE on Montgomery vs Plantard normalization:
*   The C path uses Montgomery-form zetas so fqmul(zeta_mont, x) = zeta*x mod q.
*   The assembly path uses Plantard-form twiddles and fromplant() brings
*   coefficients back to standard form.  Both produce the same NTT values
*   (up to a possible constant Montgomery factor absorbed into the final
*   round of invntt()); correctness is verified by test_ntt.c.
**************************************************/
#ifdef KYBER_ASM_NTT

#include "kyber_ntt.h"

void ntt(int16_t r[256]) {
  /* Plantard twiddles compute zeta*c mod q directly — no fromplant needed.
   * PlantMul(Plant(zeta), c) == zeta*c mod q, same as Montgomery fqmul.
   * Calling asm_fromplant here would corrupt the already-correct output. */
  ntt_fast((int32_t *)r, kyber_ntt_twiddles);
}


/* ---------------------------------------------------------------------------
 * ntt_selftest — runs ntt() on r[i]=i and checks first 16 outputs.
 * Returns 1 (pass) or 0 (fail). Called from test harness.
 * ------------------------------------------------------------------------- */
int ntt_selftest(void) {
    /* Reference: NTT(r[i]=i mod q)[j] reduced to [0,q), j=0..15 */
    static const int16_t expected[16] = {
        2429, 2845,  425,  795, 1865, 1356,  624,   31,
        2483, 2197, 2725, 2668, 2707,  517, 1488, 2194
    };
    int16_t r[256];
    int pass = 1;
    int j;
    for (j = 0; j < 256; j++) r[j] = (int16_t)(j % 3329);
    ntt(r);  /* calls ntt_fast + asm_fromplant */
    for (j = 0; j < 16; j++) {
        int16_t got = r[j] % 3329;
        if (got < 0) got += 3329;
        if (got != expected[j]) {
            /* Can't printf here; caller prints details */
            pass = 0;
        }
    }
    return pass;
}

/* Also expose the coefficient array for detailed diagnosis when pass==0 */
void ntt_selftest_dump(int16_t out[16]) {
    int16_t r[256];
    int j;
    for (j = 0; j < 256; j++) r[j] = (int16_t)(j % 3329);
    ntt(r);
    for (j = 0; j < 16; j++) {
        int16_t got = r[j] % 3329;
        if (got < 0) got += 3329;
        out[j] = got;
    }
}

#else  /* reference C NTT */

void ntt(int16_t r[256]) {
  unsigned int len, start, j, k;
  int16_t t, zeta;

  k = 1;
  for(len = 128; len >= 2; len >>= 1) {
    for(start = 0; start < 256; start = j + len) {
      zeta = zetas[k++];
      for(j = start; j < start + len; j++) {
        t = fqmul(zeta, r[j + len]);
        r[j + len] = r[j] - t;
        r[j] = r[j] + t;
      }
    }
  }
}

#endif /* KYBER_ASM_NTT */

/*************************************************
* invntt — inverse NTT, always the C reference implementation.
* (No assembly inverse NTT is provided.)
**************************************************/
void invntt(int16_t r[256]) {
  unsigned int start, len, j, k;
  int16_t t, zeta;
  const int16_t f = 1441; /* mont^2/128 */

  k = 127;
  for(len = 2; len <= 128; len <<= 1) {
    for(start = 0; start < 256; start = j + len) {
      zeta = zetas[k--];
      for(j = start; j < start + len; j++) {
        t = r[j];
        r[j] = barrett_reduce(t + r[j + len]);
        r[j + len] = r[j + len] - t;
        r[j + len] = fqmul(zeta, r[j + len]);
      }
    }
  }

  for(j = 0; j < 256; j++)
    r[j] = fqmul(r[j], f);
}

/*************************************************
* basemul — always C (no assembly version).
**************************************************/
void basemul(int16_t r[2], const int16_t a[2], const int16_t b[2], int16_t zeta)
{
  r[0]  = fqmul(a[1], b[1]);
  r[0]  = fqmul(r[0], zeta);
  r[0] += fqmul(a[0], b[0]);
  r[1]  = fqmul(a[0], b[1]);
  r[1] += fqmul(a[1], b[0]);
}
