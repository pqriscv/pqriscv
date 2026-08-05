.section .text
    .global mldsa_ntt_asm
    .type mldsa_ntt_asm, @function

# void MLDSA_ntt332(int32_t a[N])
# a0 = pointer to array 'a'

mldsa_ntt_asm:
    # -------------------------------------------------------------------------
    # Register Map (All Volatile / Caller-Saved -> Zero Stack Overhead):
    # a0 = Base pointer to array 'a'
    # a1 = len (starts at 128)
    # a2 = k (index for zetas, starts at 0)
    # a3 = pointer to zetas array
    # a4 = QINV constant (58728449)
    # a5 = MLDSA_Q constant (8380417)
    # a6 = start_bytes (NEVER clobbered inside the inner loop now!)
    # t0 = len_bytes (len * 4, NEVER clobbered inside the inner loop!)
    # -------------------------------------------------------------------------
    addi  sp, sp, -16
    sw    s0, 12(sp)
    li    s0, 1024    
    li    a1, 128                # len = 128
    li    a2, 0                  # k = 0
    la    a3, zetas              # &zetas[0]
    
    # Pre-load constants outside the loop
    li    a4, 58728449          # QINV
    li    a5, 8380417              # MLDSA_Q

.L_len_loop:
    beqz  a1, .L_done            # while len > 0
    
    slli  t0, a1, 2              # t0 = len_bytes (len * 4)
    li    a6, 0                  # start_bytes = 0

.L_start_loop:               
    bgeu  a6, s0, .L_next_len    # if start_bytes >= 1024, go to next len

    # zeta = zetas[++k]
    addi  a2, a2, 1
    slli  t1, a2, 2
    add   t1, a3, t1

    # Set up direct pointers for the innermost loop
    add   t2, a0, a6             # t2 = &a[j] (j_ptr)
    add   t3, t2, t0             # t3 = &a[j + len] (j_len_ptr)

    lw    a6, 0(t1)              # a6 = zeta during this j-loop
    
    # Calculate end pointer for this inner loop run: end_j_ptr = j_ptr + len_bytes
    add   t4, t2, t0             # t4 = loop exit bound (end_j_ptr)

.L_j_loop:
    bgeu  t2, t4, .L_end_j_loop  # if j_ptr >= end_j_ptr, loop done

    lw    t6, 0(t3)              # t6 = a[j + len]

    # --- INLINED MONTGOMERY REDUCE ---
    # Using free registers: t5 (prod_lo), t1 (prod_hi), a7 (t_lo / sub_hi), t6 (sub_lo -> final 't')
    
    # product = (int64_t)zeta * a[j + len]
    mul   t5, a6, t6             # product low
    mulh  t1, a6, t6             # product high

    # t_lo = low32(product_low * QINV)
    mul   a7, t5, a4             # a7 = t_lo = low32(t5 * QINV)

    # Compute signed 64-bit product: (int64_t)t_lo * MLDSA_Q
    mul   t6, a7, a5             # t6 = low32(t_lo * MLDSA_Q)
    mulh  a7, a7, a5             # a7 = high32(t_lo * MLDSA_Q), signed

    # 64-bit subtraction: product - (t_lo * MLDSA_Q)
    sltu  t5, t5, t6             # t5 = borrow from low-word subtraction
    sub   t1, t1, a7             # high word sub
    sub   t6, t1, t5             # t6 = montgomery_reduce result (high word 't')
    # --- END MONTGOMERY REDUCE ---

    lw    t5, 0(t2)              # t5 = a[j]

    sub   a7, t5, t6             # a[j] - t (using a7 as temporary store)
    sw    a7, 0(t3)              # store to a[j + len]

    add   a7, t5, t6             # a[j] + t
    sw    a7, 0(t2)              # store to a[j]

    # Advance pointers directly by 4 bytes (1 int32)
    addi  t2, t2, 4              # j_ptr++
    addi  t3, t3, 4              # j_len_ptr++
    j     .L_j_loop

.L_end_j_loop:
    # ---------------------------------------------------------------------
    # Exact translation of: start = j + len
    # When loop ends, t2 (j_ptr) is pointing to &a[j].
    # ---------------------------------------------------------------------
    sub   a6, t2, a0             # 1. Get j in bytes: j_bytes = &a[j] - &a[0]
    add   a6, a6, t0             # 2. Add len in bytes: start_bytes = j_bytes + len_bytes
    j     .L_start_loop

.L_next_len:
    srli  a1, a1, 1              # len >>= 1
    j     .L_len_loop

.L_done:
    lw    s0, 12(sp)
    addi  sp, sp, 16
    ret