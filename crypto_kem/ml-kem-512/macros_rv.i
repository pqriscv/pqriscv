/* macros_rv.i — RISC-V RV32IM helper macros for Kyber Plantard arithmetic
 *
 * Replaces the Cortex-M4 macros.i (and the DSP/SIMD extensions it relies on).
 * Target ISA : RV32IM base  +  F extension (fmv.x.w / fmv.w.x, fastntt only)
 *
 * Instruction mapping
 * -------------------
 *   ARM SMULWB  →  smulwb_rv    (7 insns : sign-extend half, mulh+mul, shift+or)
 *   ARM SMULWT  →  smulwt_rv    (6 insns)
 *   ARM SMLABT  →  smlabt_rv    (4 insns)
 *   ARM PKHTB   →  pkhtb_rv     (4 insns)
 *   ARM USUB16  →  usub16_rv    (7 insns)
 *   ARM UADD16  →  uadd16_rv    (7 insns)
 *   ARM VMOV    →  fmv.x.w / fmv.w.x  (1 insn, F-extension)
 *   ARM LDM/STM →  individual lw / sw
 *   ARM LDRD    →  two lw  +  addi
 *
 * Key ARM-vs-RISC-V packing difference
 * -------------------------------------
 *   The ARM code packs q=3329 into the TOP 16 bits of one register (via MOVT)
 *   so that SMLABT can read it as "Rm[T]".  In RISC-V we hold q=3329 as a
 *   plain 32-bit value and smlabt_rv multiplies by the whole register directly.
 *   No packing is needed.
 */

/* ------------------------------------------------------------------
 * smulwb_rv  dst, a, b, scr
 * dst = ((int32_t)a × (int16_t)(b & 0xFFFF)) >> 16
 *     = bits [47:16] of the signed 64-bit product a × sign_ext(b[15:0])
 * Constraints: dst≠a, dst≠scr; scr may equal b (b is read before scr is written).
 * Clobbers: dst, scr
 * ------------------------------------------------------------------ */
.macro smulwb_rv dst, a, b, scr
    slli    \scr, \b,   16
    srai    \scr, \scr, 16          /* scr = sign_extend(b[15:0])                */
    mulh    \dst, \a,   \scr        /* dst = upper 32 of signed 64-bit product   */
    mul     \scr, \a,   \scr        /* scr = lower 32 of signed 64-bit product   */
    srli    \scr, \scr, 16          /* upper-16 of lower half → [15:0]           */
    slli    \dst, \dst, 16          /* lower-16 of upper half → [31:16]          */
    or      \dst, \dst, \scr        /* dst = product bits [47:16]                */
.endm

/* ------------------------------------------------------------------
 * smulwt_rv  dst, a, b, scr
 * dst = ((int32_t)a × (int16_t)(b >> 16)) >> 16
 *     = bits [47:16] of the signed 64-bit product a × sign_ext(b[31:16])
 * Constraints: dst≠a, dst≠scr; b may equal dst (b[31:16] is read before dst is written).
 * Clobbers: dst, scr
 * ------------------------------------------------------------------ */
.macro smulwt_rv dst, a, b, scr
    srai    \scr, \b,   16          /* scr = sign_extend(b[31:16])               */
    mulh    \dst, \a,   \scr
    mul     \scr, \a,   \scr
    srli    \scr, \scr, 16
    slli    \dst, \dst, 16
    or      \dst, \dst, \scr
.endm

/* ------------------------------------------------------------------
 * smlabt_rv  dst, a, q_val, acc, scr
 * dst = acc + sign_extend(a[15:0]) × q_val
 *
 * Maps ARM SMLABT Rd, Rn, Rm, Ra  = Ra + Rn[B] × Rm[T].
 * In the original ARM code Rm[T] (the top 16 bits) held q=3329 via MOVT.
 * Here q_val is simply a register whose full value is 3329.
 * Clobbers: dst, scr
 * ------------------------------------------------------------------ */
.macro smlabt_rv dst, a, q_val, acc, scr
    slli    \scr, \a,    16
    srai    \scr, \scr,  16         /* scr = sign_extend(a[15:0])                */
    mul     \scr, \scr,  \q_val
    add     \dst, \acc,  \scr
.endm

/* ------------------------------------------------------------------
 * pkhtb_rv  dst, a, b, scr
 * dst = { a[31:16] , b[31:16] }
 * Maps ARM PKHTB Rd, Rn, Rm, ASR#16.
 * Clobbers: dst, scr
 * ------------------------------------------------------------------ */
.macro pkhtb_rv dst, a, b, scr
    srli    \scr, \b,    16         /* scr = {0…, b[31:16]}                      */
    srai    \dst, \a,    16         /* dst = sign_extend(a[31:16]) in [15:0]     */
    slli    \dst, \dst,  16         /* dst = {a[31:16], 0…}                      */
    or      \dst, \dst,  \scr
.endm

/* ------------------------------------------------------------------
 * usub16_rv  dst, a, b, s0, s1, mask
 * dst = packed16{ a[31:16]−b[31:16] , a[15:0]−b[15:0] }  (mod 2^16 each lane)
 * mask must hold 0x0000_FFFF.
 * Clobbers: dst, s0, s1
 * ------------------------------------------------------------------ */
.macro usub16_rv dst, a, b, s0, s1, mask
    srli    \s0,  \a,    16
    srli    \s1,  \b,    16
    sub     \s0,  \s0,   \s1        /* hi lane                                   */
    slli    \s0,  \s0,   16
    sub     \dst, \a,    \b         /* lo lane (hi word may be wrong)            */
    and     \dst, \dst,  \mask      /* zero hi word                              */
    or      \dst, \dst,  \s0
.endm

/* ------------------------------------------------------------------
 * uadd16_rv  dst, a, b, s0, s1, mask
 * dst = packed16{ a[31:16]+b[31:16] , a[15:0]+b[15:0] }  (mod 2^16 each lane)
 * mask must hold 0x0000_FFFF.
 * Clobbers: dst, s0, s1
 * ------------------------------------------------------------------ */
.macro uadd16_rv dst, a, b, s0, s1, mask
    srli    \s0,  \a,    16
    srli    \s1,  \b,    16
    add     \s0,  \s0,   \s1
    slli    \s0,  \s0,   16
    add     \dst, \a,    \b
    and     \dst, \dst,  \mask
    or      \dst, \dst,  \s0
.endm

/* ------------------------------------------------------------------
 * mul_twiddle_plant_rv  a, twiddle, tmp, q, qa, scr
 * Plantard twiddle multiplication on BOTH 16-bit lanes of 'a'.
 *   a_out = PlantMul(twiddle, a)  for each packed lane.
 * twiddle is read-only (preserved). a, tmp, scr are clobbered.
 * ------------------------------------------------------------------ */
.macro mul_twiddle_plant_rv a, twiddle, tmp, q, qa, scr
    smulwb_rv   \tmp, \twiddle, \a,   \scr
    smulwt_rv   \a,   \twiddle, \a,   \scr   /* a   = (tw × a[hi]) >> 16         */
    smlabt_rv   \tmp, \tmp,     \q,   \qa, \scr
    smlabt_rv   \a,   \a,       \q,   \qa, \scr
    pkhtb_rv    \a,   \a,       \tmp, \scr    /* a   = {a_hi_red, tmp_hi_red}     */
.endm

/* ------------------------------------------------------------------
 * doublebutterfly_plant_rv  a0, a1, twiddle, tmp, q, qa, scr, scr2, mask
 * Cooley-Tukey butterfly with Plantard twiddle multiplication.
 *   a0_out = a0 + PlantMul(twiddle, a1)   (both packed-16 lanes)
 *   a1_out = a0 - PlantMul(twiddle, a1)
 *
 * twiddle is READ-ONLY and is preserved after the call.  This mirrors
 * the ARM behaviour: the original SMULWB/SMULWT only read the twiddle
 * register, so the same register can be reused across consecutive calls.
 * Clobbers: a0, a1, tmp, scr, scr2
 * ------------------------------------------------------------------ */
.macro doublebutterfly_plant_rv a0, a1, twiddle, tmp, q, qa, scr, scr2, mask
    smulwb_rv   \tmp,   \twiddle, \a1,  \scr
    smulwt_rv   \a1,    \twiddle, \a1,  \scr  /* a1  = (tw × a1[hi]) >> 16       */
    smlabt_rv   \tmp,   \tmp,     \q,   \qa, \scr
    smlabt_rv   \a1,    \a1,      \q,   \qa, \scr
    pkhtb_rv    \tmp,   \a1,      \tmp, \scr  /* tmp = Plantard result           */
    /* compute subtraction first (before a0 is overwritten by addition) */
    usub16_rv   \scr2,  \a0,  \tmp, \scr, \a1, \mask  /* scr2 = a0 − tmp        */
    uadd16_rv   \a0,    \a0,  \tmp, \scr, \a1, \mask  /* a0   = a0 + tmp        */
    mv          \a1, \scr2                             /* a1   = a0 − tmp        */
.endm

/* ------------------------------------------------------------------
 * two_doublebutterfly_plant_rv  a0,a1,a2,a3, tw0,tw1, tmp,q,qa,scr,scr2,mask
 * Two independent butterflies — maps ARM two_doublebutterfly_plant.
 * ------------------------------------------------------------------ */
.macro two_doublebutterfly_plant_rv a0, a1, a2, a3, tw0, tw1, tmp, q, qa, scr, scr2, mask
    doublebutterfly_plant_rv \a0, \a1, \tw0, \tmp, \q, \qa, \scr, \scr2, \mask
    doublebutterfly_plant_rv \a2, \a3, \tw1, \tmp, \q, \qa, \scr, \scr2, \mask
.endm

/* ------------------------------------------------------------------
 * _3_layer_CT_plant_rv
 *   c0..c7           – eight coefficient registers
 *   tw1, tw2         – integer scratch for twiddle values
 *   tw_ptr           – pointer to twiddle table (MODIFIED: advanced 20 bytes)
 *   q, qa            – modulus / Plantard addend
 *   tmp, mask, scr, scr2 – scratch
 *
 * Loads twiddle factors from memory and runs 3 CT butterfly layers.
 * Maps ARM _3_layer_double_CT_16_plant.
 * ------------------------------------------------------------------ */
.macro _3_layer_CT_plant_rv c0,c1,c2,c3,c4,c5,c6,c7, tw1,tw2, tw_ptr, q,qa, tmp, mask, scr, scr2
    /* --- layer 3 : 1 twiddle factor -------------------------------- */
    lw      \tw1, 0(\tw_ptr)
    addi    \tw_ptr, \tw_ptr, 4
    two_doublebutterfly_plant_rv \c0, \c4, \c1, \c5, \tw1, \tw1, \tmp, \q, \qa, \scr, \scr2, \mask
    two_doublebutterfly_plant_rv \c2, \c6, \c3, \c7, \tw1, \tw1, \tmp, \q, \qa, \scr, \scr2, \mask

    /* --- layer 2 : 2 twiddle factors ------------------------------- */
    lw      \tw1, 0(\tw_ptr)
    lw      \tw2, 4(\tw_ptr)
    addi    \tw_ptr, \tw_ptr, 8
    two_doublebutterfly_plant_rv \c0, \c2, \c1, \c3, \tw1, \tw1, \tmp, \q, \qa, \scr, \scr2, \mask
    two_doublebutterfly_plant_rv \c4, \c6, \c5, \c7, \tw2, \tw2, \tmp, \q, \qa, \scr, \scr2, \mask

    /* --- layer 1 : 4 twiddle factors ------------------------------- */
    lw      \tw1, 0(\tw_ptr)
    lw      \tw2, 4(\tw_ptr)
    addi    \tw_ptr, \tw_ptr, 8
    two_doublebutterfly_plant_rv \c0, \c1, \c2, \c3, \tw1, \tw2, \tmp, \q, \qa, \scr, \scr2, \mask
    lw      \tw1, 0(\tw_ptr)
    lw      \tw2, 4(\tw_ptr)
    addi    \tw_ptr, \tw_ptr, 8
    two_doublebutterfly_plant_rv \c4, \c5, \c6, \c7, \tw1, \tw2, \tmp, \q, \qa, \scr, \scr2, \mask
.endm

/* ------------------------------------------------------------------
 * _3_layer_CT_plant_fp_rv
 * Same 3-layer CT structure, but twiddle factors are already in FP
 * registers xi0..xi6 (pre-loaded with flw / vldm equivalent).
 * Maps ARM _3_layer_double_CT_16_plant_fp.
 * Requires F extension for fmv.x.w.
 * ------------------------------------------------------------------ */
.macro _3_layer_CT_plant_fp_rv c0,c1,c2,c3,c4,c5,c6,c7, xi0,xi1,xi2,xi3,xi4,xi5,xi6, tw1,tw2, q,qa, tmp, mask, scr, scr2
    /* --- layer 3 --------------------------------------------------- */
    fmv.x.w \tw1, \xi0
    two_doublebutterfly_plant_rv \c0, \c4, \c1, \c5, \tw1, \tw1, \tmp, \q, \qa, \scr, \scr2, \mask
    two_doublebutterfly_plant_rv \c2, \c6, \c3, \c7, \tw1, \tw1, \tmp, \q, \qa, \scr, \scr2, \mask

    /* --- layer 2 --------------------------------------------------- */
    fmv.x.w \tw1, \xi1
    fmv.x.w \tw2, \xi2
    two_doublebutterfly_plant_rv \c0, \c2, \c1, \c3, \tw1, \tw1, \tmp, \q, \qa, \scr, \scr2, \mask
    two_doublebutterfly_plant_rv \c4, \c6, \c5, \c7, \tw2, \tw2, \tmp, \q, \qa, \scr, \scr2, \mask

    /* --- layer 1 --------------------------------------------------- */
    fmv.x.w \tw1, \xi3
    fmv.x.w \tw2, \xi4
    two_doublebutterfly_plant_rv \c0, \c1, \c2, \c3, \tw1, \tw2, \tmp, \q, \qa, \scr, \scr2, \mask
    fmv.x.w \tw1, \xi5
    fmv.x.w \tw2, \xi6
    two_doublebutterfly_plant_rv \c4, \c5, \c6, \c7, \tw1, \tw2, \tmp, \q, \qa, \scr, \scr2, \mask
.endm

/* ------------------------------------------------------------------
 * doublebarrett_rv  a, tmp, tmp2, q, bconst
 * Barrett-reduce BOTH 16-bit lanes of 'a' modulo q.
 *   x_out = x − floor(x × bconst / 2^26) × q
 * bconst = 20159 = floor(2^26 / 3329).
 * Valid for signed 16-bit inputs (range ≈ ±32768).
 * Clobbers: a, tmp, tmp2
 * ------------------------------------------------------------------ */
.macro doublebarrett_rv a, tmp, tmp2, q, bconst
    /* --- bottom lane ----------------------------------------------- */
    slli    \tmp,  \a,    16
    srai    \tmp,  \tmp,  16        /* sign_extend(a[15:0])                      */
    mul     \tmp2, \tmp,  \bconst
    srai    \tmp2, \tmp2, 26        /* quotient                                  */
    mul     \tmp2, \tmp2, \q
    sub     \tmp,  \tmp,  \tmp2     /* tmp  = reduced bottom lane                */

    /* --- top lane (clobbers a) ------------------------------------- */
    srai    \a,    \a,    16        /* sign_extend(a[31:16])                     */
    mul     \tmp2, \a,    \bconst
    srai    \tmp2, \tmp2, 26
    mul     \tmp2, \tmp2, \q
    sub     \a,    \a,    \tmp2     /* a = reduced top lane                      */

    /* --- repack { a[15:0], tmp[15:0] } ----------------------------- */
    slli    \a,    \a,    16
    slli    \tmp,  \tmp,  16
    srli    \tmp,  \tmp,  16        /* zero-extend to [15:0]                     */
    or      \a,    \a,    \tmp
.endm

/* ------------------------------------------------------------------
 * doubleplant_rv  a, tmp, q, qa, pconst, scr
 * Convert BOTH 16-bit lanes from Plantard domain to standard [0, q).
 * pconst = 0x97F44F6C  (= (Plant_const^2 mod q) × p^{-1} mod 2^32, p=2^16)
 * This is identical to mul_twiddle_plant_rv with pconst as the twiddle.
 * Clobbers: a, tmp, scr
 * ------------------------------------------------------------------ */
.macro doubleplant_rv a, tmp, q, qa, pconst, scr
    mul_twiddle_plant_rv \a, \pconst, \tmp, \q, \qa, \scr
.endm
