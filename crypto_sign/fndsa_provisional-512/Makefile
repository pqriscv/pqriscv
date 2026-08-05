# Makefile — fn-dsa-512  (FN-DSA-512)
#
# Shared implementation lives in crypto_sign/fndsa_provisional/.
# This directory only provides and api.h.

FNDSA_DIR = crypto_sign/fndsa_provisional

SCHEME_SOURCES_EXT = \
    $(FNDSA_DIR)/api.c  \
    $(FNDSA_DIR)/codec.c             \
    $(FNDSA_DIR)/kgen.c          \
    $(FNDSA_DIR)/kgen_fxp.c             \
    $(FNDSA_DIR)/kgen_gauss.c          \
    $(FNDSA_DIR)/kgen_mp31.c          \
    $(FNDSA_DIR)/kgen_ntru.c          \
    $(FNDSA_DIR)/kgen_poly.c \
    $(FNDSA_DIR)/kgen_zint31.c           \
    $(FNDSA_DIR)/mq.c \
    $(FNDSA_DIR)/sign.c \
    $(FNDSA_DIR)/sign_core.c \
    $(FNDSA_DIR)/sign_fpoly.c \
    $(FNDSA_DIR)/sign_sampler.c \
    $(FNDSA_DIR)/sysrng.c \
    $(FNDSA_DIR)/util.c \
    $(FNDSA_DIR)/sign_fpr.c \
    $(FNDSA_DIR)/fnsha3.c \
    $(FNDSA_DIR)/vrfy.c


SCHEME_SOURCES =

SCHEME_CFLAGS = -I$(FNDSA_DIR) -Icrypto_sign/fndsa_provisional-512
