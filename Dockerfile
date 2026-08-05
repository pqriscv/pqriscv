# =============================================================================
# pqriscv — RISC-V post-quantum crypto build + test container
#
# Build:      docker build -t pqriscv .
# Run all:    docker run --rm pqriscv
# One scheme: docker run --rm pqriscv make SCHEME=ml-kem-512 run-test
# Shell:      docker run --rm -it pqriscv bash
# =============================================================================

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ─── Toolchain + C library + QEMU ────────────────────────────────────────────
#
#  gcc-riscv64-unknown-elf        bare-metal cross compiler
#  binutils-riscv64-unknown-elf   assembler / linker
#  picolibc-riscv64-unknown-elf   C library headers + stubs (replaces newlib)
#                                 → provides string.h, stdint.h, stdio.h …
#                                 → provides --specs=picolibc.specs
#  qemu-system-misc               qemu-system-riscv32 (virt machine)
#
# On Arch Linux the "riscv64-elf-gcc" AUR package bundles newlib, so no
# extra package is needed there.  On Ubuntu/Debian you need picolibc.
# ─────────────────────────────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc-riscv64-unknown-elf \
        binutils-riscv64-unknown-elf \
        picolibc-riscv64-unknown-elf \
        qemu-system-misc \
        make \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Sanity-check: confirm key binaries are present and picolibc.specs is found
RUN riscv64-unknown-elf-gcc --version && \
    qemu-system-riscv32 --version    && \
    riscv64-unknown-elf-gcc -specs=picolibc.specs -print-multi-lib > /dev/null

# ─── Project ──────────────────────────────────────────────────────────────────
WORKDIR /workspace
COPY . .

# ─── Default: build + test all three ML-KEM variants ─────────────────────────
# make exits non-zero on build failure; QEMU exits non-zero on RESULT: FAIL
# (via the SiFive test device write in _exit).  `set -e` propagates both.
CMD ["bash", "-c", "\
    set -e; \
    for scheme in ml-kem-512 ml-kem-768 ml-kem-1024; do \
        echo; \
        echo '============================================================'; \
        echo \"  $scheme\"; \
        echo '============================================================'; \
        make --no-print-directory SCHEME=$scheme run-test; \
    done; \
    echo; echo 'All schemes passed.'; \
"]
