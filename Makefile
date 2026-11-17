#
# ============================================================
# Quick start
# ============================================================
#   make help                          — this message
#   make all                           — build every scheme (test + bench)
#   make kem                           — build all KEM schemes
#   make SCHEME=ml-kem-768 test        — build test binary for one scheme
#   make SCHEME=ml-kem-768 bench       — build bench binary for one scheme
#   make SCHEME=ml-kem-768 run-test    — build + run test under QEMU
#   make SCHEME=ml-kem-768 run-bench   — build + run bench under QEMU
#   make run-all-kem                   — run every KEM test under QEMU
#   make clean                         — remove all build artefacts
#
# Override toolchain/verbosity:
#   make V=1 SCHEME=ml-kem-768 test    — verbose build

include mk/config.mk
PLATFORM ?= qemu
include mk/$(PLATFORM).mk

# When SCHEME= is set on the CLI with no explicit target, build just that scheme.
ifdef SCHEME
.DEFAULT_GOAL := kem-$(SCHEME)
endif

# ============================================================
# Global compiler flags
# ============================================================
CFLAGS_COMMON := \
    -Os                  \
    -Wall -Wextra        \
    -ffunction-sections  \
    -fdata-sections      \
    -g3                  \
    -fstack-usage        \
    $(PLATFORM_CFLAGS)

# ============================================================
# Scheme discovery
# ============================================================
KEM_DIRS := $(patsubst crypto_kem/%/Makefile,%,$(wildcard crypto_kem/*/Makefile))

.PHONY: all
all: primitives kem sign

.PHONY: kem
kem: $(addprefix kem-,$(KEM_DIRS))

# ============================================================
# Helper macros
# ============================================================

# Object path: build/<scheme>/obj/<basename>.o
obj_of = $(BUILD)/$(1)/obj/$(notdir $(2)).o

# Compile a .c file
define compile_c
$(call obj_of,$(1),$(2)): $(2)
	$$(Q)mkdir -p $$(@D)
	@echo "  CC    $$<"
	$$(Q)$$(CC) -c $$(CFLAGS_COMMON) $(3) -o $$@ $$<
endef

# Compile a .S file  ($(3) = extra flags, e.g. -I paths for .i includes)
define compile_s
$(call obj_of,$(1),$(2)): $(2)
	$$(Q)mkdir -p $$(@D)
	@echo "  AS    $$<"
	$$(Q)$$(CC) -c $$(CFLAGS_COMMON) $(3) -o $$@ $$<
endef

# Build a static library
define build_lib
$(1): $(2)
	$$(Q)mkdir -p $$(@D)
	@echo "  AR    $$@"
	$$(Q)$$(AR) rcs $$@ $$^
endef

# ============================================================
# Startup object — compiled per-scheme (same source, different build dir)
# and linked DIRECTLY into each ELF (not via .a — see mk/qemu.mk for why).
# ============================================================
define gen_startup_obj
$(call obj_of,$(1),$(STARTUP_SOURCE)): $(STARTUP_SOURCE)
	$$(Q)mkdir -p $$(@D)
	@echo "  AS    $$<"
	$$(Q)$$(CC) -c $$(CFLAGS_COMMON) -o $$@ $$<
endef

# ============================================================
# Common library (libcommon.a) — per scheme build dir
# ============================================================
define gen_common_lib
COMMON_OBJS_$(1) := $$(foreach s,$$(COMMON_SOURCES),$$(call obj_of,$(1),$$(s)))

$$(foreach s,$$(filter %.c,$$(COMMON_SOURCES)),\
    $$(eval $$(call compile_c,$(1),$$(s),)))

$$(eval $$(call build_lib,$$(BUILD)/$(1)/libcommon.a,$$(COMMON_OBJS_$(1))))
endef

# ============================================================
# Per-scheme KEM rule generator
# ============================================================
define gen_kem_scheme

# Reset per-scheme variables, then include the scheme's own Makefile
SCHEME_SOURCES     :=
SCHEME_SOURCES_EXT :=   # project-relative paths outside the scheme dir
SCHEME_CFLAGS      :=
include crypto_kem/$(1)/Makefile

# Local sources are prefixed with the scheme dir; external sources are used as-is
_SCHEME_SRC_$(1) := $$(addprefix crypto_kem/$(1)/,$$(SCHEME_SOURCES)) $$(SCHEME_SOURCES_EXT)
SCHEME_OBJS_$(1) := $$(foreach s,$$(_SCHEME_SRC_$(1)),$$(call obj_of,$(1),$$(s)))

# Capture SCHEME_CFLAGS at this point (after the scheme Makefile was included)
# so the test binary gets the same -D flags (e.g. -DKYBER_ASM_NTT) as the library.
SCHEME_CFLAGS_$(1) := $$(SCHEME_CFLAGS)

$$(foreach s,$$(filter %.c,$$(_SCHEME_SRC_$(1))),\
    $$(eval $$(call compile_c,$(1),$$(s),$$(SCHEME_CFLAGS) -Icrypto_kem/$(1))))

$$(foreach s,$$(filter %.S %.s,$$(_SCHEME_SRC_$(1))),\
    $$(eval $$(call compile_s,$(1),$$(s),$$(SCHEME_CFLAGS) -Icrypto_kem/$(1))))

$$(eval $$(call build_lib,$$(BUILD)/$(1)/libscheme.a,$$(SCHEME_OBJS_$(1))))

# ---- Test binary object ----
$(call obj_of,$(1),test/test_kem.c): test/test_kem.c
	$$(Q)mkdir -p $$(@D)
	@echo "  CC    $$<"
	$$(Q)$$(CC) -c $$(CFLAGS_COMMON) $$(SCHEME_CFLAGS_$(1)) -Icrypto_kem/$(1) -o $$@ $$<

# ---- Bench binary object ----
$(call obj_of,$(1),test/bench_kem.c): test/bench_kem.c
	$$(Q)mkdir -p $$(@D)
	@echo "  CC    $$<"
	$$(Q)$$(CC) -c $$(CFLAGS_COMMON) -Icrypto_kem/$(1) -o $$@ $$<

# Shorthand for the startup object of this scheme
_STARTUP_OBJ_$(1) := $$(call obj_of,$(1),$$(STARTUP_SOURCE))

# ---- Link test ELF ----
# The startup object is listed FIRST (before --start-group) so the linker
# sees _start before scanning libraries.  This is the key to fixing the
# "cannot find entry symbol _start" warning.
$(BUILD)/$(1)/test.elf: \
        $$(_STARTUP_OBJ_$(1)) \
        $$(call obj_of,$(1),test/test_kem.c) \
        $$(BUILD)/$(1)/libscheme.a \
        $$(BUILD)/$(1)/libcommon.a
	$$(Q)mkdir -p $$(@D)
	@echo "  LD    $$@"
	$$(Q)$$(CC) $$(CFLAGS_COMMON) \
	    -Wl,--gc-sections \
	    $$(PLATFORM_LDFLAGS) \
	    -Wl,-Map,$$(BUILD)/$(1)/test.map \
	    -o $$@ \
	    $$(_STARTUP_OBJ_$(1)) \
	    $$(call obj_of,$(1),test/test_kem.c) \
	    -Wl,--start-group \
	    $$(BUILD)/$(1)/libscheme.a \
	    $$(BUILD)/$(1)/libcommon.a \
	    -Wl,--end-group

# ---- Link bench ELF ----
$(BUILD)/$(1)/bench.elf: \
        $$(_STARTUP_OBJ_$(1)) \
        $$(call obj_of,$(1),test/bench_kem.c) \
        $$(BUILD)/$(1)/libscheme.a \
        $$(BUILD)/$(1)/libcommon.a
	$$(Q)mkdir -p $$(@D)
	@echo "  LD    $$@"
	$$(Q)$$(CC) $$(CFLAGS_COMMON) \
	    -Wl,--gc-sections \
	    $$(PLATFORM_LDFLAGS) \
	    -Wl,-Map,$$(BUILD)/$(1)/bench.map \
	    -o $$@ \
	    $$(_STARTUP_OBJ_$(1)) \
	    $$(call obj_of,$(1),test/bench_kem.c) \
	    -Wl,--start-group \
	    $$(BUILD)/$(1)/libscheme.a \
	    $$(BUILD)/$(1)/libcommon.a \
	    -Wl,--end-group

.PHONY: kem-$(1)
kem-$(1): $(BUILD)/$(1)/test.elf $(BUILD)/$(1)/bench.elf

endef


# ============================================================
# Scheme discovery — signatures
# ============================================================
SIGN_DIRS := $(patsubst crypto_sign/%/Makefile,%,$(wildcard crypto_sign/*/Makefile))

.PHONY: sign
sign: $(addprefix sign-,$(SIGN_DIRS))

# ============================================================
# Per-scheme DSA rule generator
# ============================================================
define gen_dsa_scheme

SCHEME_SOURCES     :=
SCHEME_SOURCES_EXT :=
SCHEME_CFLAGS      :=
include crypto_sign/$(1)/Makefile

_DSA_SRC_$(1) := $$(addprefix crypto_sign/$(1)/,$$(SCHEME_SOURCES)) $$(SCHEME_SOURCES_EXT)
DSA_OBJS_$(1) := $$(foreach s,$$(_DSA_SRC_$(1)),$$(call obj_of,$(1),$$(s)))

$$(foreach s,$$(filter %.c,$$(_DSA_SRC_$(1))),\
    $$(eval $$(call compile_c,$(1),$$(s),$$(SCHEME_CFLAGS) -Icrypto_sign/$(1))))
#added 24/06
$$(foreach s,$$(filter %.S %.s,$$(_DSA_SRC_$(1))),\
    $$(eval $$(call compile_s,$(1),$$(s),$$(SCHEME_CFLAGS) -Icrypto_sign/$(1))))

$$(eval $$(call build_lib,$$(BUILD)/$(1)/libscheme.a,$$(DSA_OBJS_$(1))))

# ---- test_sign object ----
$(call obj_of,$(1),test/test_sign.c): test/test_sign.c
	$$(Q)mkdir -p $$(@D)
	@echo "  CC    $$<"
	$$(Q)$$(CC) -c $$(CFLAGS_COMMON) -Icrypto_sign/$(1) -o $$@ $$<

# ---- bench_sign object ----
$(call obj_of,$(1),test/bench_sign.c): test/bench_sign.c
	$$(Q)mkdir -p $$(@D)
	@echo "  CC    $$<"
	$$(Q)$$(CC) -c $$(CFLAGS_COMMON) -Icrypto_sign/$(1) -o $$@ $$<

_DSA_STARTUP_$(1) := $$(call obj_of,$(1),$$(STARTUP_SOURCE))

# ---- Link test ELF ----
$(BUILD)/$(1)/test.elf: \
        $$(_DSA_STARTUP_$(1)) \
        $$(call obj_of,$(1),test/test_sign.c) \
        $$(BUILD)/$(1)/libscheme.a \
        $$(BUILD)/$(1)/libcommon.a
	$$(Q)mkdir -p $$(@D)
	@echo "  LD    $$@"
	$$(Q)$$(CC) $$(CFLAGS_COMMON) \
	    -Wl,--gc-sections \
	    $$(PLATFORM_LDFLAGS) \
	    -Wl,-Map,$$(BUILD)/$(1)/test.map \
	    -o $$@ \
	    $$(_DSA_STARTUP_$(1)) \
	    $$(call obj_of,$(1),test/test_sign.c) \
	    -Wl,--start-group \
	    $$(BUILD)/$(1)/libscheme.a \
	    $$(BUILD)/$(1)/libcommon.a \
	    -Wl,--end-group

# ---- Link bench ELF ----
$(BUILD)/$(1)/bench.elf: \
        $$(_DSA_STARTUP_$(1)) \
        $$(call obj_of,$(1),test/bench_sign.c) \
        $$(BUILD)/$(1)/libscheme.a \
        $$(BUILD)/$(1)/libcommon.a
	$$(Q)mkdir -p $$(@D)
	@echo "  LD    $$@"
	$$(Q)$$(CC) $$(CFLAGS_COMMON) \
	    -Wl,--gc-sections \
	    $$(PLATFORM_LDFLAGS) \
	    -Wl,-Map,$$(BUILD)/$(1)/bench.map \
	    -o $$@ \
	    $$(_DSA_STARTUP_$(1)) \
	    $$(call obj_of,$(1),test/bench_sign.c) \
	    -Wl,--start-group \
	    $$(BUILD)/$(1)/libscheme.a \
	    $$(BUILD)/$(1)/libcommon.a \
	    -Wl,--end-group

.PHONY: sign-$(1)
sign-$(1): $(BUILD)/$(1)/test.elf $(BUILD)/$(1)/bench.elf

endef

# ============================================================
# Instantiate rules for all KEM schemes
# ============================================================
$(foreach name,$(KEM_DIRS),$(eval $(call gen_startup_obj,$(name))))
$(foreach name,$(KEM_DIRS),$(eval $(call gen_common_lib,$(name))))
$(foreach name,$(KEM_DIRS),$(eval $(call gen_kem_scheme,$(name))))

$(foreach name,$(SIGN_DIRS),$(eval $(call gen_startup_obj,$(name))))
$(foreach name,$(SIGN_DIRS),$(eval $(call gen_common_lib,$(name))))
$(foreach name,$(SIGN_DIRS),$(eval $(call gen_dsa_scheme,$(name))))

# ============================================================
# Convenience targets (require SCHEME= on the command line)
# ============================================================
.PHONY: test bench run-test run-bench

test:  $(BUILD)/$(SCHEME)/test.elf
bench: $(BUILD)/$(SCHEME)/bench.elf

# What the run-* targets hand to qemu_run: the ELF for QEMU, the flashable
# image for boards that can run tests unattended (mk/dabao.mk sets bin).
RUN_IMAGE ?= elf

run-test: $(BUILD)/$(SCHEME)/test.$(RUN_IMAGE)
	@echo "  RUN   $<"
	$(call qemu_run,$<)

run-bench: $(BUILD)/$(SCHEME)/bench.$(RUN_IMAGE)
	@echo "  RUN   $<"
	$(call qemu_run,$<)

# ============================================================
# Primitives test — no scheme dependency, tests libcommon.a only
# ============================================================
_PRIM_DIR  := $(BUILD)/primitives
_PRIM_SU   := $(_PRIM_DIR)/obj/$(notdir $(STARTUP_SOURCE)).o
_PRIM_OBJS := $(foreach s,$(COMMON_SOURCES),$(_PRIM_DIR)/obj/$(notdir $(s)).o)
_PRIM_LIB  := $(_PRIM_DIR)/libcommon.a
_PRIM_OBJ  := $(_PRIM_DIR)/obj/test_primitives.c.o
_PRIM_ELF  := $(_PRIM_DIR)/test_primitives.elf

$(_PRIM_SU): $(STARTUP_SOURCE)
	$(Q)mkdir -p $(@D)
	@echo "  AS    $<"
	$(Q)$(CC) -c $(CFLAGS_COMMON) -o $@ $<

$(foreach s,$(filter %.c,$(COMMON_SOURCES)),    $(eval $(call compile_c,primitives,$(s),)))

$(_PRIM_LIB): $(_PRIM_OBJS)
	$(Q)mkdir -p $(@D)
	@echo "  AR    $@"
	$(Q)$(AR) rcs $@ $^

$(_PRIM_OBJ): test/test_primitives.c
	$(Q)mkdir -p $(@D)
	@echo "  CC    $<"
	$(Q)$(CC) -c $(CFLAGS_COMMON) -o $@ $<

$(_PRIM_ELF): $(_PRIM_SU) $(_PRIM_OBJ) $(_PRIM_LIB)
	$(Q)mkdir -p $(@D)
	@echo "  LD    $@"
	$(Q)$(CC) $(CFLAGS_COMMON) \
	    -Wl,--gc-sections \
	    $(PLATFORM_LDFLAGS) \
	    -Wl,-Map,$(_PRIM_DIR)/test_primitives.map \
	    -o $@ \
	    $(_PRIM_SU) $(_PRIM_OBJ) \
	    -Wl,--start-group $(_PRIM_LIB) -Wl,--end-group

.PHONY: primitives run-test-primitives
primitives: $(_PRIM_ELF)

run-test-primitives: $(_PRIM_ELF)
	@echo "  QEMU  $<"
	$(call qemu_run,$<)


# ============================================================
# Standalone ML-DSA NTT test/benchmark
# ============================================================

$(BUILD)/ml-dsa-44/obj/test_mldsa_ntt.c.o: test/test_mldsa_ntt.c
	$(Q)mkdir -p $(@D)
	@echo "  CC    $<"
	$(Q)$(CC) -c $(CFLAGS_COMMON) \
	    -Icrypto_sign/mldsa \
	    -Icrypto_sign/ml-dsa-44 \
	    -o $@ $<

$(BUILD)/ml-dsa-44/test_mldsa_ntt.elf: \
        $(call obj_of,ml-dsa-44,$(STARTUP_SOURCE)) \
        $(BUILD)/ml-dsa-44/obj/test_mldsa_ntt.c.o \
        $(BUILD)/ml-dsa-44/libscheme.a \
        $(BUILD)/ml-dsa-44/libcommon.a
	$(Q)mkdir -p $(@D)
	@echo "  LD    $@"
	$(Q)$(CC) $(CFLAGS_COMMON) \
	    -Wl,--gc-sections \
	    $(PLATFORM_LDFLAGS) \
	    -o $@ \
	    $(call obj_of,ml-dsa-44,$(STARTUP_SOURCE)) \
	    $(BUILD)/ml-dsa-44/obj/test_mldsa_ntt.c.o \
	    -Wl,--start-group \
	    $(BUILD)/ml-dsa-44/libscheme.a \
	    $(BUILD)/ml-dsa-44/libcommon.a \
	    -Wl,--end-group

.PHONY: run-test-mldsa-ntt
run-test-mldsa-ntt: $(BUILD)/ml-dsa-44/test_mldsa_ntt.elf
	@echo "  QEMU  $<"
	$(call qemu_run,$<)

.PHONY: flash-test-mldsa-ntt
flash-test-mldsa-ntt: $(BUILD)/ml-dsa-44/test_mldsa_ntt.bin
	$(call flash_bin,$<)
	
# Montgomery reduction test (HAETAE-specific)
$(BUILD)/haetae2/test_montgomery_reduce.elf: \
        $(call obj_of,haetae2,$(STARTUP_SOURCE)) \
        test/test_montgomery_reduce.c \
        $(BUILD)/haetae2/libscheme.a \
        $(BUILD)/haetae2/libcommon.a
	$(Q)mkdir -p $(@D)
	$(Q)$(CC) -c $(CFLAGS_COMMON) -Icrypto_sign/haetae2 \
	    -o $(BUILD)/haetae2/obj/test_montgomery_reduce.c.o \
	    test/test_montgomery_reduce.c
	$(Q)$(CC) $(CFLAGS_COMMON) \
	    -Wl,--gc-sections \
	    $(PLATFORM_LDFLAGS) \
	    -o $@ \
	    $(call obj_of,haetae2,$(STARTUP_SOURCE)) \
	    $(BUILD)/haetae2/obj/test_montgomery_reduce.c.o \
	    -Wl,--start-group \
	    $(BUILD)/haetae2/libscheme.a \
	    $(BUILD)/haetae2/libcommon.a \
	    -Wl,--end-group

.PHONY: run-test-montgomery-reduce
run-test-montgomery-reduce: $(BUILD)/haetae2/test_montgomery_reduce.elf
	$(call qemu_run,$<)
# ============================================================
# Run all KEM tests sequentially under QEMU
# ============================================================
.PHONY: run-all-sign
run-all-sign: $(foreach n,$(SIGN_DIRS),$(BUILD)/$(n)/test.$(RUN_IMAGE))
	$(foreach n,$(SIGN_DIRS), \
	    echo "=== $(n) ===" && \
	    $(call qemu_run,$(BUILD)/$(n)/test.$(RUN_IMAGE)) ; )

.PHONY: run-all-kem
run-all-kem: $(foreach n,$(KEM_DIRS),$(BUILD)/$(n)/test.$(RUN_IMAGE))
	$(foreach n,$(KEM_DIRS), \
	    echo "=== $(n) ===" && \
	    $(call qemu_run,$(BUILD)/$(n)/test.$(RUN_IMAGE)) ; )

# Every scheme's benchmark, one after the other (on the Dabao: unattended,
# results collected in BENCH_CSV).
.PHONY: run-all-bench
run-all-bench: $(foreach n,$(KEM_DIRS) $(SIGN_DIRS),$(BUILD)/$(n)/bench.$(RUN_IMAGE))
	@$(foreach n,$(KEM_DIRS) $(SIGN_DIRS), \
	    echo "=== $(n) ===" && \
	    $(call qemu_run,$(BUILD)/$(n)/bench.$(RUN_IMAGE)) ; )

# ============================================================
# Size report
# ============================================================
.PHONY: size
size: $(foreach n,$(KEM_DIRS),$(BUILD)/$(n)/test.elf) $(foreach n,$(SIGN_DIRS),$(BUILD)/$(n)/test.elf)
	$(SIZE) $^

# ============================================================
# Clean
# ============================================================
.PHONY: clean
clean:
	rm -rf $(BUILD)

# ============================================================
# Help
# ============================================================
.PHONY: help
help:
	@echo ""
	@echo "pqriscv — RISC-V post-quantum crypto benchmark framework"
	@echo ""
	@echo "KEM schemes found:"
	@$(foreach n,$(KEM_DIRS), echo "  $(n)";)
	@echo ""
	@echo "Targets:"
	@echo "  all                              build everything"
	@echo "  kem                              build all KEM schemes"
	@echo "  SCHEME=<name> test               build test ELF"
	@echo "  SCHEME=<name> bench              build bench ELF"
	@echo "  SCHEME=<name> run-test           build + run test under QEMU"
	@echo "  SCHEME=<name> run-bench          build + run bench under QEMU"
	@echo "  run-all-kem                      run all KEM tests under QEMU"
	@echo "  run-all-sign                     run all DSA tests under QEMU"
	@echo "  run-all-bench                    run every benchmark (Dabao: -> benchmarks/dabao.csv)"
	@echo "  sign                             build all DSA schemes"
	@echo "  primitives                       build primitives test ELF"
	@echo "  run-test-primitives              build + run primitives KAT under QEMU"
	@echo "  size                             print ELF sizes"
	@echo "  clean                            remove build/ directory"
	@echo ""
	@echo "Options:"
	@echo "  V=1                              verbose output"
	@echo "  PREFIX=<triplet>                 toolchain prefix (default: riscv64-unknown-elf)"
	@echo "  QEMU_EXTRA=<flags>               extra QEMU flags"
	@echo ""

# ============================================================
# Binary image generation (ESP32 platforms)
# ============================================================
%.bin: %.elf
	$(call elf2bin,$<)

.PHONY: bin-test bin-bench
bin-test:  $(BUILD)/$(SCHEME)/test.bin
bin-bench: $(BUILD)/$(SCHEME)/bench.bin

# ============================================================
# Hardware flash targets
# ============================================================
.PHONY: flash-test flash-bench
flash-test: $(BUILD)/$(SCHEME)/test.bin
	$(call flash_bin,$<)

flash-bench: $(BUILD)/$(SCHEME)/bench.bin
	$(call flash_bin,$<)

.PHONY: bin-all-kem bin-all-sign
bin-all-kem:  $(foreach n,$(KEM_DIRS),$(BUILD)/$(n)/test.bin)
bin-all-sign: $(foreach n,$(SIGN_DIRS),$(BUILD)/$(n)/test.bin)
