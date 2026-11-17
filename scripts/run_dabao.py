#!/usr/bin/env python3
"""scripts/run_dabao.py — flash a pqriscv image to a Dabao, run it, capture the result.

Usage (normally through make, see mk/dabao.mk):
    run_dabao.py build/ml-dsa-44/bench.uf2 --uart /dev/ttyUSB0 --log build/ml-dsa-44/bench.log

Steps:
  1. wait for boot1's mass-storage drive (label BAOCHIP)
  2. open the UART adapter on PB14
  3. copy the .uf2 onto the drive and sync
  4. start it: send `boot` to boot1's USB serial console (USB 1d50:6196);
     if that console cannot be found, ask for a PROG press instead
  5. echo the UART output until [PASS], [FAIL] or !TRAP, and save it

Exit status: 0 PASS, 1 FAIL or trap, 2 timeout / setup error.

With DABAO_RESET_ON_EXIT=1 (the default) the image resets into boot1 after
printing its result, so the drive comes back by itself for the next run.

Needs pyserial (pip install pyserial / python3-serial), as scripts/monitor.sh.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    sys.exit("run_dabao: pyserial is missing (pip install pyserial or python3-serial)")

LABEL = "BAOCHIP"
BOOT1_VID, BOOT1_PID = 0x1D50, 0x6196
DONE = ("[PASS]", "[FAIL]", "!TRAP")


def log(msg):
    print(f"[run_dabao] {msg}", flush=True)


def _findmnt():
    try:
        out = subprocess.run(["findmnt", "-rn", "-S", f"LABEL={LABEL}", "-o", "TARGET"],
                             capture_output=True, text=True).stdout
    except FileNotFoundError:
        return ""
    return out.split("\n")[0].strip().replace("\\x20", " ")


def find_mount():
    m = _findmnt()
    dev = f"/dev/disk/by-label/{LABEL}"
    if not m and os.path.exists(dev) and shutil.which("udisksctl"):
        subprocess.run(["udisksctl", "mount", "-b", dev], capture_output=True)
        m = _findmnt()
    return m


def wait_mount(fixed, timeout):
    if fixed:
        if not os.path.isdir(fixed):
            sys.exit(f"run_dabao: {fixed} is not a directory")
        return fixed
    t0, asked = time.time(), False
    while time.time() - t0 < timeout:
        m = find_mount()
        if m and os.path.isdir(m):
            return m
        if not asked and time.time() - t0 > 5:
            log(f"waiting for the {LABEL} drive — press RESET on the board "
                "(hold PROG while pressing it if bootwait is disabled)")
            asked = True
        time.sleep(0.5)
    log(f"no {LABEL} drive after {timeout:.0f} s")
    sys.exit(2)


def find_boot1_port(fixed):
    if fixed:
        return fixed
    for p in serial.tools.list_ports.comports():
        if p.vid == BOOT1_VID and p.pid == BOOT1_PID:
            return p.device
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("uf2")
    ap.add_argument("--uart", default="/dev/ttyUSB0", help="USB-UART adapter wired to PB14")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--mount", help="mount point of the BAOCHIP drive (default: by label)")
    ap.add_argument("--boot-port", help="boot1 USB console (default: USB 1d50:6196)")
    ap.add_argument("--log", help="write the captured UART output here")
    ap.add_argument("--timeout", type=float, default=1800, help="seconds to wait for a result")
    ap.add_argument("--drive-timeout", type=float, default=120)
    a = ap.parse_args()

    if not os.path.isfile(a.uf2):
        sys.exit(f"run_dabao: {a.uf2} not found")

    mnt = wait_mount(a.mount, a.drive_timeout)
    try:
        uart = serial.Serial(a.uart, a.baud, timeout=0.2)
    except serial.SerialException as e:
        sys.exit(f"run_dabao: cannot open {a.uart}: {e}")

    # the console must be found before the copy: boot1 keeps it while the drive is up
    boot_port = find_boot1_port(a.boot_port)

    log(f"{a.uf2} -> {mnt}")
    dst = os.path.join(mnt, os.path.basename(a.uf2))
    with open(a.uf2, "rb") as src, open(dst, "wb") as out:
        shutil.copyfileobj(src, out)
        out.flush()
        os.fsync(out.fileno())
    os.sync()
    time.sleep(1.0)                 # let boot1 commit the last RRAM page

    uart.reset_input_buffer()
    started = False
    if boot_port:
        try:
            con = serial.Serial(boot_port, 115200, timeout=0.5)
        except (serial.SerialException, OSError) as e:
            log(f"could not open {boot_port} ({e})")
        else:
            try:
                con.write(b"\rboot\r")
                con.flush()
            except (serial.SerialException, OSError):
                pass        # boot1 drops USB as it hands over: expected
            try:
                con.close()
            except (serial.SerialException, OSError):
                pass
            started = True
            log(f"sent 'boot' on {boot_port}")
    if not started:
        log("boot1 USB console not found — press PROG on the board now")

    captured, line, t0, status = [], b"", time.time(), 2
    while time.time() - t0 < a.timeout:
        chunk = uart.read(256)
        if not chunk:
            continue
        for b in chunk:
            if b == 0x0A:
                text = line.decode("ascii", errors="ignore").rstrip("\r")
                # boot1 talks at 1 Mbaud on the same pin: drop the noise it makes
                text = "".join(c for c in text if c.isprintable())
                line = b""
                captured.append(text)
                print(text, flush=True)
                if any(d in text for d in DONE):
                    status = 0 if "[PASS]" in text else 1
            else:
                line += bytes([b])
        if status != 2:
            break
    else:
        log(f"no [PASS]/[FAIL] within {a.timeout:.0f} s")
    uart.close()

    if a.log:
        os.makedirs(os.path.dirname(a.log) or ".", exist_ok=True)
        with open(a.log, "w") as f:
            f.write("\n".join(captured) + "\n")
        log(f"output saved to {a.log}")
    sys.exit(status)


if __name__ == "__main__":
    main()
