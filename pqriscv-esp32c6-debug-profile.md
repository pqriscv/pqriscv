# Debugging & Profiling pqriscv on the ESP32-C6

**Project brief for a bachelor student.**
Target board: ESP32-C6 (RV32IMAC HP core). Codebase:
[`pqriscv`](https://github.com/pqriscv/pqriscv) — a bare-metal, pqm4-style
PQC benchmarking framework (no IDF, no FreeRTOS).

The goal of this project is to set up a real on-chip debug + profiling
workflow for post-quantum schemes (ML-KEM, ML-DSA, FN-DSA) running on the
board, and to use it to understand *where the cycles go* inside a scheme.

---

## Learning goals

By the end you should be able to:

1. Flash a scheme to the ESP32-C6 and attach a debugger over the built-in
   USB-JTAG — no external probe.
2. Set breakpoints, single-step, and inspect registers/memory/variables,
   both from the command line and from a GUI.
3. Measure per-operation cycle counts and break a single operation down
   into its internal phases (e.g. NTT vs. hashing vs. sampling).
4. Produce a statistical PC-sampling profile and read it with `gprof`.
5. Measure peak stack usage per scheme.

---

## 0. Background: how debugging works here

The ESP32-C6 has a **built-in USB-Serial-JTAG** peripheral wired to the
native USB pins (D+/D- on GPIO12/GPIO13). That means the chip can be
debugged with nothing but a USB cable — no ESP-Prog, no FTDI probe.

The picture is always the same three pieces:

```
   your PC                          the board
 ┌─────────┐   TCP :3333   ┌─────────┐   USB-JTAG   ┌──────────┐
 │  GDB /  │ ◄───────────► │ OpenOCD │ ◄──────────► │ ESP32-C6 │
 │  GUI    │               │ (server)│              │          │
 └─────────┘               └─────────┘              └──────────┘
```

OpenOCD talks to the chip over JTAG and exposes a GDB server on TCP port
3333. GDB (or any GUI wrapping GDB) connects to that port. Everything
below is just different front-ends over this same setup.

> **Port note.** The *native* USB port (JTAG + a CDC serial) shows up as
> `/dev/ttyACM0`. If your DevKit also has a separate UART-bridge port
> (CP210x/CH340) it shows up as `/dev/ttyUSB0` and is used only for
> flashing/monitoring. Single-USB-C DevKitC/M boards use one port for
> everything.

---

## 1. One-time environment setup

### 1.1 Toolchain

You already need the cross toolchain to build pqriscv:

```bash
# Debian/Ubuntu
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
# Arch: the prefix is riscv64-elf-*  (build with: make PREFIX=riscv64-elf ...)
```

You also need a **RISC-V-capable GDB**. Any one of these works — use
whichever is installed:

- `riscv64-unknown-elf-gdb` (handles RV32 fine)
- `riscv64-elf-gdb` (Arch)
- `riscv32-esp-elf-gdb` (ships with the Espressif tools)

Check:

```bash
riscv64-unknown-elf-gdb --version
```

### 1.2 OpenOCD (Espressif fork)

Mainline OpenOCD does **not** ship the `esp32c6-builtin.cfg` board file.
Use `openocd-esp32`. Easiest options:

- Install the ESP-IDF tools (they include `openocd-esp32`), **or**
- Download a standalone `openocd-esp32` release and put its `bin/` on your
  `PATH`.

On Linux, add the udev rules once so you can access the JTAG without root:

```bash
# from the openocd-esp32 distribution
sudo cp share/openocd/contrib/60-openocd.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger
```

Sanity check — plug the board into the native USB port and run:

```bash
openocd -f board/esp32c6-builtin.cfg
```

You should see the tap detected, e.g.:

```
Info : JTAG tap: esp32c6.cpu tap/device found: 0x0000dc25 (mfg: 0x612 (Espressif Systems), part: 0x000d ...)
Info : [esp32c6] datacount=2 progbufsize=16
Info : Listening on port 3333 for gdb connections
```

The line `Memory protection is enabled. Reset target to disable it...` is
normal. Leave this terminal running; Ctrl-C to stop.

### 1.3 Build with debug symbols

You debug against the **ELF**, even though you flash a `.bin`. The ELF just
needs debug info. Add `-g` to the compiler flags in `mk/config.mk`. At
`-O2` this changes nothing about the generated code — it only adds symbols
(line stepping gets a bit jumpy under optimization; drop that one build to
`-Og` if you are chasing a specific bug and want cleaner stepping).

Build and flash a scheme, then locate its ELF:

```bash
make PLATFORM=esp32c6 SCHEME=ml-dsa-44 bin-test
make PLATFORM=esp32c6 SCHEME=ml-dsa-44 flash-test FLASH_PORT=/dev/ttyUSB0
find build -name '*.elf'          # note the path; call it $ELF below
```

Export it so the commands below are copy-pasteable:

```bash
export ELF=$(find build -path '*ml-dsa-44*' -name '*.elf' | head -n1)
```

---

## 2. Debugging

### 2.1 Command line (start here)

Terminal 1 — the OpenOCD server:

```bash
openocd -f board/esp32c6-builtin.cfg
```

Terminal 2 — GDB:

```bash
riscv64-unknown-elf-gdb "$ELF"
(gdb) target extended-remote :3333
(gdb) monitor reset halt
(gdb) hbreak hal_setup        # <-- note: hbreak, not break (see below)
(gdb) continue
```

Once you hit the breakpoint, the usual commands work:

| Command                | What it does                              |
| ---------------------- | ----------------------------------------- |
| `next` / `step`        | step over / into                          |
| `finish`               | run until the current function returns    |
| `bt`                   | backtrace                                 |
| `info registers`       | dump all registers                        |
| `p variable`           | print a variable                          |
| `x/16xw &buf`          | examine 16 words of memory at `&buf`      |
| `hbreak file.c:123`    | hardware breakpoint at a line             |
| `watch var`            | break when `var` changes                  |
| `continue` / `c`       | resume                                    |

> **Why `hbreak` and not `break`?** The firmware runs execute-in-place
> (XIP) from flash (mapped around `0x4200_0000`). A plain software
> breakpoint tries to patch the instruction in memory, which does not work
> for flash. Use **hardware breakpoints** (`hbreak`). The C6 has **4**
> hardware trigger units, so up to ~4 `hbreak`/`watch` active at once —
> plan around that limit.

Useful breakpoints for this codebase:

- `hbreak hal_setup` — verify the watchdogs get disabled before a long run.
- `hbreak crypto_kem_keypair` / `crypto_kem_enc` / `crypto_kem_dec`
- `hbreak crypto_sign` / `crypto_sign_open`
- A breakpoint inside the NTT (`fastntt_rv` / the assembly entry) if you
  are debugging the arithmetic.

### 2.2 GUI option A — VS Code

Install the Microsoft **C/C++** extension. Do **not** use the ESP-IDF
extension (it assumes an `idf.py` project and fights the Makefile), and do
not use Cortex-Debug (ARM-only). Create `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug pqriscv (C6)",
      "type": "cppdbg",
      "request": "launch",
      "program": "${workspaceFolder}/build/REPLACE/WITH/test.elf",
      "cwd": "${workspaceFolder}",
      "MIMode": "gdb",
      "miDebuggerPath": "/usr/bin/riscv64-unknown-elf-gdb",
      "miDebuggerServerAddress": "localhost:3333",
      "debugServerPath": "openocd",
      "debugServerArgs": "-f board/esp32c6-builtin.cfg",
      "filterStderr": true,
      "serverStarted": "Listening on port 3333",
      "postRemoteConnectCommands": [
        { "text": "monitor reset halt" },
        { "text": "hbreak hal_setup" }
      ]
    }
  ]
}
```

Set `program` to the ELF path you found in step 1.3. VS Code launches
OpenOCD for you, waits for the "Listening on port 3333" line, attaches, and
resets — one press of **F5**. You get source view, breakpoints in the
gutter, a variables/watch panel, and a register view.

### 2.3 GUI option B — gdbgui (lightweight, browser-based)

No editor, no Electron — a web front-end over plain GDB:

```bash
pipx install gdbgui
# terminal 1:
openocd -f board/esp32c6-builtin.cfg
# terminal 2:
gdbgui --gdb-cmd "riscv64-unknown-elf-gdb $ELF"
```

In the gdbgui console, run `target extended-remote :3333` then
`monitor reset halt`. You get source, breakpoints, registers, and memory
panes in the browser.

### 2.4 Troubleshooting

| Symptom                                    | Likely cause / fix                                                        |
| ------------------------------------------ | ------------------------------------------------------------------------- |
| OpenOCD can't find the board               | Wrong USB port (use the native USB), or udev rules not installed          |
| `JTAG tap ... found` but GDB won't attach  | Another OpenOCD/monitor already holds the port — close it                 |
| Breakpoint never hit                       | You used `break` in flash — switch to `hbreak`                            |
| "all registers are 0" warning              | Harmless on a freshly-reset C6; proceed                                    |
| Target keeps resetting mid-run             | Watchdog firing — make sure `hal_setup()` runs first                      |
| DTR/DIR sync errors while running          | App is reconfiguring GPIO12/13 (the JTAG pins) — don't touch those        |

---

## 3. Profiling

Three complementary methods, from most-precise/most-manual to
least-intrusive. For a benchmarking framework, **method 1 is the workhorse**
and gives you numbers you can put in a table; method 2 tells you *where* to
point method 1.

### 3.1 Method 1 — cycle counting via the HAL (precise, deterministic)

pqriscv already exposes a cycle counter. On the ESP32-C6 the standard
`mcycle` CSR is not implemented, so the HAL uses Espressif's custom
performance-counter CSRs; `hal_get_time()` returns the tick/cycle count.
The `bench_kem` / `bench_sign` harnesses already report min/max/avg for a
whole operation.

**Profiling = breaking one operation into phases.** Wrap the regions you
care about with the same counter:

```c
#include "hal.h"

uint64_t t0 = hal_get_time();
/* ---- region under test, e.g. the NTT ---- */
poly_ntt(&a);
uint64_t t1 = hal_get_time();

/* the perf counter is 32-bit, so take the delta in 32-bit */
uint32_t cycles = (uint32_t)(t1 - t0);
/* print with the same helper bench_*.c uses to format numbers over UART */
```

Suggested breakdown for ML-KEM (`ml-kem-768`), per operation:

- SHAKE/Keccak (symmetric layer)
- NTT / inverse-NTT (compare C vs the `-DKYBER_ASM_NTT` Plantard assembly)
- sampling (rejection sampling, CBD)
- everything else

Read the numbers back over UART with `./scripts/monitor.sh /dev/ttyUSB0`.

**Watch out for counter wraparound:** the counter is 32-bit. A full ML-DSA
signing run at the benchmark clock can approach or exceed 2^32 cycles, so
measure *phases* (short regions), not the whole op, when using this method,
or the delta will wrap.

### 3.2 Method 2 — statistical PC sampling → gprof (non-intrusive)

This needs **no code changes**. OpenOCD samples the program counter while
the code runs and writes a `gmon.out` you read with `gprof`. Because the C6
is single-core RISC-V, this is clean here.

First find the flash text address range so you can bound the sampling
(sampling only the code region gives a much cleaner histogram):

```bash
riscv64-unknown-elf-objdump -h "$ELF" | grep -E '\.text|\.iram|flash'
```

Then, with the program running, in the **OpenOCD console** (you can open a
telnet console on port 4444, or issue it as a `monitor` command from GDB):

```
# profile <seconds> <outfile> [start end]
profile 10 gmon.out 0x42000000 0x42200000
```

Adjust the `start end` range to the `.text`/instruction-flash addresses you
found above. OpenOCD halts/resumes as fast as it can for 10 seconds and
records where the PC was. Then on the host:

```bash
riscv64-unknown-elf-gprof "$ELF" gmon.out > profile.txt
less profile.txt
```

The flat profile shows the percentage of samples per function — i.e. the
hot functions. Caveats to explain in your report: it is *statistical* (more
seconds = better resolution), and it is mildly intrusive because it relies
on halt/resume, so treat it as "where to look", then confirm exact costs
with method 1.

### 3.3 Method 3 — peak stack usage

Stack is often the binding constraint for PQC on embedded targets, so
measuring it is part of benchmarking. The HAL already exposes
`hal_get_stack_size()`. The classic approach:

1. At startup, paint the stack region with a known sentinel pattern
   (e.g. `0xAAAAAAAA`).
2. Run one full operation.
3. Walk the stack from the top and find the last word still holding the
   sentinel — the distance to the stack top is the high-water mark.

Report peak stack per scheme and per operation (keypair / enc / dec, or
sign / verify). This is a good, self-contained deliverable.

### 3.4 What *not* to bother with

Classic `gcc -pg` instrumentation (compiler-inserted `mcount`) is
impractical bare-metal: it needs an `mcount` implementation and a way to
dump `gmon.out` off the chip (no filesystem). Use method 2 instead — it
gives you a `gmon.out` for the same `gprof` workflow without touching the
build.

---

## 4. Suggested milestones

A reasonable progression for the project:

1. **Setup (week 1).** Get OpenOCD talking to the board; hit a breakpoint
   in `hal_setup`; step into `crypto_sign`. Deliverable: a short screencast
   or log showing a live breakpoint.
2. **Debug workflow (week 2).** Get either VS Code or gdbgui working
   end-to-end. Deliverable: the committed `.vscode/launch.json` (or a
   `make debug` target) plus notes.
3. **Cycle breakdown (weeks 3–4).** Instrument one KEM and one signature
   scheme; produce a phase-by-phase cycle table (hashing / NTT / sampling /
   rest). Deliverable: a table + short analysis.
4. **Statistical profile (week 5).** Produce a `gprof` flat profile for one
   scheme; cross-check the top functions against the method-1 numbers.
   Deliverable: `profile.txt` + a paragraph reconciling the two methods.
5. **Stack (week 6).** Peak-stack measurement across all schemes.
   Deliverable: a stack-usage table.
6. **Write-up.** Combine into a short report: methodology, tables, and one
   optimization idea the profile suggests (e.g. C vs. assembly NTT).

---

## 5. References

- pqriscv README and `README-ESP32.md` (boot flow, watchdogs, perf-counter
  CSRs).
- ESP-IDF *JTAG Debugging* guide for ESP32-C6 (built-in USB-JTAG,
  `board/esp32c6-builtin.cfg`, udev rules).
- OpenOCD *General Commands* — the `profile` command.
- `gprof` manual (flat profile & call graph).
