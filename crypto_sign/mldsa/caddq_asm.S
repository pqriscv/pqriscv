    .section .text
    .global caddq_asm
    .type  caddq_asm, @function

caddq_asm:
    #int32_t caddq(int32_t a) 
    #a0 = a
    #(a >> 31)
    srai    a1, a0, 31
    #  a += (a >> 31) & Q;
    li      t0, 8380417
    and     a1, a1, t0
    add     a0, a0, a1
    #  return a;
    ret