# mk/esp32c6.mk — ESP32-C6 bare-metal platform
#
# ESP32-C6 has two cores:
#   HP core: RV32IMAC @ up to 160 MHz  ← this target
#   LP core: RV32IMC  @       20 MHz   (not targeted here)
#
# Same ROM bootloader protocol as ESP32-C3: loads segments from flash → RAM,
# jumps to entry point.  UART0 pre-initialised at 115200 baud.
#
# Key difference vs C3: ARCH_FLAGS includes the A extension (atomics).
# The fastntt_rv.S targets RV32IM and is compatible with both C3 and C6.
#
# ── Quick reference ──────────────────────────────────────────────────────────
# Build:   make PLATFORM=esp32c6 SCHEME=ml-dsa-44 test
# .bin:    make PLATFORM=esp32c6 SCHEME=ml-dsa-44 bin-test
# Flash:   make PLATFORM=esp32c6 SCHEME=ml-dsa-44 flash-test FLASH_PORT=/dev/ttyUSB0
# ─────────────────────────────────────────────────────────────────────────────

PLATFORM_NAME := esp32c6

# ESP32-C6 HP core is RV32IMAC — has A (atomics), no F (float).
ARCH_FLAGS := -march=rv32imac_zicsr_zifencei -mabi=ilp32

LDSCRIPT := common/esp32c6/esp32c6.ld

PLATFORM_CFLAGS := \
    --specs=picolibc.specs \
    $(ARCH_FLAGS)          \
    -Icommon               \
    -Icommon/esp32c6       \
    -DESP32C6

PLATFORM_LDFLAGS := \
    -fuse-ld=bfd                    \
    -nostartfiles                   \
    -Wl,--wrap=_sbrk                \
    -Wl,--no-warn-rwx-segments      \
    -ffreestanding                  \
    $(ARCH_FLAGS)                   \
    -T$(LDSCRIPT)

STARTUP_SOURCE := common/esp32c6/startup_esp32c6.S

COMMON_SOURCES := \
    common/hal-esp-riscv.c  \
    common/randombytes.c    \
    common/fips202.c        \
    common/sha2.c           \
    common/aes.c            \
    common/nistrng.c

# ── esptool.py knobs ─────────────────────────────────────────────────────────
ESPTOOL      ?= esptool.py
FLASH_PORT   ?= /dev/ttyUSB0
FLASH_BAUD   ?= 460800
FLASH_MODE   ?= dio
FLASH_FREQ   ?= 80m
FLASH_SIZE   ?= 4MB
FLASH_OFFSET ?= 0x0

define elf2bin
	@echo "  BIN   $(1:.elf=.bin)"
	$(Q)$(ESPTOOL) --chip esp32c6 elf2image \
	    --flash_mode $(FLASH_MODE)           \
	    --flash_freq $(FLASH_FREQ)           \
	    --flash_size $(FLASH_SIZE)           \
	    --output $(1:.elf=.bin) $(1)
endef

define flash_bin
	@echo "  FLASH $(1) → $(FLASH_PORT)"
	$(Q)$(ESPTOOL) --chip esp32c6           \
	    --port $(FLASH_PORT)                 \
	    --baud $(FLASH_BAUD)                 \
	    write_flash                          \
	    --flash_mode $(FLASH_MODE)           \
	    --flash_freq $(FLASH_FREQ)           \
	    --flash_size $(FLASH_SIZE)           \
	    $(FLASH_OFFSET) $(1)
endef

qemu_run = @echo "  SKIP  QEMU run (hardware target). Use 'flash-test' instead."
