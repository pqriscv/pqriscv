# mk/dabao.mk — Baochip-1x "Dabao" evaluation board, bare metal
#
# Baochip-1x: VexRiscv RV32IMAC (+MMU, unused here) @ 350 MHz,
#             2 MiB SRAM, 4 MiB RRAM (non-volatile, execute in place).
#
# Boot chain (always present, cannot be bypassed):
#   boot0 (immutable) → boot1 (USB mass storage / UF2 loader) → our image
#   - boot1 only runs images signed with Ed25519ph. Bare-metal images are
#     signed with the published developer key (scripts/bao1x_image.py).
#   - boot1 leaves clocks, SRAM trims and UART2 (PB13/PB14, 1 Mbaud) set up.
#
# NOTE: the first developer-signed image a board boots makes boot1 erase the
# device's factory secrets and mark it as a developer unit. That is one-way.
# It is the intended path for bare-metal work; just be aware of it.
#
# ── Quick reference ──────────────────────────────────────────────────────────
# Build:   make PLATFORM=dabao SCHEME=ml-kem-768 test
# .uf2:    make PLATFORM=dabao SCHEME=ml-kem-768 bin-test
# Flash:   make PLATFORM=dabao SCHEME=ml-kem-768 flash-test
#          (board in boot1 mode, mounted as the BAOCHIP drive; then press PROG)
# Monitor: scripts/monitor.sh /dev/ttyUSB0 115200
#          (3.3 V USB-UART adapter: adapter RX ← PB14, GND ↔ GND)
# ─────────────────────────────────────────────────────────────────────────────

PLATFORM_NAME := dabao

# RV32IMAC — no F/D extension.
ARCH_FLAGS := -march=rv32imac_zicsr_zifencei -mabi=ilp32

LDSCRIPT := common/dabao/dabao.ld

# C library: picolibc if the toolchain has it (as on the QEMU platform),
# otherwise full newlib (Arch's riscv64-elf-newlib, xPack riscv-none-elf).
# Not nano.specs: its printf has no %llu, which test_kem/test_sign use.
LIBC_SPECS ?= $(shell $(CC) --specs=picolibc.specs -E -x c /dev/null >/dev/null 2>&1 \
                 && echo --specs=picolibc.specs || echo --specs=nosys.specs)

# Console baud rate on PB14 (boot1's own messages there are at 1 Mbaud).
DABAO_BAUD ?= 115200

PLATFORM_CFLAGS := \
    $(LIBC_SPECS)          \
    $(ARCH_FLAGS)          \
    -Icommon               \
    -Icommon/dabao         \
    -DDABAO                \
    -DDABAO_BAUD=$(DABAO_BAUD)

PLATFORM_LDFLAGS := \
    -fuse-ld=bfd                    \
    -nostartfiles                   \
    -Wl,--wrap=_sbrk                \
    -Wl,--no-warn-rwx-segments      \
    -ffreestanding                  \
    $(ARCH_FLAGS)                   \
    -T$(LDSCRIPT)

STARTUP_SOURCE := common/dabao/startup_dabao.S

COMMON_SOURCES := \
    common/hal-dabao.c      \
    common/randombytes.c    \
    common/fips202.c        \
    common/sha2.c           \
    common/aes.c            \
    common/nistrng.c

# ── Image + flash knobs (override on CLI) ────────────────────────────────────
PYTHON      ?= python3
# Mount point of the BAOCHIP drive; empty = let scripts/flash_dabao.sh find it.
DABAO_MOUNT ?=

# elf2bin(elf_path) — ELF → signed image (.bin) + the same image as UF2 (.uf2)
#   .raw  what the linker placed in RRAM, starting at 0x60060300
#   .bin  768-byte signature block + .raw, i.e. the slot contents @ 0x60060000
#   .uf2  .bin wrapped for boot1's mass-storage loader — this is what you flash
define elf2bin
	@echo "  BIN   $(1:.elf=.bin)"
	$(Q)$(OBJCOPY) -O binary $(1) $(1:.elf=.raw)
	$(Q)$(PYTHON) scripts/bao1x_image.py $(1:.elf=.raw) $(1:.elf=.bin) $(1:.elf=.uf2)
endef

# flash_bin(bin_path) — copy the matching .uf2 onto the BAOCHIP drive
define flash_bin
	@echo "  FLASH $(1:.bin=.uf2)"
	$(Q)scripts/flash_dabao.sh $(1:.bin=.uf2) $(DABAO_MOUNT)
endef

# No QEMU on hardware targets
qemu_run = @echo "  SKIP  QEMU run (hardware target). Use 'flash-test' instead."
