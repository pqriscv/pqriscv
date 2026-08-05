#!/usr/bin/env python3
"""
scripts/gen_test_vectors.py
Generate Known-Answer Test vectors for every primitive in common/.
Run with --update to rewrite test/test_primitives.c in place.

Usage:
    python3 scripts/gen_test_vectors.py            # print vectors
    python3 scripts/gen_test_vectors.py --update   # rewrite test file
"""

import hashlib, sys, os, argparse, textwrap

# ── AES (pycryptodome) ──────────────────────────────────────────────────────
try:
    from Crypto.Cipher import AES as _AES
    def aes256_ecb(key, pt):
        return _AES.new(key, _AES.MODE_ECB).encrypt(pt)
except ImportError:
    sys.exit("pycryptodome required:  pip install pycryptodome")

# ── NIST AES-256-CTR DRBG  (mirrors common/nistrng.c exactly) ──────────────
def _drbg_update(key, V, provided):
    tmp = b""
    for _ in range(3):
        V = (int.from_bytes(V, "big") + 1).to_bytes(16, "big")
        tmp += aes256_ecb(key, V)
    if provided:
        tmp = bytes(a ^ b for a, b in zip(tmp, provided))
    return tmp[:32], tmp[32:48]

class NistDrbg:
    def __init__(self, seed48):
        assert len(seed48) == 48
        self.key = b"\x00" * 32
        self.V   = b"\x00" * 16
        self.key, self.V = _drbg_update(self.key, self.V, seed48)

    def generate(self, n):
        out = b""
        while len(out) < n:
            self.V = (int.from_bytes(self.V, "big") + 1).to_bytes(16, "big")
            out += aes256_ecb(self.key, self.V)
        self.key, self.V = _drbg_update(self.key, self.V, None)
        return out[:n]

# ── Helpers ─────────────────────────────────────────────────────────────────
def chunks(s, n=32):
    return [s[i:i+n] for i in range(0, len(s), n)]

def c_hex(data, indent=10):
    """Format bytes as one or more C string literals, 16 bytes per line."""
    hex_str = data.hex()
    parts = chunks(hex_str, 32)
    pad = " " * indent
    lines = [f'"{parts[0]}"']
    for p in parts[1:]:
        lines.append(f'{pad}"{p}"')
    return "\n".join(lines)

# ── Vector computation ───────────────────────────────────────────────────────
def all_vectors():
    seed_a = bytes(range(48))
    seed_b = bytes(b ^ 0xff for b in range(48))
    d = NistDrbg(seed_a)
    drbg_a1 = d.generate(32)
    drbg_a2 = d.generate(32)
    drbg_a3 = NistDrbg(seed_a).generate(32)   # re-seed: must == drbg_a1
    drbg_b1 = NistDrbg(seed_b).generate(32)

    key1 = bytes(range(32))
    pt1  = bytes([0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
                  0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff])

    return dict(
        sha3_256_empty   = hashlib.sha3_256(b"").digest(),
        sha3_256_abc     = hashlib.sha3_256(b"abc").digest(),
        sha3_256_200xa3  = hashlib.sha3_256(bytes([0xa3]*200)).digest(),
        sha3_512_empty   = hashlib.sha3_512(b"").digest(),
        sha3_512_abc     = hashlib.sha3_512(b"abc").digest(),
        shake128_empty32 = hashlib.shake_128(b"").digest(32),
        shake128_abc32   = hashlib.shake_128(b"abc").digest(32),
        shake128_empty64 = hashlib.shake_128(b"").digest(64),
        shake256_empty32 = hashlib.shake_256(b"").digest(32),
        shake256_abc32   = hashlib.shake_256(b"abc").digest(32),
        sha256_empty     = hashlib.sha256(b"").digest(),
        sha256_abc       = hashlib.sha256(b"abc").digest(),
        sha256_448bit    = hashlib.sha256(
            b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").digest(),
        sha512_abc       = hashlib.sha512(b"abc").digest(),
        sha512_448bit    = hashlib.sha512(
            b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").digest(),
        aes256_fips197   = aes256_ecb(key1, pt1),
        aes256_zero      = aes256_ecb(bytes(32), bytes(16)),
        drbg_a_first     = drbg_a1,
        drbg_a_second    = drbg_a2,
        drbg_a_reseed    = drbg_a3,
        drbg_b_first     = drbg_b1,
    )

# ── Print summary ────────────────────────────────────────────────────────────
def print_summary(v):
    print("=" * 64)
    print("Known-Answer Vectors  (Python hashlib + pycryptodome)")
    print("=" * 64)
    for k, val in v.items():
        print(f"  {k:<20} = {val.hex()}")

# ── Generate C source ────────────────────────────────────────────────────────
def generate_c(v):
    I = "          "  # indent for continuation hex strings

    def chk(label, data, var="h"):
        return (f'    check("{label}",\n'
                f'          {var}, {c_hex(data, len("          "))}, {len(data)});')

    lines = []
    w = lines.append

    w("""\
/*
 * test/test_primitives.c — Known-Answer Tests for all symmetric primitives
 *
 * ALL VECTORS ARE MACHINE-GENERATED — do not edit by hand.
 * Re-generate with:
 *   python3 scripts/gen_test_vectors.py --update
 *
 * Sources:
 *   SHA-3 / SHAKE  : Python hashlib        (FIPS 202)
 *   SHA-256/512    : Python hashlib        (FIPS 180-4)
 *   AES-256        : pycryptodome          (FIPS 197)
 *   NIST DRBG      : Python reference impl (SP 800-90A)
 */

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>

#include "hal.h"
#include "fips202.h"
#include "sha2.h"
#include "aes.h"
#include "nistrng.h"

/* -------------------------------------------------------------------------
 * Helpers
 * ------------------------------------------------------------------------- */
static char _buf[256];
static void pf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(_buf, sizeof(_buf), fmt, ap);
    va_end(ap);
    hal_send_str(_buf);
}

static int total_pass = 0;
static int total_fail = 0;

static void unhex(uint8_t *out, const char *hex, size_t nbytes)
{
    size_t i;
    for (i = 0; i < nbytes; i++) {
        unsigned int hi = (hex[2*i  ] >= 'a') ? (hex[2*i  ] - 'a' + 10) : (hex[2*i  ] - '0');
        unsigned int lo = (hex[2*i+1] >= 'a') ? (hex[2*i+1] - 'a' + 10) : (hex[2*i+1] - '0');
        out[i] = (uint8_t)((hi << 4) | lo);
    }
}

static void check(const char *label,
                  const uint8_t *got, const char *expected_hex,
                  size_t nbytes)
{
    uint8_t expected[128];
    size_t i;
    unhex(expected, expected_hex, nbytes);
    if (memcmp(got, expected, nbytes) == 0) {
        pf("  PASS  %s", label);
        total_pass++;
    } else {
        for (i = 0; i < nbytes; i++) {
            if (got[i] != expected[i]) {
                pf("  FAIL  %s  [byte %u: got %02x want %02x]",
                   label, (unsigned)i, got[i], expected[i]);
                break;
            }
        }
        total_fail++;
    }
}
""")

    # SHA3-256
    w("/* --------------------------------------------------------------------- */\n"
      "static void test_sha3_256(void)\n{\n"
      "    uint8_t h[32];\n"
      '    hal_send_str("SHA3-256:");\n')
    w('    sha3_256(h, (const uint8_t *)"", 0);')
    w(chk('SHA3-256(empty)', v['sha3_256_empty']))
    w('    sha3_256(h, (const uint8_t *)"abc", 3);')
    w(chk('SHA3-256(abc)  ', v['sha3_256_abc']))
    w('    { uint8_t msg[200]; memset(msg, 0xa3, 200); sha3_256(h, msg, 200); }')
    w(chk('SHA3-256(200*0xa3)', v['sha3_256_200xa3']))
    w("}\n")

    # SHA3-512
    w("static void test_sha3_512(void)\n{\n"
      "    uint8_t h[64];\n"
      '    hal_send_str("SHA3-512:");\n')
    w('    sha3_512(h, (const uint8_t *)"", 0);')
    w(chk('SHA3-512(empty)', v['sha3_512_empty']))
    w('    sha3_512(h, (const uint8_t *)"abc", 3);')
    w(chk('SHA3-512(abc)  ', v['sha3_512_abc']))
    w("}\n")

    # SHAKE-128
    w("static void test_shake128(void)\n{\n"
      "    uint8_t out[64];\n"
      '    hal_send_str("SHAKE-128:");\n')
    w('    shake128(out, 32, (const uint8_t *)"", 0);')
    w(chk('SHAKE128(empty,32)', v['shake128_empty32'], "out"))
    w('    shake128(out, 32, (const uint8_t *)"abc", 3);')
    w(chk('SHAKE128(abc,32)  ', v['shake128_abc32'], "out"))
    w('    shake128(out, 64, (const uint8_t *)"", 0);')
    w(chk('SHAKE128(empty,64)', v['shake128_empty64'], "out"))
    w("""\
    /* Incremental API must match one-shot */
    {
        keccak_state st;
        uint8_t inc[32];
        shake128_init(&st);
        shake128_absorb(&st, (const uint8_t *)"abc", 3);
        shake128_finalize(&st);
        shake128_squeeze(inc, 32, &st);
        shake128(out, 32, (const uint8_t *)"abc", 3);
        if (memcmp(out, inc, 32) == 0) {
            hal_send_str("  PASS  SHAKE128 incremental == one-shot");
            total_pass++;
        } else {
            hal_send_str("  FAIL  SHAKE128 incremental != one-shot");
            total_fail++;
        }
    }""")
    w("}\n")

    # SHAKE-256
    w("static void test_shake256(void)\n{\n"
      "    uint8_t out[32];\n"
      '    hal_send_str("SHAKE-256:");\n')
    w('    shake256(out, 32, (const uint8_t *)"", 0);')
    w(chk('SHAKE256(empty,32)', v['shake256_empty32'], "out"))
    w('    shake256(out, 32, (const uint8_t *)"abc", 3);')
    w(chk('SHAKE256(abc,32)  ', v['shake256_abc32'], "out"))
    w("""\
    {
        keccak_state st;
        uint8_t inc[32];
        shake256_init(&st);
        shake256_absorb(&st, (const uint8_t *)"abc", 3);
        shake256_finalize(&st);
        shake256_squeeze(inc, 32, &st);
        shake256(out, 32, (const uint8_t *)"abc", 3);
        if (memcmp(out, inc, 32) == 0) {
            hal_send_str("  PASS  SHAKE256 incremental == one-shot");
            total_pass++;
        } else {
            hal_send_str("  FAIL  SHAKE256 incremental != one-shot");
            total_fail++;
        }
    }""")
    w("}\n")

    # SHA-256
    w("static void test_sha256(void)\n{\n"
      "    uint8_t h[32];\n"
      '    hal_send_str("SHA-256:");\n')
    w('    sha256(h, (const uint8_t *)"", 0);')
    w(chk('SHA256(empty)  ', v['sha256_empty']))
    w('    sha256(h, (const uint8_t *)"abc", 3);')
    w(chk('SHA256(abc)    ', v['sha256_abc']))
    w('    sha256(h, (const uint8_t *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56);')
    w(chk('SHA256(448-bit)', v['sha256_448bit']))
    w("""\
    /* Incremental must match one-shot */
    {
        sha256_ctx ctx;
        uint8_t inc[32];
        sha256_init(&ctx);
        sha256_update(&ctx, (const uint8_t *)"abc", 3);
        sha256_final(&ctx, inc);
        sha256(h, (const uint8_t *)"abc", 3);
        if (memcmp(h, inc, 32) == 0) {
            hal_send_str("  PASS  SHA256 incremental == one-shot");
            total_pass++;
        } else {
            hal_send_str("  FAIL  SHA256 incremental != one-shot");
            total_fail++;
        }
    }""")
    w("}\n")

    # SHA-512
    w("static void test_sha512(void)\n{\n"
      "    uint8_t h[64];\n"
      '    hal_send_str("SHA-512:");\n')
    w('    sha512(h, (const uint8_t *)"abc", 3);')
    w(chk('SHA512(abc)    ', v['sha512_abc']))
    w('    sha512(h, (const uint8_t *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56);')
    w(chk('SHA512(448-bit)', v['sha512_448bit']))
    w("}\n")

    # AES-256
    key1 = bytes(range(32))
    pt1  = bytes([0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
                  0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff])
    key1_c = ", ".join(f"0x{b:02x}" for b in key1)
    pt1_c  = ", ".join(f"0x{b:02x}" for b in pt1)
    key2_c = ", ".join(["0x00"] * 32)
    pt2_c  = ", ".join(["0x00"] * 16)
    w("static void test_aes256(void)\n{\n"
      '    hal_send_str("AES-256 ECB:");\n')
    w(f"""\
    {{
        static const uint8_t key[32] = {{ {key1_c} }};
        static const uint8_t pt [16] = {{ {pt1_c} }};
        uint8_t ct[16];
        aes256_ecb(ct, key, pt);
        {chk("AES-256 FIPS197-C3 ", v['aes256_fips197'], "ct").lstrip()}
    }}
    {{
        static const uint8_t key[32] = {{ {key2_c} }};
        static const uint8_t pt [16] = {{ {pt2_c} }};
        uint8_t ct[16];
        aes256_ecb(ct, key, pt);
        {chk("AES-256 zero key/pt", v['aes256_zero'], "ct").lstrip()}
    }}""")
    w("}\n")

    # NIST DRBG
    w("static void test_nistrng(void)\n{\n"
      '    hal_send_str("NIST AES-CTR DRBG:");\n'
      "    uint8_t seed_a[48], seed_b[48], out[32];\n"
      "    int i;\n"
      "    for (i = 0; i < 48; i++) seed_a[i] = (uint8_t)i;\n"
      "    for (i = 0; i < 48; i++) seed_b[i] = (uint8_t)(i ^ 0xff);\n")
    w("    randombytes_init(seed_a, NULL, 256);")
    w("    randombytes_nist(out, 32);")
    w(chk("DRBG seed_a[1st]  ", v['drbg_a_first'], "out"))
    w("    randombytes_nist(out, 32);")
    w(chk("DRBG seed_a[2nd]  ", v['drbg_a_second'], "out"))
    w("    /* Re-seed: must reproduce first output */")
    w("    randombytes_init(seed_a, NULL, 256);")
    w("    randombytes_nist(out, 32);")
    w(chk("DRBG re-seed==1st ", v['drbg_a_reseed'], "out"))
    w("    randombytes_init(seed_b, NULL, 256);")
    w("    randombytes_nist(out, 32);")
    w(chk("DRBG seed_b[1st]  ", v['drbg_b_first'], "out"))
    w("}\n")

    # main
    w("""\
int main(void)
{
    hal_setup(CLOCK_BENCHMARK);
    hal_send_str("==============================");
    hal_send_str("Primitive Known-Answer Tests");
    hal_send_str("==============================");
    test_sha3_256();
    test_sha3_512();
    test_shake128();
    test_shake256();
    test_sha256();
    test_sha512();
    test_aes256();
    test_nistrng();
    hal_send_str("------------------------------");
    pf("Results: %d passed, %d failed", total_pass, total_fail);
    hal_send_str((total_fail == 0) ? "RESULT: PASS" : "RESULT: FAIL");
    hal_send_str("==============================");
    return (total_fail == 0) ? 0 : 1;
}
""")
    return "\n".join(lines)

# ── Entry point ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true",
                        help="Rewrite test/test_primitives.c in place")
    args = parser.parse_args()

    v = all_vectors()
    print_summary(v)

    c_src = generate_c(v)
    if args.update:
        dest = os.path.normpath(
            os.path.join(os.path.dirname(__file__), "..", "test", "test_primitives.c"))
        with open(dest, "w") as f:
            f.write(c_src)
        print(f"\nWrote {dest}  ({len(c_src)} bytes)")
    else:
        print("\n\nPass --update to rewrite test/test_primitives.c")
