/******************************************************************************
 * RISC-V RV32IM port of fastntt.S
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
 *  • Target ISA: RV32IM — no F extension required.
 *    The original port used f0–f24 as extra integer storage (via fmv.w.x /
 *    fmv.x.w), which trapped on any core without the F extension (ESP32-C3,
 *    many bare RISC-V cores).  This version replaces every FP register use
 *    with either an integer register or a stack slot.
 *
 *  • Twiddle preload (was f8–f14 / f15–f22):
 *      – 7 sub-NTT twiddles (xi0–xi6) → a2–a7, t6 (caller-saved; free)
 *      – 8 mul_twiddle factors         → loaded via s2 each iteration
 *        s2 stays at &twiddle[7] throughout loop1, then advances 32 bytes
 *        to &twiddle[15] for loop2.
 *
 *  • Odd-column stash (was f0–f7): → sp+0..sp+31 (32-byte scratch area).
 *
 *  • Poly-pointer save (was f23): ELIMINATED.
 *    s1 is never modified inside the loop body.
 *
 *  • Loop sentinels (were f24, f13): → a0, a1.
 *
 * Stack frame (84 bytes total)
 * ----------------------------
 *  sp+ 0..31  : stash[0..7] — odd-column results  (8×4 bytes)
 *  sp+32..80  : callee-saved regs (s11,s10,...,s0,ra)
 *
 * Integer register map
 * --------------------
 *  a0 = loop1 sentinel   a1 = loop2 sentinel
 *  a2 = xi0  a3 = xi1  a4 = xi2  a5 = xi3  a6 = xi4  a7 = xi5  t6 = xi6
 *  s0 = q=3329   s1 = poly   s2 = twiddle ptr
 *  s3–s10 = 8 coefficient words
 *  s11 = twiddle1 scratch    t0 = twiddle2/scratch
 *  t1 = qa=26632   t2 = tmp   t3 = mask16   t4,t5 = butterfly scratch
 ******************************************************************************/

#include "macros_rv.i"

    .section .text

    .global ntt_fast
    .type   ntt_fast, @function
    .align  2
ntt_fast:

    /* ------------------------------------------------------------------ */
    /* Prologue                                                             */
    /* ------------------------------------------------------------------ */
    addi    sp,  sp, -84
    sw      ra,  80(sp)
    sw      s0,  76(sp)
    sw      s1,  72(sp)
    sw      s2,  68(sp)
    sw      s3,  64(sp)
    sw      s4,  60(sp)
    sw      s5,  56(sp)
    sw      s6,  52(sp)
    sw      s7,  48(sp)
    sw      s8,  44(sp)
    sw      s9,  40(sp)
    sw      s10, 36(sp)
    sw      s11, 32(sp)

    mv      s1,  a0
    mv      s2,  a1
    li      s0,  3329
    lui     t3,  0x10
    addi    t3,  t3, -1             /* t3 = 0x0000_FFFF                         */

    /* ---- Pre-load 7 sub-NTT twiddles into integer registers ---------- */
    lw      a2,  0(s2)              /* xi0 – stage1 twiddle  (1 total)          */
    lw      a3,  4(s2)              /* xi1 – stage2 twiddle0 (2 total)          */
    lw      a4,  8(s2)              /* xi2 – stage2 twiddle1                    */
    lw      a5, 12(s2)              /* xi3 – stage3 twiddle0 (4 total)          */
    lw      a6, 16(s2)              /* xi4 – stage3 twiddle1                    */
    lw      a7, 20(s2)              /* xi5 – stage3 twiddle2                    */
    lw      t6, 24(s2)              /* xi6 – stage3 twiddle3                    */
    addi    s2,  s2, 28             /* s2 → &twiddle[7] (mul_twiddles)          */

    addi    a0,  s1, 4*8            /* loop1 sentinel: poly + STRINCR*8         */

    /* ================================================================== */
    /* LAYER 7+6+5+4 (8 outer iterations)                                  */
    /* ================================================================== */

    .equ DIST,    256
    .equ OFFSET,  32
    .equ STRINCR, 4

.Lloop1:
    li      t1, 26632

    /* ---- Load 8 odd-column words ------------------------------------- */
    lw      s3,  (OFFSET)(s1)
    lw      s4,  (DIST/4  + OFFSET)(s1)
    lw      s5,  (DIST/2  + OFFSET)(s1)
    lw      s6,  (3*DIST/4+ OFFSET)(s1)
    lw      s7,  (DIST    + OFFSET)(s1)
    lw      s8,  (5*DIST/4+ OFFSET)(s1)
    lw      s9,  (6*DIST/4+ OFFSET)(s1)
    lw      s10, (7*DIST/4+ OFFSET)(s1)

    /* 8-point sub-NTT on odd column (layers 7+6+5) */
    _3_layer_CT_plant_int_rv s3,s4,s5,s6, s7,s8,s9,s10, a2,a3,a4,a5,a6,a7,t6, s11,t0, s0,t1,t2,t3,t4,t5

    /* ---- Apply layer-4 mul_twiddle to odd column ---------------------
     * s2 stays fixed at &twiddle[7] for all iterations.                  */
    lw      s11, 0(s2);  lw t0,  4(s2)
    mul_twiddle_plant_rv  s3,  s11, t2, s0, t1, t4
    mul_twiddle_plant_rv  s4,  t0,  t2, s0, t1, t4

    lw      s11, 8(s2);  lw t0, 12(s2)
    mul_twiddle_plant_rv  s5,  s11, t2, s0, t1, t4
    mul_twiddle_plant_rv  s6,  t0,  t2, s0, t1, t4

    lw      s11,16(s2);  lw t0, 20(s2)
    mul_twiddle_plant_rv  s7,  s11, t2, s0, t1, t4
    mul_twiddle_plant_rv  s8,  t0,  t2, s0, t1, t4

    lw      s11,24(s2);  lw t0, 28(s2)
    mul_twiddle_plant_rv  s9,  s11, t2, s0, t1, t4
    mul_twiddle_plant_rv  s10, t0,  t2, s0, t1, t4

    /* ---- Stash odd results to stack ---------------------------------- */
    sw      s3,   0(sp)
    sw      s4,   4(sp)
    sw      s5,   8(sp)
    sw      s6,  12(sp)
    sw      s7,  16(sp)
    sw      s8,  20(sp)
    sw      s9,  24(sp)
    sw      s10, 28(sp)

    /* ---- Load 8 even-column words ------------------------------------ */
    li      t1, 26632
    lw      s3,  0(s1)
    lw      s4,  (DIST/4)(s1)
    lw      s5,  (DIST/2)(s1)
    lw      s6,  (3*DIST/4)(s1)
    lw      s7,  (DIST)(s1)
    lw      s8,  (5*DIST/4)(s1)
    lw      s9,  (6*DIST/4)(s1)
    lw      s10, (7*DIST/4)(s1)

    /* 8-point sub-NTT on even column (same twiddles, layers 7+6+5) */
    _3_layer_CT_plant_int_rv s3,s4,s5,s6, s7,s8,s9,s10, a2,a3,a4,a5,a6,a7,t6, s11,t0, s0,t1,t2,t3,t4,t5

    /* ---- Layer-4 butterfly: even (s3..s10) ↔ odd (from stash) ------- */

    lw      s11,  4(sp)
    uadd16_rv   t2,  s4, s11, t4, t5, t3
    usub16_rv   s4,  s4, s11, t4, t5, t3
    sw          t2,  (1*DIST/4)(s1)
    sw          s4,  (1*DIST/4 + OFFSET)(s1)

    lw      s11, 12(sp)
    uadd16_rv   t2,  s6, s11, t4, t5, t3
    usub16_rv   s6,  s6, s11, t4, t5, t3
    sw          t2,  (3*DIST/4)(s1)
    sw          s6,  (3*DIST/4 + OFFSET)(s1)

    lw      s11, 20(sp)
    uadd16_rv   t2,  s8, s11, t4, t5, t3
    usub16_rv   s8,  s8, s11, t4, t5, t3
    sw          t2,  (5*DIST/4)(s1)
    sw          s8,  (5*DIST/4 + OFFSET)(s1)

    lw      s11, 28(sp)
    uadd16_rv   t2,  s10, s11, t4, t5, t3
    usub16_rv   s10, s10, s11, t4, t5, t3
    sw          t2,  (7*DIST/4)(s1)
    sw          s10, (7*DIST/4 + OFFSET)(s1)

    lw      s6,   8(sp)
    uadd16_rv   t2,  s5, s6, t4, t5, t3
    usub16_rv   s11, s5, s6, t4, t5, t3
    sw          t2,  (2*DIST/4)(s1)
    sw          s11, (2*DIST/4 + OFFSET)(s1)

    lw      s8,  16(sp)
    uadd16_rv   t2,  s7, s8, t4, t5, t3
    usub16_rv   s11, s7, s8, t4, t5, t3
    sw          t2,  (4*DIST/4)(s1)
    sw          s11, (4*DIST/4 + OFFSET)(s1)

    lw      s10, 24(sp)
    uadd16_rv   t2,  s9, s10, t4, t5, t3
    usub16_rv   s11, s9, s10, t4, t5, t3
    sw          t2,  (6*DIST/4)(s1)
    sw          s11, (6*DIST/4 + OFFSET)(s1)

    lw      s4,   0(sp)
    uadd16_rv   t2,  s3, s4, t4, t5, t3
    usub16_rv   s11, s3, s4, t4, t5, t3
    sw          s11, OFFSET(s1)
    sw          t2,  0(s1)
    addi        s1,  s1, STRINCR

    bne         s1, a0, .Lloop1

    /* Rewind poly; advance s2 past mul_twiddles to &twiddle[15] */
    addi    s1, s1, -(8*STRINCR)
    addi    s2, s2, 32

    /* ================================================================== */
    /* LAYER 3+2+1 (16 outer iterations)                                   */
    /* ================================================================== */

    .equ DIST2,    16
    .equ STRINCR2, 32

    addi    a1, s1, 32*16

.Lloop2:
    lw      s3,  0(s1)
    lw      s4,  (DIST2/4)(s1)
    lw      s5,  (DIST2/2)(s1)
    lw      s6,  (3*DIST2/4)(s1)
    lw      s7,  (DIST2)(s1)
    lw      s8,  (5*DIST2/4)(s1)
    lw      s9,  (6*DIST2/4)(s1)
    lw      s10, (7*DIST2/4)(s1)

    li      t1, 26632

    _3_layer_CT_plant_rv  s3,s4,s5,s6, s7,s8,s9,s10, s11,t0, s2, s0,t1, t2, t3,t4,t5

    sw      s7,  (DIST2)(s1)
    sw      s8,  (5*DIST2/4)(s1)
    sw      s9,  (6*DIST2/4)(s1)
    sw      s10, (7*DIST2/4)(s1)
    sw      s4,  (DIST2/4)(s1)
    sw      s5,  (DIST2/2)(s1)
    sw      s6,  (3*DIST2/4)(s1)
    sw      s3,  0(s1)
    addi    s1,  s1, STRINCR2

    bne     s1, a1, .Lloop2

    /* ------------------------------------------------------------------ */
    /* Epilogue                                                             */
    /* ------------------------------------------------------------------ */
    lw      ra,  80(sp)
    lw      s0,  76(sp)
    lw      s1,  72(sp)
    lw      s2,  68(sp)
    lw      s3,  64(sp)
    lw      s4,  60(sp)
    lw      s5,  56(sp)
    lw      s6,  52(sp)
    lw      s7,  48(sp)
    lw      s8,  44(sp)
    lw      s9,  40(sp)
    lw      s10, 36(sp)
    lw      s11, 32(sp)
    addi    sp,  sp, 84
    ret

    .size   ntt_fast, .-ntt_fast
