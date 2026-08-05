    .section .text
    .global haetae_montgomery_reduce_asm
    .type haetae_montgomery_reduce_asm, @function

# int32_t haetae_montgomery_reduce_asm(int64_t a)
#
# RV32 ABI for a 64-bit argument:
#   a0 = low 32 bits of a
#   a1 = high 32 bits of a
#
# Return value:
#   a0 = int32_t result

haetae_montgomery_reduce_asm:
    # t = (int64_t)(int32_t)a * QINV;
    # Only the low 32 bits are kept because t is int32_t.
    li    t0, 940508161          # QINV
    mul   t1, a0, t0            # t1 = low32(a_lo * QINV)

    # Compute signed 64-bit product: (int64_t)t * HAETAE_Q.
    li    t2, 64513           # HAETAE_Q
    mul   t3, t1, t2            # low32(t * HAETAE_Q)
    mulh  t4, t1, t2            # high32(t * HAETAE_Q), signed

    # Compute 64-bit subtraction: a - (int64_t)t * HAETAE_Q.
    # a is a1:a0, product is t4:t3.
    sltu  t5, a0, t3            # borrow from low-word subtraction
    sub   a0, a0, t3            # low word, discarded later
    sub   a1, a1, t4            # high word
    sub   a1, a1, t5            # subtract borrow

    # Return (a - (int64_t)t * HAETAE_Q) >> 32, i.e. the high word.
    mv    a0, a1
    ret
