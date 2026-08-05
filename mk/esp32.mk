# mk/esp32.mk — ESP32 (Xtensa LX6) bare-metal platform  [STUB — NOT YET IMPLEMENTED]
#
# The original ESP32 uses a dual-core Xtensa LX6 @ 240 MHz.  This is a
# completely different architecture from the RISC-V variants (C3, C6):
#
#   • Toolchain: xtensa-esp32-elf-gcc   (Espressif release, NOT riscv64-unknown-elf)
#     Download: https://github.com/espressif/crosstool-NG/releases
#   • Architecture: Xtensa LX6 with windowed registers, no CSRs
#   • UART0 base: 0x3FF40000  (different from C3/C6's 0x60000000)
#   • Cycle counter: RSR a0, CCOUNT  (Xtensa-specific instruction)
#   • IRAM: 0x40080000  (192 KB)
#   • DRAM: 0x3FFB0000  (320 KB available)
#   • Flash code cache: 0x400D0000+
#   • Flash data cache: 0x3F400000+
#
# The pure-C crypto code (ML-KEM, ML-DSA) will compile with xtensa-esp32-elf-gcc
# unchanged.  The RV32IM assembly NTT (fastntt_rv.S, reduce_rv.S) needs an
# Xtensa equivalent or a C fallback (compile WITHOUT -DKYBER_ASM_NTT).
#
# TODO:
#   [ ] Write common/esp32/startup_esp32.S  (Xtensa entry, WindowBase, RSR CCOUNT)
#   [ ] Write common/esp32/esp32.ld
#   [ ] Write common/hal-esp32-xtensa.c     (UART @ 0x3FF40000, CCOUNT timing)
#   [ ] Add xtensa-esp32-elf cross-compiler to Dockerfile.esp32
#   [ ] Drop -DKYBER_ASM_NTT in SCHEME_CFLAGS (no RV32 ASM on Xtensa)
#
# This file exists as a placeholder so that `make PLATFORM=esp32` fails loudly
# rather than silently including the wrong platform file.

$(error ESP32 (Xtensa) support is not yet implemented. \
    See mk/esp32.mk for the implementation roadmap. \
    Use PLATFORM=esp32c3 or PLATFORM=esp32c6 for the RISC-V ESP variants.)
