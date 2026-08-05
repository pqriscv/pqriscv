    .section .text
    .global haetae_2_montgomery_reduce_asm
    .type haetae_2_montgomery_reduce_asm, @function

haetae_2_montgomery_reduce_asm:
        li      a4,940507136
        addi    a4,a4,1025
        mul     a4,a0,a4
        srai    a2,a4,31
        srli    a3,a4,26
        slli    a5,a2,6
        add     a5,a3,a5
        slli    a3,a4,6
        sub     a3,a4,a3
        sgtu    a6,a3,a4
        sub     a5,a2,a5
        sub     a5,a5,a6
        slli    a5,a5,10
        srli    a6,a3,22
        slli    a3,a3,10
        sub     a4,a3,a4
        add     a5,a6,a5
        sub     a5,a5,a2
        sgtu    a3,a4,a3
        sub     a5,a5,a3
        add     a0,a4,a0
        add     a5,a5,a1
        sltu    a0,a0,a4
        add     a0,a0,a5
        ret