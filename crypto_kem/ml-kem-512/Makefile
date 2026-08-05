# Makefile — ml-kem-512  (with optional RISC-V Plantard NTT)

MLKEM_DIR = crypto_kem/mlkem

SCHEME_SOURCES_EXT = \
    common/symmetric-shake.c     \
    $(MLKEM_DIR)/kem.c           \
    $(MLKEM_DIR)/indcpa.c        \
    $(MLKEM_DIR)/poly.c          \
    $(MLKEM_DIR)/polyvec.c       \
    $(MLKEM_DIR)/ntt.c           \
    $(MLKEM_DIR)/cbd.c           \
    $(MLKEM_DIR)/verify.c        \
    $(MLKEM_DIR)/reduce.c        \
    $(MLKEM_DIR)/twiddles.c      \
    $(MLKEM_DIR)/reduce_rv.S     \
    $(MLKEM_DIR)/fastntt_rv.S

SCHEME_SOURCES =

SCHEME_CFLAGS = \
    -I$(MLKEM_DIR)               \
    -Icrypto_kem/ml-kem-512      \
    -DKYBER_ASM_NTT
