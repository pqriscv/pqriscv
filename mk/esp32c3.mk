# mk/esp32c3.mk — ESP32-C3 bare-metal platform (RISC-V RV32IMC, up to 160 MHz)
#
# The ROM first-stage bootloader (always in ROM, cannot be replaced):
#   - Initialises flash cache, UART0 @ 115200 baud, CPU clock
#   - Reads the ESP image header at flash offset 0x0
#   - Copies each loadable segment to its target RAM address
#   - Jumps to the ELF entry point
#
# We produce the ESP image with:   esptool.py elf2image ...
# We flash it with:                esptool.py write_flash 0x0 ...
#
# ── Quick reference ──────────────────────────────────────────────────────────
# Build:   make PLATFORM=esp32c3 SCHEME=ml-kem-512 test
# .bin:    make PLATFORM=esp32c3 SCHEME=ml-kem-512 bin-test
# Flash:   make PLATFORM=esp32c3 SCHEME=ml-kem-512 flash-test FLASH_PORT=/dev/ttyUSB0
# Monitor: screen /dev/ttyUSB0 115200   (or scripts/monitor.sh)
# ─────────────────────────────────────────────────────────────────────────────

PLATFORM_NAME := esp32c3

# ESP32-C3 is RV32IMC — NO A (atomics) or F (float) extensions.
# The fastntt_rv.S in this repo already targets RV32IM exclusively.
ARCH_FLAGS := -march=rv32imc_zicsr_zifencei -mabi=ilp32

LDSCRIPT := common/esp32c3/esp32c3.ld

PLATFORM_CFLAGS := \
    --specs=nano.specs     \
    --specs=nosys.specs    \
    $(ARCH_FLAGS)          \
    -Icommon               \
    -Icommon/esp32c3       \
    -DESP32C3

PLATFORM_LDFLAGS := \
    -fuse-ld=bfd                    \
    -nostartfiles                   \
    -Wl,--wrap=_sbrk                \
    -Wl,--no-warn-rwx-segments      \
    -ffreestanding                  \
    $(ARCH_FLAGS)                   \
    -T$(LDSCRIPT)

STARTUP_SOURCE := common/esp32c3/startup_esp32c3.S

COMMON_SOURCES := \
    common/hal-esp-riscv.c  \
    common/randombytes.c    \
    common/fips202.c        \
    common/sha2.c           \
    common/aes.c            \
    common/nistrng.c

# ── esptool.py knobs (override on CLI) ───────────────────────────────────────
ESPTOOL      ?= esptool.py
FLASH_PORT   ?= /dev/ttyUSB0
FLASH_BAUD   ?= 460800
FLASH_MODE   ?= dio
FLASH_FREQ   ?= 80m
FLASH_SIZE   ?= 4MB
FLASH_OFFSET ?= 0x0

# elf2bin(elf_path) — convert ELF → ESP32-C3 image binary
define elf2bin
	@echo "  BIN   $(1:.elf=.bin)"
	$(Q)$(ESPTOOL) --chip esp32c3 elf2image \
	    --flash_mode $(FLASH_MODE)           \
	    --flash_freq $(FLASH_FREQ)           \
	    --flash_size $(FLASH_SIZE)           \
	    --output $(1:.elf=.bin) $(1)
endef

# flash_bin(bin_path) — program binary to board
define flash_bin
	@echo "  FLASH $(1) → $(FLASH_PORT)"
	$(Q)$(ESPTOOL) --chip esp32c3           \
	    --port $(FLASH_PORT)                 \
	    --baud $(FLASH_BAUD)                 \
	    write_flash                          \
	    --flash_mode $(FLASH_MODE)           \
	    --flash_freq $(FLASH_FREQ)           \
	    --flash_size $(FLASH_SIZE)           \
	    $(FLASH_OFFSET) $(1)
endef

# No QEMU on hardware targets
qemu_run = @echo "  SKIP  QEMU run (hardware target). Use 'flash-test' instead."
