# mk/config.mk — Toolchain and global path configuration
#
# Override any of these on the command line, e.g.:
#   make PREFIX=riscv32-unknown-elf-gcc all

# --------------------------------------------------------------------------
# Toolchain (riscv64-unknown-elf-* handles RV32 via -march=rv32...)
# Install on Debian/Ubuntu:
#   sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
# --------------------------------------------------------------------------
# PREFIX   ?= riscv64-elf
PREFIX ?= riscv64-unknown-elf
CC       := $(PREFIX)-gcc
AR       := $(PREFIX)-ar
OBJCOPY  := $(PREFIX)-objcopy
OBJDUMP  := $(PREFIX)-objdump
GDB      := $(PREFIX)-gdb
SIZE     := $(PREFIX)-size

# --------------------------------------------------------------------------
# Build directories
# --------------------------------------------------------------------------
BUILD    := build

# Verbosity: set V=1 to see full commands
ifeq ($(V),1)
Q :=
else
Q := @
endif
