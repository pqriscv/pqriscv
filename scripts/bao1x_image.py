#!/usr/bin/env python3
"""scripts/bao1x_image.py — sign a bare-metal image for the Baochip-1x and
wrap it as UF2 for boot1's mass-storage loader.

Usage:
    bao1x_image.py <code.raw> <signed.bin> <image.uf2>

    code.raw    `objcopy -O binary` of the ELF: everything the linker placed
                in RRAM, starting at 0x60060300 (see common/dabao/dabao.ld)
    signed.bin  768-byte signature block + code.raw = contents of the
                baremetal slot starting at 0x60060000
    image.uf2   signed.bin in UF2 form; copy this to the BAOCHIP drive

Normally run through `make PLATFORM=dabao ... bin-test`.

No dependencies beyond the Python standard library: boot1 wants Ed25519ph
(RFC 8032, pre-hashed with SHA-512, empty context), which the usual Ed25519
tools do not offer, so a small implementation is included below.

The key is the Baochip *developer* key. It is public on purpose (xous-core
devkey/dev.key): it is how anyone gets to run their own code. An image signed
with it boots on any board whose developer key slot has not been revoked,
and makes boot1 erase the board's factory secrets the first time.

Signature block layout — struct SignatureInFlash, xous-core
libs/bao1x-api/src/signatures.rs (all integers little-endian):

    0x000    4  jal x0, 0x300        hop over this block (boot1 < 0.10.2)
    0x004   64  Ed25519ph signature
    0x044    4  aad_len = 0          selects plain Ed25519ph
    0x048   60  aad (zero)
    ---- everything from here to the end of the image is signed ----
    0x084    4  version = 0x100
    0x088    8  magic "yumy", "Bao3" (two big-endian words)
    0x090    4  signed_len = len(code) + 0x300 - 0x84
    0x094    4  function_code = 6    (Baremetal)
    0x098    4  anti_rollback = 1
    0x09c   16  min_semver (zero)
    0x0ac   16  semver (zero)
    0x0bc  144  key manifest: 4 x (32-byte Ed25519 key + 4-byte tag);
                only slot 3, the developer key, is filled in
    0x14c   20  toolchain (zero)
    0x160  416  zero (later format revisions keep post-quantum fields here;
                all-zero means "legacy record, no SLH-DSA signature")
    0x300       code
"""

import base64
import hashlib
import struct
import sys

# --------------------------------------------------------------------------
# Baochip-1x constants
# --------------------------------------------------------------------------
BAREMETAL_START = 0x60060000    # loader/baremetal slot in RRAM
SIGBLOCK_LEN = 0x300
UNSIGNED_LEN = 0x84             # jal + signature + aad_len + aad
SIG_VERSION = 0x100
SIG_MAGIC = (0x79756D79, 0x42616F33)    # "yumy", "Bao3"
FUNCTION_BAREMETAL = 6
# Checked against a one-way counter on the chip. boot1 refuses images whose
# value is lower than the counter and *advances the counter* to match higher
# ones, permanently — so never raise this without a reason. 1 is what
# xous-core signs baremetal images with (signing/anti-rollback.hjson).
ANTI_ROLLBACK = 1

UF2_FAMILY = 0xA7D76373         # BAOCHIP_1X_UF2_FAMILY
MAX_IMAGE = 0x100000            # RRAM budget in common/dabao/dabao.ld

# xous-core devkey/dev.key (PKCS#8); the Ed25519 seed is the last 32 bytes.
DEV_KEY_PKCS8 = "MC4CAQAwBQYDK2VwBCIEIKindlyNoteThisIsADevKeyDontUseForProduction"
# libs/bao1x-api/src/pubkeys/developer.rs
DEV_PUBKEY = bytes.fromhex(
    "1c9beae32aeac87507c18094387eff1c74614282affd8152d871352edf3f58bb")
DEV_TAG = b"dev "

# First word of the code: startup_dabao.S entry header, `jal x0, 0x100`
ENTRY_HEADER_WORD = 0x1000006F

# --------------------------------------------------------------------------
# Ed25519ph (RFC 8032, sections 5.1 and 6)
# --------------------------------------------------------------------------
P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P


def _point_add(a, b):
    """Extended twisted Edwards coordinates (X, Y, Z, T)."""
    A = (a[1] - a[0]) * (b[1] - b[0]) % P
    B = (a[1] + a[0]) * (b[1] + b[0]) % P
    C = 2 * a[3] * b[3] * D % P
    DD = 2 * a[2] * b[2] % P
    E, F, G, H = B - A, DD - C, DD + C, B + A
    return (E * F % P, G * H % P, F * G % P, E * H % P)


def _point_mul(s, pt):
    acc = (0, 1, 1, 0)          # neutral element
    while s > 0:
        if s & 1:
            acc = _point_add(acc, pt)
        pt = _point_add(pt, pt)
        s >>= 1
    return acc


def _point_compress(pt):
    zinv = pow(pt[2], P - 2, P)
    x, y = pt[0] * zinv % P, pt[1] * zinv % P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def _base_point():
    y = 4 * pow(5, P - 2, P) % P
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P != 0:
        x = x * pow(2, (P - 1) // 4, P) % P
    if x & 1:                   # the base point has even x
        x = P - x
    return (x, y, 1, x * y % P)


G = _base_point()


def _sha512_int(data):
    return int.from_bytes(hashlib.sha512(data).digest(), "little")


def ed25519_public_key(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little")
    a = (a & ((1 << 254) - 8)) | (1 << 254)
    return _point_compress(_point_mul(a, G))


def ed25519ph_sign(seed, message):
    """Ed25519ph signature of `message` with an empty context string."""
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little")
    a = (a & ((1 << 254) - 8)) | (1 << 254)
    prefix = h[32:]
    pub = _point_compress(_point_mul(a, G))

    # dom2(phflag = 1, context = "")
    dom2 = b"SigEd25519 no Ed25519 collisions" + bytes([1, 0])
    prehash = hashlib.sha512(message).digest()

    r = _sha512_int(dom2 + prefix + prehash) % L
    big_r = _point_compress(_point_mul(r, G))
    k = _sha512_int(dom2 + big_r + pub + prehash) % L
    s = (r + k * a) % L
    return big_r + s.to_bytes(32, "little")


# --------------------------------------------------------------------------
# Image construction
# --------------------------------------------------------------------------
def jal_x0(offset):
    """Encode `jal x0, offset`."""
    assert offset % 2 == 0 and -(1 << 20) <= offset < (1 << 20)
    imm = offset & 0x1FFFFF
    return (((imm >> 20) & 1) << 31 | ((imm >> 1) & 0x3FF) << 21
            | ((imm >> 11) & 1) << 20 | ((imm >> 12) & 0xFF) << 12 | 0x6F)


def sign_image(code):
    seed = base64.b64decode(DEV_KEY_PKCS8)[-32:]
    if ed25519_public_key(seed) != DEV_PUBKEY:
        raise SystemExit("bao1x_image: developer key self-check failed")

    signed_len = len(code) + SIGBLOCK_LEN - UNSIGNED_LEN
    sealed = struct.pack("<I", SIG_VERSION)
    sealed += struct.pack("<II", *SIG_MAGIC)
    sealed += struct.pack("<III", signed_len, FUNCTION_BAREMETAL, ANTI_ROLLBACK)
    sealed += bytes(16)                             # min_semver
    sealed += bytes(16)                             # semver
    sealed += bytes(3 * 36) + DEV_PUBKEY + DEV_TAG  # key manifest
    sealed += bytes(20)                             # toolchain
    sealed += bytes(SIGBLOCK_LEN - UNSIGNED_LEN - len(sealed))

    signature = ed25519ph_sign(seed, sealed + code)

    block = struct.pack("<I", jal_x0(SIGBLOCK_LEN)) + signature
    block += struct.pack("<I", 0) + bytes(60)       # aad_len, aad
    block += sealed
    assert len(block) == SIGBLOCK_LEN
    return block + code


def to_uf2(image, base_addr):
    """256-byte payload per 512-byte block, as xous-core's tools emit it."""
    nblocks = (len(image) + 255) // 256
    out = bytearray()
    for i in range(nblocks):
        chunk = image[256 * i:256 * (i + 1)].ljust(256, b"\0")
        out += struct.pack("<8I", 0x0A324655, 0x9E5D5157,
                           0x2000,                  # family ID present
                           base_addr + 256 * i, 256, i, nblocks, UF2_FAMILY)
        out += chunk + bytes(512 - 32 - 256 - 4)
        out += struct.pack("<I", 0x0AB16F30)
    return bytes(out)


def main(argv):
    if len(argv) != 4:
        raise SystemExit(__doc__.split("\n\n")[1])
    raw_path, bin_path, uf2_path = argv[1:]

    with open(raw_path, "rb") as f:
        code = f.read()

    # Catch a mis-linked input before it gets a valid signature.
    if len(code) < 0x104 or struct.unpack_from("<I", code)[0] != ENTRY_HEADER_WORD:
        raise SystemExit(f"bao1x_image: {raw_path} does not start with the "
                         "Dabao entry header — was it built with PLATFORM=dabao?")
    if SIGBLOCK_LEN + len(code) > MAX_IMAGE:
        raise SystemExit(f"bao1x_image: {raw_path} is too large "
                         f"({len(code)} bytes) — is a section linked outside RRAM?")

    image = sign_image(code)
    with open(bin_path, "wb") as f:
        f.write(image)
    with open(uf2_path, "wb") as f:
        f.write(to_uf2(image, BAREMETAL_START))
    print(f"  SIGN  {uf2_path}  ({len(image)} bytes @ 0x{BAREMETAL_START:08x}, "
          "developer key)")


if __name__ == "__main__":
    main(sys.argv)
