/******************************************************************************
 * RISC-V RV32IMF port of fastntt.S
 *
 * Integrating the improved Plantard arithmetic into Kyber.
 * Fast NTT using the 3-layer double Cooley-Tukey butterfly.
 *
 * Original Cortex-M4 author:
 *   Junhao Huang, BNU-HKBU United International College, Zhuhai, China
 *   jhhuang_nuaa@126.com  (September 2022)
 *   https://eprint.iacr.org/2022/956.pdf
 *
 * RISC-V port notes
 * -----------------
 *  • Target ISA: RV32IM + F extension.
 *    The F extension is required only for fmv.x.w / fmv.w.x / flw / fsw,
 *    which replace ARM vmov / vldm / vpush / vpop.  No floating-point
 *    arithmetic is used; FP registers serve purely as extra integer storage.
 *
 *  • FP register usage mirrors ARM exactly:
 *      f0-f7   ← ARM s0-s7   (temporary coefficient storage, caller-saved)
 *      f8-f22  ← ARM s8-s22  (pre-loaded twiddle factors)
 *      f23     ← ARM s23     (saved poly pointer)
 *      f24     ← ARM s24     (loop-end sentinel)
 *      f13     ← ARM s13     (loop-end sentinel for second outer loop;
 *                              reuses the twiddle slot after first loop)
 *
 *  • ARM MOVT register-packing trick is dropped: q = 3329 lives in a plain
 *    register (s0); qa = 26632 is loaded with li inside each loop iteration.
 *
 *  • ARM ldrd → two lw + addi; ldr.w/str.w → lw/sw with immediate offsets.
 *
 * Stack frame  (88 bytes total)
 * ------------------------------
 *  sp+ 0 .. sp+32  : f24, f23, f22, f21, f20, f19, f18, f9, f8  (FP, 9×4)
 *  sp+36 .. sp+84  : s11, s10, s9, s8, s7, s6, s5, s4, s3, s2, s1, s0 (12×4)
 *  sp+84           : ra
 *
 * Integer register map
 * --------------------
 *   a0   → s1   = poly          (base pointer, advances through first loop)
 *   a1   → s2   = twiddle_ptr   (advances as twiddle table is consumed)
 *   s3   = poly0   (packed 16-bit coefficient pair)
 *   s4   = poly1
 *   s5   = poly2
 *   s6   = poly3
 *   s7   = poly4
 *   s8   = poly5
 *   s9   = poly6
 *   s10  = poly7
 *   s11  = twiddle1 (first of a twiddle pair)
 *   s0   = q = 3329
 *   t0   = twiddle2 (second twiddle in a pair / general scratch)
 *   t1   = qa = 26632  (re-loaded each iteration)
 *   t2   = tmp  (Plantard intermediate)
 *   t3   = mask16 = 0x0000_FFFF  (pre-loaded once, constant across loops)
 *   t4   = scr   (first  scratch in butterfly/SIMD macros)
 *   t5   = scr2  (second scratch in butterfly/SIMD macros)
 ******************************************************************************/

#include "macros_rv.i"

    .section .text

/* ===========================================================================
 * void ntt_fast(int32_t *poly, int32_t *twiddle_ptr)
 *
 * In-place NTT over Z_q[x]/(x^256+1), q = 3329, using Plantard arithmetic.
 * Input/output: packed pairs of 16-bit coefficients stored as int32_t words.
 * =========================================================================== */
    .global ntt_fast
    .type   ntt_fast, @function
    .align  2
ntt_fast:

    /* ------------------------------------------------------------------ */
    /* Prologue                                                             */
    /* ------------------------------------------------------------------ */

    /* Save integer callee-saved registers (ra + s0-s11 = 13 words = 52 bytes) */
    addi    sp,  sp, -52
    sw      ra,  48(sp)
    sw      s0,  44(sp)
    sw      s1,  40(sp)
    sw      s2,  36(sp)
    sw      s3,  32(sp)
    sw      s4,  28(sp)
    sw      s5,  24(sp)
    sw      s6,  20(sp)
    sw      s7,  16(sp)
    sw      s8,  12(sp)
    sw      s9,   8(sp)
    sw      s10,  4(sp)
    sw      s11,  0(sp)

    /* Save FP callee-saved registers used (f8, f9, f18-f24 = 9 words = 36 bytes)
     * ARM: vpush.w {s16-s24}  (s16-s24 are callee-saved in ARM ABI)             */
    addi    sp,  sp, -36
    fsw     f8,  32(sp)
    fsw     f9,  28(sp)
    fsw     f18, 24(sp)
    fsw     f19, 20(sp)
    fsw     f20, 16(sp)
    fsw     f21, 12(sp)
    fsw     f22,  8(sp)
    fsw     f23,  4(sp)
    fsw     f24,  0(sp)

    mv      s1,  a0                 /* poly                                      */
    mv      s2,  a1                 /* twiddle_ptr                               */

    /* ARM: movt q, #3329 — loads 3329 into top half of r12.
     * RISC-V: just use a plain register.                                        */
    li      s0, 3329                /* q                                         */

    /* Pre-load the 0x0000_FFFF mask used by all usub16/uadd16 calls.
     * lui 0x10 = 0x0001_0000, then addi -1 = 0x0000_FFFF.                      */
    lui     t3, 0x10
    addi    t3, t3, -1              /* t3 = 0x0000_FFFF                         */

    /* ------------------------------------------------------------------ */
    /* LAYER 7+6+5+4                                                        */
    /* ------------------------------------------------------------------ */

    .equ DIST,    256               /* bytes between NTT "distance" apart elems */
    .equ OFFSET,  32                /* byte offset of odd column within stride   */
    .equ STRINCR, 4                 /* bytes advanced per outer-loop iteration   */

    /* ARM: vldm twiddle_ptr!, {s8-s22}  (pre-load 15 twiddle factors)          */
    flw     f8,   0(s2)
    flw     f9,   4(s2)
    flw     f10,  8(s2)
    flw     f11, 12(s2)
    flw     f12, 16(s2)
    flw     f13, 20(s2)
    flw     f14, 24(s2)
    flw     f15, 28(s2)
    flw     f16, 32(s2)
    flw     f17, 36(s2)
    flw     f18, 40(s2)
    flw     f19, 44(s2)
    flw     f20, 48(s2)
    flw     f21, 52(s2)
    flw     f22, 56(s2)
    addi    s2,  s2, 60             /* twiddle_ptr += 15×4                       */

    /* ARM: add tmp, poly, #strincr*8  →  loop runs for 8 iterations of 4 bytes */
    addi    t0,  s1, STRINCR*8     /* t0 = loop end sentinel                    */
    fmv.w.x f24, t0                /* ARM: vmov s24, tmp                        */

.Lloop1:
    /* ARM: vmov s23, poly */
    fmv.w.x f23, s1

    /* ---- load 8 odd-column coefficient words -------------------------
     * ARM: load poly, poly0-poly3, #OFFSET, #DIST/4+OFFSET, ...         */
    lw      s3,  (OFFSET)(s1)
    lw      s4,  (DIST/4  + OFFSET)(s1)
    lw      s5,  (DIST/2  + OFFSET)(s1)
    lw      s6,  (3*DIST/4+ OFFSET)(s1)
    lw      s7,  (DIST    + OFFSET)(s1)
    lw      s8,  (5*DIST/4+ OFFSET)(s1)
    lw      s9,  (6*DIST/4+ OFFSET)(s1)
    lw      s10, (7*DIST/4+ OFFSET)(s1)

    /* ARM: movw qa, #26632 */
    li      t1,  26632

    /* 8-point NTT on odd-indexed coefficients (a1,a3,…,a15)
     * ARM: _3_layer_double_CT_16_plant_fp poly0..poly7, s8..s14, tw1, tw2, q, qa, tmp */
    _3_layer_CT_plant_fp_rv  s3,s4,s5,s6, s7,s8,s9,s10,  f8,f9,f10,f11,f12,f13,f14,  s11,t0,  s0,t1, t2, t3,t4,t5

    /* ---- multiply by layer-8 twiddle factors (stored in f15-f22) ----- */
    /* ARM: vmov twiddle1, s15 / vmov twiddle2, s16 */
    fmv.x.w s11, f15
    fmv.x.w t0,  f16
    mul_twiddle_plant_rv  s3,  s11, t2, s0, t1, t4   /* poly0 */
    mul_twiddle_plant_rv  s4,  t0,  t2, s0, t1, t4   /* poly1 */

    fmv.x.w s11, f17
    fmv.x.w t0,  f18
    mul_twiddle_plant_rv  s5,  s11, t2, s0, t1, t4   /* poly2 */
    mul_twiddle_plant_rv  s6,  t0,  t2, s0, t1, t4   /* poly3 */

    fmv.x.w s11, f19
    fmv.x.w t0,  f20
    mul_twiddle_plant_rv  s7,  s11, t2, s0, t1, t4   /* poly4 */
    mul_twiddle_plant_rv  s8,  t0,  t2, s0, t1, t4   /* poly5 */

    fmv.x.w s11, f21
    fmv.x.w t0,  f22
    mul_twiddle_plant_rv  s9,  s11, t2, s0, t1, t4   /* poly6 */
    mul_twiddle_plant_rv  s10, t0,  t2, s0, t1, t4   /* poly7 */

    /* ---- stash processed odd coefficients into f0-f7 -----------------
     * ARM: vmov s0, poly0 // a1  ...  vmov s7, poly7 // a15              */
    fmv.w.x f0,  s3
    fmv.w.x f1,  s4
    fmv.w.x f2,  s5
    fmv.w.x f3,  s6
    fmv.w.x f4,  s7
    fmv.w.x f5,  s8
    fmv.w.x f6,  s9
    fmv.w.x f7,  s10

    /* ARM: vmov poly, s23 */
    fmv.x.w s1,  f23

    /* ---- load 8 even-column coefficient words ------------------------ */
    lw      s3,  0(s1)
    lw      s4,  (DIST/4)(s1)
    lw      s5,  (DIST/2)(s1)
    lw      s6,  (3*DIST/4)(s1)
    lw      s7,  (DIST)(s1)
    lw      s8,  (5*DIST/4)(s1)
    lw      s9,  (6*DIST/4)(s1)
    lw      s10, (7*DIST/4)(s1)

    li      t1,  26632

    /* 8-point NTT on even-indexed coefficients (a0,a2,…,a14) */
    _3_layer_CT_plant_fp_rv  s3,s4,s5,s6, s7,s8,s9,s10,  f8,f9,f10,f11,f12,f13,f14,  s11,t0,  s0,t1, t2, t3,t4,t5

    /* ---- layer 4: butterfly (a2,a6,a10,a14) ↔ (a3,a7,a11,a15) ------
     * ARM: vmov poly, s23                                                 */
    fmv.x.w s1, f23

    /* ARM: vmov twiddle1, s1 // load a3 */
    fmv.x.w s11, f1
    uadd16_rv   t2,  s4, s11, t4, t5, t3   /* tmp    = a2 + a3  */
    usub16_rv   s4,  s4, s11, t4, t5, t3   /* poly1  = a2 − a3  */
    sw          t2,  (1*DIST/4)(s1)
    sw          s4,  (1*DIST/4 + OFFSET)(s1)

    fmv.x.w s11, f3                         /* load a7           */
    uadd16_rv   t2,  s6, s11, t4, t5, t3
    usub16_rv   s6,  s6, s11, t4, t5, t3
    sw          t2,  (3*DIST/4)(s1)
    sw          s6,  (3*DIST/4 + OFFSET)(s1)

    fmv.x.w s11, f5                         /* load a11          */
    uadd16_rv   t2,  s8, s11, t4, t5, t3
    usub16_rv   s8,  s8, s11, t4, t5, t3
    sw          t2,  (5*DIST/4)(s1)
    sw          s8,  (5*DIST/4 + OFFSET)(s1)

    fmv.x.w s11, f7                         /* load a15          */
    uadd16_rv   t2,  s10, s11, t4, t5, t3
    usub16_rv   s10, s10, s11, t4, t5, t3
    sw          t2,  (7*DIST/4)(s1)
    sw          s10, (7*DIST/4 + OFFSET)(s1)

    /* ---- layer 4: butterfly (a0,a4,a8,a12) ↔ (a1,a5,a9,a13) --------*/
    fmv.x.w s6,  f2                         /* poly3 = a5        */
    uadd16_rv   t2,  s5, s6, t4, t5, t3
    usub16_rv   s11, s5, s6, t4, t5, t3
    sw          t2,  (2*DIST/4)(s1)
    sw          s11, (2*DIST/4 + OFFSET)(s1)

    fmv.x.w s8,  f4                         /* poly5 = a9        */
    uadd16_rv   t2,  s7, s8, t4, t5, t3
    usub16_rv   s11, s7, s8, t4, t5, t3
    sw          t2,  (4*DIST/4)(s1)
    sw          s11, (4*DIST/4 + OFFSET)(s1)

    fmv.x.w s10, f6                         /* poly7 = a13       */
    uadd16_rv   t2,  s9, s10, t4, t5, t3
    usub16_rv   s11, s9, s10, t4, t5, t3
    sw          t2,  (6*DIST/4)(s1)
    sw          s11, (6*DIST/4 + OFFSET)(s1)

    /* ---- butterfly a0 ↔ a1  and write a0 with post-increment --------
     * ARM: str.w tmp, [poly], #4                                         */
    fmv.x.w s4,  f0                         /* poly1 = a1        */
    uadd16_rv   t2,  s3, s4, t4, t5, t3    /* tmp      = a0 + a1*/
    usub16_rv   s11, s3, s4, t4, t5, t3    /* twiddle1 = a0 − a1*/
    sw          s11, OFFSET(s1)
    sw          t2,  0(s1)
    addi        s1,  s1, STRINCR           /* poly++ (4 bytes)   */

    /* ARM: cmp.w poly, tmp  /  bne.w 1b */
    fmv.x.w t2, f24
    bne         s1, t2, .Lloop1

    /* ARM: sub.w poly, #8*strincr  — rewind to start of polynomial      */
    addi    s1, s1, -(8*STRINCR)

    /* ------------------------------------------------------------------ */
    /* LAYER 3+2+1                                                          */
    /* ------------------------------------------------------------------ */

    .equ DIST2,    16               /* distance/16  (was 256)                   */
    .equ STRINCR2, 32               /* 32 bytes per second-loop step            */

    /* ARM: add.w tmp, poly, #strincr*16  (= poly + 512, full polynomial) */
    addi    t0, s1, STRINCR2*16
    fmv.w.x f13, t0                 /* save loop end in f13 (reuse twiddle slot) */

.Lloop2:
    /* ARM: vmov s23, poly */
    fmv.w.x f23, s1

    /* Load 8 coefficient words with distance=16 */
    lw      s3,  0(s1)
    lw      s4,  (DIST2/4)(s1)
    lw      s5,  (DIST2/2)(s1)
    lw      s6,  (3*DIST2/4)(s1)
    lw      s7,  (DIST2)(s1)
    lw      s8,  (5*DIST2/4)(s1)
    lw      s9,  (6*DIST2/4)(s1)
    lw      s10, (7*DIST2/4)(s1)

    li      t1, 26632               /* qa                                        */

    /* ARM: _3_layer_double_CT_16_plant poly0..poly7, tw1, tw2, twiddle_ptr, q, qa, tmp
     * This version loads twiddle factors from memory (not FP registers).       */
    _3_layer_CT_plant_rv  s3,s4,s5,s6, s7,s8,s9,s10,  s11,t0,  s2,  s0,t1, t2, t3,t4,t5

    /* ARM: vmov poly, s23 */
    fmv.x.w s1, f23

    /* Store results
     * ARM: store poly, poly4-poly7, #distance, ...
     *      str.w poly1, [poly, #distance/4]  etc.                        */
    sw      s7,  (DIST2)(s1)
    sw      s8,  (5*DIST2/4)(s1)
    sw      s9,  (6*DIST2/4)(s1)
    sw      s10, (7*DIST2/4)(s1)
    sw      s4,  (DIST2/4)(s1)
    sw      s5,  (DIST2/2)(s1)
    sw      s6,  (3*DIST2/4)(s1)

    /* ARM: str.w poly0, [poly], #strincr  — write poly0 and advance poly */
    sw      s3,  0(s1)
    addi    s1,  s1, STRINCR2

    /* ARM: cmp.w poly, tmp  /  bne.w 2b */
    fmv.x.w t2, f13
    bne     s1, t2, .Lloop2

    /* ------------------------------------------------------------------ */
    /* Epilogue                                                             */
    /* ------------------------------------------------------------------ */

    /* ARM: vpop.w {s16-s24} */
    flw     f8,  32(sp)
    flw     f9,  28(sp)
    flw     f18, 24(sp)
    flw     f19, 20(sp)
    flw     f20, 16(sp)
    flw     f21, 12(sp)
    flw     f22,  8(sp)
    flw     f23,  4(sp)
    flw     f24,  0(sp)
    addi    sp,  sp, 36

    /* ARM: pop {r4-r11, pc} */
    lw      ra,  48(sp)
    lw      s0,  44(sp)
    lw      s1,  40(sp)
    lw      s2,  36(sp)
    lw      s3,  32(sp)
    lw      s4,  28(sp)
    lw      s5,  24(sp)
    lw      s6,  20(sp)
    lw      s7,  16(sp)
    lw      s8,  12(sp)
    lw      s9,   8(sp)
    lw      s10,  4(sp)
    lw      s11,  0(sp)
    addi    sp,  sp, 52
    ret

    .size   ntt_fast, .-ntt_fast
