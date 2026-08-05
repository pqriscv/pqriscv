    .section .text
    .global reduce32_asm
    .type  reduce32_asm, @function
reduce32_asm:
    li      t0, 1
    slli    t0, t0, 22
    add     t1, a0, t0
    srai    t1, t1, 23
    li      t3, 8380417
    mul    t1, t1, t3
    sub     a0, a0, t1
    ret

