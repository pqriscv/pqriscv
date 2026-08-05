.section .text
.global mldsa_invntt_asm
.type mldsa_invntt_asm, @function
    # -------------------------------------------------------------------------
    # a0 = Base pointer to array 'a'
    # a1 = 1024
    # a2 = k (index for zetas, starts at 256, goes down)
    # a3 = pointer to zetas array
    # a4 = QINV constant (58728449)
    # a5 = MLDSA_Q constant (8380417)
    # a6 = start_bytes 
    # t0 = len_bytes (len * 4)
    # -------------------------------------------------------------------------
mldsa_invntt_asm:
    li a1, 1024
    li a2, 256
    la a3, zetas
    li a4, 58728449
    li a5, 8380417
    li  t0, 4
    la   a3, zetas
    addi a3, a3, 1024     # point one past zetas[255]

.L_len_loop:
    bgeu t0, a1,  .L_done     # if len_bytes>1024 jump
    li a6, 0 #startbytes = 0

.L_start_loop:  
    bgeu a6, a1, .L_next_len #if start_bytes>1024 jump

    # Set up direct pointers for the innermost loop
    add   t2, a0, a6             # t2 = &a[j] (j_ptr)
    add   t3, t2, t0             # t3 = &a[j + len] (j_len_ptr)        

    # Calculate end pointer for this inner loop run: end_j_ptr = j_ptr + len_bytes
    add   t4, t2, t0             # t4 = loop exit bound (end_j_ptr)

    # zeta = -zetas[--k]
    # each zeta:
    addi a3, a3, -4
    lw   a6, 0(a3)
    neg  a6, a6

.L_j_loop:
    bgeu  t2, t4, .L_end_j_loop  # if j_ptr >= end_j_ptr, loop done
    lw a7, 0(t2)        # a7 = a[j] = t
    lw t5, 0(t3)              # t5 = a[j + len]
    add t6, a7, t5      # t6 = t + a[j + len]
    sw t6, 0(t2)        # a[j] = t + a[j + len]
    sub t5, a7, t5      # a[j + len] = t - a[j + len];

# --- INLINED MONTGOMERY REDUCE ---
    # Using free registers: t6 (prod_lo), t1 (prod_hi), a7 yes (t_lo / sub_hi), t6 yes(sub_lo -> final 't')
    # product = (int64_t)zeta * a[j + len]
    mul   t6, a6, t5             # product low 
    mulh  t1, a6, t5             # product high now t5 free
    
    # t_lo = low32(product_low * QINV)
    mul   a7, t6, a4             # a7 = t_lo = low32(t5 * QINV)

    # Compute signed 64-bit product: (int64_t)t_lo * MLDSA_Q
    mul   t5, a7, a5             # t6 = low32(t_lo * MLDSA_Q)
    mulh  a7, a7, a5             # a7 = high32(t_lo * MLDSA_Q), signed

    # 64-bit subtraction: product - (t_lo * MLDSA_Q)
    sltu  t5, t6, t5             # t5 = borrow from low-word subtraction
    sub   t1, t1, a7             # high word sub
    sub   t6, t1, t5             # t6 = montgomery_reduce result (high word 't')
    # --- END MONTGOMERY REDUCE ---
    # a[j + len] = montgomery_reduce
    sw t6, 0(t3)
    
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
    slli t0, t0, 1       # len <<= 1
    j    .L_len_loop
.L_done:
    # Final scaling: a[j] = montgomery_reduce((int64_t)f * a[j]) 
    # free reg: a2, a3, a6, a7, t1, t0, t2, t3, t4, t5, t6
    li    a2, 41978           # f
    add   t4, a0, a1           # t4 = end_ptr = base_ptr + 1024 bytes
    

.L_scale_loop:
    bgeu  a0, t4, .L_exit     # while j_ptr < 1024
    lw    t0, 0(a0)           # a[j]
    # --- INLINED MONTGOMERY REDUCE ---

    # Using free registers: t5 (prod_lo), t1 (prod_hi), a7 (t_lo / sub_hi), t6 (sub_lo -> final 't')
    # product = (int64_t)f * a[j]
    mul   t5, a2, t0             # product low
    mulh  t1, a2, t0             # product high

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
    sw t6, 0(a0)
    addi  a0, a0, 4              # j_ptr++
    j     .L_scale_loop
.L_exit:
    ret

    
    
