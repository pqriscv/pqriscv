# mk/qemu.mk — QEMU RISC-V 32 "virt" machine platform
#
# Install QEMU:
#   sudo apt install qemu-system-misc

PLATFORM_NAME := qemu-riscv32

# --------------------------------------------------------------------------
# Architecture flags
# --------------------------------------------------------------------------
ARCH_FLAGS := -march=rv32imac_zicsr_zifencei -mabi=ilp32

LDSCRIPT := common/riscv/virt.ld

PLATFORM_CFLAGS := \
    $(ARCH_FLAGS)        \
    -Icommon             \
    -Icommon/riscv       \
    -DRISCV_VIRT
PLATFORM_CFLAGS += --specs=picolibc.specs
# NOTE: --specs=picolibc.specs is intentionally absent here.
# It lives in PLATFORM_CFLAGS above and reaches the linker via CFLAGS_COMMON
# (the link command is: $(CC) $(CFLAGS_COMMON) $(PLATFORM_LDFLAGS) ...).
# Passing it a second time triggers "attempt to rename spec 'link' to already
# defined spec 'picolibc_link'" and aborts the link.
PLATFORM_LDFLAGS := \
    -fuse-ld=bfd                   \
    -nostartfiles                  \
    -Wl,--wrap=_sbrk               \
    -Wl,--no-warn-rwx-segments     \
    -ffreestanding                 \
    $(ARCH_FLAGS)                  \
    -T$(LDSCRIPT)

# --------------------------------------------------------------------------
# Startup object — MUST be linked directly, NOT inside libcommon.a.
#
# Rationale: the linker only extracts archive members when they satisfy an
# undefined symbol reference.  _start is referenced only by the CPU/QEMU
# (not by any C code), so if startup_riscv.S lives inside libcommon.a the
# linker never pulls it out and warns "cannot find entry symbol _start".
#
# STARTUP_SOURCE is compiled into its own .o and placed first on the ld
# command line in every ELF link rule (see Makefile).
# --------------------------------------------------------------------------
STARTUP_SOURCE := common/riscv/startup_riscv.S

# --------------------------------------------------------------------------
# Common library sources — hal, symmetric primitives, RNGs.
# startup_riscv.S is intentionally absent (see above).
# --------------------------------------------------------------------------
COMMON_SOURCES := \
    common/hal-riscv.c   \
    common/randombytes.c \
    common/fips202.c     \
    common/sha2.c        \
    common/aes.c         \
    common/nistrng.c

# --------------------------------------------------------------------------
# QEMU invocation
# --------------------------------------------------------------------------
QEMU       := qemu-system-riscv32
QEMUFLAGS  := -machine virt -bios none -nographic
QEMU_EXTRA ?=

qemu_run = $(QEMU) $(QEMUFLAGS) $(QEMU_EXTRA) -kernel $(1)

# ── No-op stubs for cross-platform Makefile compatibility ────────────────────
# The top-level Makefile's %.bin and flash-* targets call elf2bin / flash_bin.
# For the QEMU platform these are intentional no-ops.

define elf2bin
	@echo "  SKIP  elf2bin (QEMU target — use PLATFORM=esp32c3 for .bin output)"
endef

define flash_bin
	@echo "  SKIP  flash   (QEMU target — use 'run-test' instead)"
endef
