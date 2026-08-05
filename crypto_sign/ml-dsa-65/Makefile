# Makefile — ml-dsa-65  (Dilithium mode 3 = ML-DSA-65)
#
# Shared implementation lives in crypto_sign/mldsa/.
# This directory only provides params.h (DILITHIUM_MODE=3) and api.h.

MLDSA_DIR = crypto_sign/mldsa

SCHEME_SOURCES_EXT = \
    $(MLDSA_DIR)/symmetric-shake.c  \
    $(MLDSA_DIR)/sign.c             \
    $(MLDSA_DIR)/packing.c          \
    $(MLDSA_DIR)/poly.c             \
    $(MLDSA_DIR)/polyvec.c          \
    $(MLDSA_DIR)/ntt.c              \
    $(MLDSA_DIR)/ntt_asm.S          \
    $(MLDSA_DIR)/invntt_asm.S \
    $(MLDSA_DIR)/caddq_asm.S \
    $(MLDSA_DIR)/reduce32_asm.S \
    $(MLDSA_DIR)/montgomery_reduce_asm.S \
    $(MLDSA_DIR)/reduce.c           \
    $(MLDSA_DIR)/rounding.c
    
SCHEME_SOURCES =

SCHEME_CFLAGS = -I$(MLDSA_DIR) -Icrypto_sign/ml-dsa-65
