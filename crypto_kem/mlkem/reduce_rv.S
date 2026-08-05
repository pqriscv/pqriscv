/******************************************************************************
 * RISC-V RV32IM port of reduce.S
 *
 * Integrating the improved Plantard arithmetic into Kyber.
 * Barrett and Plantard ("fromplant") coefficient reduction.
 *
 * Original Cortex-M4 author:
 *   Junhao Huang, BNU-HKBU United International College, Zhuhai, China
 *   jhhuang_nuaa@126.com  (September 2022)
 *   https://eprint.iacr.org/2022/956.pdf
 *
 * RISC-V port notes
 * -----------------
 *  • Target ISA: RV32IM.  No SIMD extensions required.
 *  • SMULWB/SMULWT/SMLABT/PKHTB/USUB16/UADD16 are all expanded to
 *    multi-instruction sequences via macros_rv.i.
 *  • The ARM "register packing" trick (q in the top half of one register,
 *    qa in the bottom half) is NOT used: q=3329 and qa=26632 are stored
 *    as plain 32-bit values in separate registers.
 *  • LDM/STM are replaced with 8 individual lw/sw + an addi for writeback.
 *  • Condition-code branches (subs / bne) become addi + bnez.
 *
 * Register conventions (RISC-V ABI)
 * ----------------------------------
 *  a0-a7   caller-saved argument/return registers
 *  t0-t6   caller-saved temporaries
 *  s0-s11  callee-saved  ← functions below use s0-s11 and ra
 ******************************************************************************/

#include "macros_rv.i"

    .section .text

/* ===========================================================================
 * void asm_barrett_reduce(int16_t *poly)
 *
 * Barrett-reduces all 256 coefficients of *poly modulo q = 3329.
 * Coefficients are packed two-per-word (little-endian 16-bit) in 128 words.
 * The loop processes 8 words (16 coefficients) per iteration × 16 iterations.
 *
 * Register map
 * ------------
 *   a0      = poly (argument; NOT modified on return)
 *   s1      = poly working pointer  (= a0 initially, then auto-increments)
 *   s2-s9   = poly0-poly7           (8 packed-coefficient words per iteration)
 *   s10     = loop counter          (counts down from 16)
 *   s11     = barrettconst          (= 20159 = floor(2^26 / 3329))
 *   s0      = q                     (= 3329)
 *   t0, t1  = tmp, tmp2             (scratch inside doublebarrett_rv)
 * =========================================================================== */
    .global asm_barrett_reduce
    .type   asm_barrett_reduce, @function
    .align  2
asm_barrett_reduce:
    /* prologue: save ra + s0-s11 (13 × 4 = 52 bytes) */
    addi    sp,  sp,  -52
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

    li      s11, 20159              /* barrettconst = floor(2^26 / q)            */
    li      s0,  3329               /* q                                         */
    li      s10, 16                 /* 16 iterations × 8 words = 128 words       */
    mv      s1,  a0                 /* working pointer (mirrors ARM poly .req r0)*/

.Lbarrett_loop:
    /* ARM: ldm poly, {poly0-poly7} */
    lw      s2,   0(s1)
    lw      s3,   4(s1)
    lw      s4,   8(s1)
    lw      s5,  12(s1)
    lw      s6,  16(s1)
    lw      s7,  20(s1)
    lw      s8,  24(s1)
    lw      s9,  28(s1)

    /* ARM: 8× doublebarrett poly_i, tmp, tmp2, q, barrettconst */
    doublebarrett_rv  s2, t0, t1, s0, s11
    doublebarrett_rv  s3, t0, t1, s0, s11
    doublebarrett_rv  s4, t0, t1, s0, s11
    doublebarrett_rv  s5, t0, t1, s0, s11
    doublebarrett_rv  s6, t0, t1, s0, s11
    doublebarrett_rv  s7, t0, t1, s0, s11
    doublebarrett_rv  s8, t0, t1, s0, s11
    doublebarrett_rv  s9, t0, t1, s0, s11

    /* ARM: stm poly!, {poly0-poly7}  (! = writeback) */
    sw      s2,   0(s1)
    sw      s3,   4(s1)
    sw      s4,   8(s1)
    sw      s5,  12(s1)
    sw      s6,  16(s1)
    sw      s7,  20(s1)
    sw      s8,  24(s1)
    sw      s9,  28(s1)
    addi    s1,  s1, 32             /* pointer writeback                         */

    /* ARM: subs.w loop, #1  /  bne.w 1b */
    addi    s10, s10, -1
    bnez    s10, .Lbarrett_loop

    /* epilogue */
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
    .size   asm_barrett_reduce, .-asm_barrett_reduce


/* ===========================================================================
 * void asm_fromplant(int16_t *poly)
 *
 * Converts all 256 coefficients from Plantard representation back to the
 * standard [0, q) range using the Plantard constant.
 *
 *   plantconst = (Plant_const^2 mod q) × (p^{-1} mod 2^32),  p = 2^16
 *              = 0x97F4_4F6C
 *              ARM: movw plantconst, #20396  (= 0x4F6C)
 *                   movt plantconst, #38900  (= 0x97F4)
 *
 * Register map
 * ------------
 *   a0      = poly (argument)
 *   s1      = poly working pointer
 *   s2-s9   = poly0-poly7
 *   s10     = loop counter (16)
 *   s11     = plantconst (0x97F44F6C, i.e. −1 745 469 588 signed)
 *   s0      = q          (3329)
 *   a1      = qa         (26632 = 8·q; re-loaded each iteration to match ARM)
 *   t0, t1  = tmp, scr   (scratch inside doubleplant_rv)
 * =========================================================================== */
    .global asm_fromplant
    .type   asm_fromplant, @function
    .align  2
asm_fromplant:
    /* prologue */
    addi    sp,  sp,  -52
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

    li      s0,  3329               /* q                                         */
    li      s10, 16                 /* loop count                                */

    /* Load plantconst = (38900 << 16) | 20396 = 0x97F4_4F6C
     * 0x97F4_4F6C bits[31:12] = 0x97F44 → lui loads 0x97F44000
     * bits[11:0]  = 0xF6C = −148 in 12-bit signed
     * Compensation: use 0x97F45 so that addi −148 gives the right result:
     *   0x97F45000 − 148 = 0x97F44F6C  ✓                                        */
    lui     s11, 0x97F45
    addi    s11, s11, -148          /* s11 = plantconst = 0x97F44F6C             */

    mv      s1,  a0

.Lplant_loop:
    lw      s2,   0(s1)
    lw      s3,   4(s1)
    lw      s4,   8(s1)
    lw      s5,  12(s1)
    lw      s6,  16(s1)
    lw      s7,  20(s1)
    lw      s8,  24(s1)
    lw      s9,  28(s1)

    /* ARM: movw qa, #26632  (inside loop — qa shared r0 with poly in ARM) */
    li      a1, 26632               /* qa = 8·q                                  */

    /* ARM: 8× doubleplant poly_i, tmp, q, qa, plantconst */
    doubleplant_rv  s2, t0, s0, a1, s11, t1
    doubleplant_rv  s3, t0, s0, a1, s11, t1
    doubleplant_rv  s4, t0, s0, a1, s11, t1
    doubleplant_rv  s5, t0, s0, a1, s11, t1
    doubleplant_rv  s6, t0, s0, a1, s11, t1
    doubleplant_rv  s7, t0, s0, a1, s11, t1
    doubleplant_rv  s8, t0, s0, a1, s11, t1
    doubleplant_rv  s9, t0, s0, a1, s11, t1

    sw      s2,   0(s1)
    sw      s3,   4(s1)
    sw      s4,   8(s1)
    sw      s5,  12(s1)
    sw      s6,  16(s1)
    sw      s7,  20(s1)
    sw      s8,  24(s1)
    sw      s9,  28(s1)
    addi    s1,  s1, 32

    addi    s10, s10, -1
    bnez    s10, .Lplant_loop

    /* epilogue */
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
    .size   asm_fromplant, .-asm_fromplant
