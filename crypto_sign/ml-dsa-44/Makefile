# Makefile — ml-dsa-44  (Dilithium mode 2 = ML-DSA-44)
#
# Shared implementation lives in crypto_sign/mldsa/.
# This directory only provides params.h (DILITHIUM_MODE=2) and api.h.

MLDSA_DIR = crypto_sign/mldsa

SCHEME_SOURCES_EXT = \
    $(MLDSA_DIR)/symmetric-shake.c  \
    $(MLDSA_DIR)/sign.c             \
    $(MLDSA_DIR)/packing.c          \
    $(MLDSA_DIR)/poly.c             \
    $(MLDSA_DIR)/polyvec.c          \
    $(MLDSA_DIR)/ntt.c              \
    $(MLDSA_DIR)/ntt_asm.S          \
    $(MLDSA_DIR)/invntt_asm.S\
    $(MLDSA_DIR)/caddq_asm.S \
    $(MLDSA_DIR)/reduce32_asm.S \
    $(MLDSA_DIR)/montgomery_reduce_asm.S \
    $(MLDSA_DIR)/reduce.c           \
    $(MLDSA_DIR)/rounding.c

SCHEME_SOURCES =

SCHEME_CFLAGS = -I$(MLDSA_DIR) -Icrypto_sign/ml-dsa-44