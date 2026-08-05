# pqriscv — Post-Quantum Crypto Benchmarking Framework for RISC-V

A [pqm4](https://github.com/mupq/pqm4)-style framework for testing and
benchmarking post-quantum cryptographic schemes on bare-metal RISC-V.
No liboqs, no OS, no IDF/FreeRTOS — just a HAL, a linker script, and
`make`.

Supported platforms:

| Platform  | Core / ISA          | `PLATFORM=` | Status        |
|-----------|---------------------|-------------|---------------|
| QEMU virt | RV32IMAC (emulated) | `qemu`      | ✅ (default)  |
| ESP32-C3  | RV32IMC             | `esp32c3`   | ✅            |
| ESP32-C6  | RV32IMAC (HP core)  | `esp32c6`   | ✅            |
| ESP32     | Xtensa LX6          | `esp32`     | 🚧 TODO       |

See [README-ESP32.md](README-ESP32.md) for the ESP32 bare-metal port
(boot flow, flashing, Docker build environment, watchdog/perf-counter
details).

Implemented schemes:

- **ML-KEM** (FIPS 203): `ml-kem-512`, `ml-kem-768`, `ml-kem-1024` —
  shared implementation in `crypto_kem/mlkem/`, with an optional RV32
  assembly NTT using Plantard arithmetic (`-DKYBER_ASM_NTT`).
- **ML-DSA** (FIPS 204): `ml-dsa-44`, `ml-dsa-65`, `ml-dsa-87` —
  shared implementation in `crypto_sign/mldsa/`, with RV32 assembly
  Montgomery reduction / NTT routines.
- **FN-DSA** (provisional, Falcon-based): `fndsa_provisional-512`,
  `fndsa_provisional-1024` — shared implementation in
  `crypto_sign/fndsa_provisional/`.

---

## Project structure

```
pqriscv/
├── Makefile                   # top-level build system (schemes auto-discovered)
├── mk/
│   ├── config.mk              # toolchain configuration
│   ├── qemu.mk                # QEMU virt platform flags & run targets
│   ├── esp32c3.mk             # ESP32-C3 flags, image + flash targets
│   ├── esp32c6.mk             # ESP32-C6 flags, image + flash targets
│   └── esp32.mk               # ESP32 (Xtensa) roadmap
├── common/                    # shared library (libcommon.a)
│   ├── hal.h                  # HAL interface
│   ├── hal-riscv.c            # QEMU virt HAL (NS16550A UART, time/timeh CSRs)
│   ├── hal-esp-riscv.c        # ESP32-C3/C6 HAL (UART0, WDTs, perf-counter CSRs)
│   ├── randombytes.h/.c       # RNG (PRNG fallback on QEMU)
│   ├── fips202.h/.c           # SHA-3 / SHAKE (FIPS 202)
│   ├── sha2.h/.c              # SHA-256 / SHA-512 (FIPS 180-4)
│   ├── aes.h/.c               # AES-128/256 ECB (for NIST RNG only)
│   ├── nistrng.h/.c           # NIST AES-256-CTR DRBG (KAT generation)
│   ├── symmetric-shake.c/.h   # SHAKE-based symmetric layer for schemes
│   ├── riscv/                 # QEMU virt startup + linker script
│   ├── esp32c3/               # ESP32-C3 startup + linker script
│   └── esp32c6/               # ESP32-C6 startup + linker script
├── crypto_kem/
│   ├── mlkem/                 # shared ML-KEM sources (+ RV32 Plantard NTT asm)
│   └── ml-kem-{512,768,1024}/ # per-parameter-set api.h, params.h, Makefile
├── crypto_sign/
│   ├── mldsa/                 # shared ML-DSA sources (+ RV32 asm)
│   ├── ml-dsa-{44,65,87}/     # per-parameter-set api.h, params.h, Makefile
│   ├── fndsa_provisional/     # shared FN-DSA sources
│   └── fndsa_provisional-{512,1024}/
├── test/
│   ├── test_kem.c             # KEM functional test + implicit-rejection check
│   ├── bench_kem.c            # KEM min/max/avg timing benchmark
│   ├── test_sign.c            # signature functional test
│   ├── bench_sign.c           # signature timing benchmark
│   └── test_primitives.c      # SHA-3/SHAKE/SHA-2/DRBG self-tests
├── scripts/                   # flash_esp.sh, monitor.sh, gen_test_vectors.py
├── Dockerfile / Dockerfile.esp32 / docker-compose.yml
└── README-ESP32.md
```

---

## Prerequisites

```bash
# Toolchain (a riscv64 toolchain handles RV32 via -march=rv32...)
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
# On Arch the prefix is riscv64-elf; override with: make PREFIX=riscv64-elf ...

# QEMU (for the default platform)
sudo apt install qemu-system-misc
```

Verify:
```bash
riscv64-unknown-elf-gcc --version
qemu-system-riscv32 --version
```

For ESP32 targets you additionally need `esptool.py`, or use the
provided Docker environment (`Dockerfile.esp32`, `docker-compose.yml`).

> Note: if your shell exports `LDFLAGS=-fuse-ld=mold` (or similar),
> unset it for cross builds — bare-metal linker scripts require GNU ld.

---

## Build & run

The platform defaults to QEMU; select ESP32 boards with `PLATFORM=`.

```bash
# QEMU virt (default)
make SCHEME=ml-kem-768 run-test
make SCHEME=ml-dsa-44  run-bench
make run-all-kem                      # every KEM test sequentially
make run-all-sign                     # every signature test sequentially

# ESP32-C6 (real hardware)
make PLATFORM=esp32c6 SCHEME=ml-dsa-44 bin-test
make PLATFORM=esp32c6 SCHEME=ml-dsa-44 flash-test FLASH_PORT=/dev/ttyUSB0
./scripts/monitor.sh /dev/ttyUSB0
```

| Target | Description |
|--------|-------------|
| `make all` | Build primitives + every KEM and signature scheme |
| `make kem` / `make sign` | Build all KEM / signature schemes |
| `make primitives` | Build the symmetric-primitives self-test |
| `make SCHEME=<s> test` / `bench` | Build test/bench ELF for one scheme |
| `make SCHEME=<s> run-test` / `run-bench` | Build + run under QEMU |
| `make run-test-primitives` | Run the primitives self-test under QEMU |
| `make SCHEME=<s> bin-test` / `bin-bench` | Produce flashable ESP image (.bin) |
| `make SCHEME=<s> flash-test` / `flash-bench` | Flash to an ESP32 board |
| `make bin-all-kem` / `bin-all-sign` | Build all flashable images |
| `make size` | Print ELF sizes |
| `make V=1 ...` | Verbose build |
| `make clean` | Remove `build/` |
| `make help` | Show quick-start help |

---

## Adding a scheme

Each scheme lives in `crypto_kem/<name>/` or `crypto_sign/<name>/` and
is auto-discovered by the presence of its `Makefile`. A parameter-set
directory typically contains only `api.h`, `params.h`, and a `Makefile`
pointing at a shared implementation:

```makefile
# crypto_kem/ml-kem-768/Makefile
MLKEM_DIR = crypto_kem/mlkem

SCHEME_SOURCES_EXT = \
    common/symmetric-shake.c \
    $(MLKEM_DIR)/kem.c       \
    $(MLKEM_DIR)/indcpa.c    \
    ...                      \
    $(MLKEM_DIR)/fastntt_rv.S

SCHEME_CFLAGS = -I$(MLKEM_DIR) -Icrypto_kem/ml-kem-768 -DKYBER_ASM_NTT
```

Use `SCHEME_SOURCES` for files inside the scheme directory itself, and
`SCHEME_SOURCES_EXT` for files elsewhere in the tree. The test/bench
harnesses in `test/` are shared and unchanged across schemes.

---

## HAL API

```c
void     hal_setup(enum clock_mode);   // CLOCK_FAST or CLOCK_BENCHMARK
void     hal_send_str(const char *s);  // print a line via UART
uint64_t hal_get_time(void);           // 64-bit tick count
size_t   hal_get_stack_size(void);     // bytes between SP and heap top
```

Always call `hal_setup()` first — on ESP32 it disables the ROM
watchdogs (TIMG0/RTC/SWD); skipping it makes long operations (e.g.
ML-DSA signing) die mid-run.

Timers:
- **QEMU virt**: `time`/`timeh` CSRs at **10 MHz** (100 ns/tick).
- **ESP32-C3/C6**: the standard `mcycle`/`cycle` CSRs are not
  implemented; the HAL uses Espressif's custom perf-counter CSRs
  (MPCER/MPCMR/MPCCR) to count cycles. The counter is 32-bit, so
  deltas are computed in `uint32_t`.

---

## Symmetric primitives API

All functions are available by including the corresponding header from `common/`:

```c
// FIPS 202 — SHA-3 / SHAKE
#include "fips202.h"
shake128(out, outlen, in, inlen);
shake256(out, outlen, in, inlen);
sha3_256(h, in, inlen);
sha3_512(h, in, inlen);
// Incremental: shake128_init / _absorb / _finalize / _squeezeblocks / _squeeze

// FIPS 180-4 — SHA-2
#include "sha2.h"
sha256(digest, in, inlen);
sha512(digest, in, inlen);

// NIST AES-256-CTR DRBG (KAT generation only)
#include "nistrng.h"
randombytes_init(seed48, NULL, 256);
randombytes_nist(buf, len);
```

---

## Notes

- `randombytes.c` uses a PRNG fallback on QEMU (prints a `#warning` at
  compile time). The NIST DRBG (`nistrng`) is used in the test harness
  for deterministic KAT generation.
- `aes.c` is **not constant-time** and must not be used in scheme
  implementations; it only drives the NIST RNG.
- Stack on QEMU `virt` defaults to 16 KiB (set in `virt.ld`); increase
  `STACK_SIZE` if your scheme overflows. On ESP32-C6 the stack grows
  down from the top of SRAM and `STACK_SIZE` is only a link-time floor.

---

## Contributors

- Gustavo Banegas `<gustavo[at]cryptme.in>`
- Maria Tudorache `<maria.tudorache[at]polytechnique.edu>`

---

## Citing

If you use pqriscv in your work, please cite it as:

```bibtex
@misc{PQRISCV,
  title = {{pqriscv}: Post-quantum crypto library for bare-metal {RISC-V}},
  author = {Gustavo Banegas and Maria Tudorache},
  note = {\url{https://github.com/pqriscv/pqriscv}}
}
```

---

## License

Different parts of **pqriscv** have different licenses.
Each subdirectory containing implementations contains a LICENSE or COPYING file stating
under what license that specific implementation is released.
The files in common contain licensing information at the top of the file (and
are currently either public domain or MIT).

All other code in this repository is dual-licensed under [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0) and under the conditions of [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
