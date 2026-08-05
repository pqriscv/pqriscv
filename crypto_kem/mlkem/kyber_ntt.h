#ifndef KYBER_NTT_H
#define KYBER_NTT_H

/*
 * kyber_ntt.h — Public interface for the Kyber NTT assembly routines.
 *
 * Targets:
 *   RISC-V : reduce_rv.S + fastntt_rv.S  (RV32IM + F extension)
 *   ARM    : reduce_arm.S + fastntt_arm.S (Cortex-M4 + DSP + VFPv4-SP)
 *
 * Coefficient layout
 * ------------------
 * All functions operate on a poly[256] array of int16_t coefficients stored
 * as 128 packed int32_t words: word[i] = (poly[2i+1] << 16) | (uint16_t)poly[2i].
 * That is, two consecutive coefficients share each 32-bit word, low-index
 * coefficient in the lower 16 bits.
 *
 * Modulus: q = 3329 (Kyber)
 */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------------------
 * ntt_selftest()
 *
 * Runs NTT on a fixed polynomial (r[i] = i mod q) and verifies the first 16
 * output coefficients against a Python-computed reference.
 * Returns 1 if all match, 0 on any mismatch (which also prints details via
 * the hal_send_str path when called from within the firmware).
 *
 * Only available when KYBER_ASM_NTT is defined.
 * ------------------------------------------------------------------------- */
#ifdef KYBER_ASM_NTT
int ntt_selftest(void);
void ntt_selftest_dump(int16_t out[16]);
#endif


/* ---------------------------------------------------------------------------
 * asm_barrett_reduce(poly)
 *
 * Barrett-reduces every coefficient of poly modulo q = 3329.
 * Input range : any value representable in a signed 16-bit integer.
 * Output range: approximately [0, q) — one canonical step.
 *
 * Call after polynomial addition / subtraction to keep coefficients bounded.
 * ------------------------------------------------------------------------- */
void asm_barrett_reduce(int16_t poly[256]);

/* ---------------------------------------------------------------------------
 * asm_fromplant(poly)
 *
 * Converts all 256 coefficients from Plantard domain to the standard range.
 * Uses the precomputed Plantard constant:
 *   plantconst = (Plant_const^2 mod q) * (2^16)^{-1} mod 2^32 = 0x97F44F6C
 *
 * Must be called after a Plantard-domain inverse NTT, before the result
 * is used in further polynomial arithmetic or encoding.
 * ------------------------------------------------------------------------- */
void asm_fromplant(int16_t poly[256]);

/* ---------------------------------------------------------------------------
 * ntt_fast(poly, twiddle_ptr)
 *
 * In-place forward NTT over Z_q[x]/(x^256+1).
 * poly        : 256 packed int16_t coefficients (128 int32_t words, in-place).
 * twiddle_ptr : pointer to the 127-entry Plantard twiddle table
 *               (see twiddles.c / kyber_ntt_twiddles[]).
 *
 * The twiddle pointer is consumed (advanced) during the call.  Pass a fresh
 * pointer on every invocation:
 *   ntt_fast(poly, kyber_ntt_twiddles);   // OK — table not modified
 *
 * After ntt_fast the coefficients are in NTT / Plantard domain.
 * Call asm_fromplant() + asm_barrett_reduce() to convert back after INTT.
 * ------------------------------------------------------------------------- */
void ntt_fast(int32_t poly[128], const int32_t twiddle_ptr[127]);

/* ---------------------------------------------------------------------------
 * Twiddle-factor table (defined in twiddles.c)
 *
 * 127 int32_t entries in Plantard form: round(zeta_k * 2^32 / q).
 * Layout:
 *   [0]      1 value  — layer 7 twiddle  (len=128 CT group)
 *   [1..2]   2 values — layer 6 twiddles (len=64)
 *   [3..6]   4 values — layer 5 twiddles (len=32)
 *   [7..14]  8 values — layer 4 twiddles (len=16, mul_twiddle_plant step)
 *   [15..126] 112 values — layers 3,2,1  (16 groups × 7 values each)
 * ------------------------------------------------------------------------- */
extern const int32_t kyber_ntt_twiddles[127];

#ifdef __cplusplus
}
#endif
#endif /* KYBER_NTT_H */
