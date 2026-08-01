#!/usr/bin/env python3
"""
Verify existing binary patches and find all remaining "openwrt" references.
Determine the actual from_file logic.
"""
import struct

data = open(r"d:\code03\uugamebooster-docker\bin\uuplugin", "rb").read()

# ═══════════════════════════════════════════════════════════════
# 1. Check existing patches
# ═══════════════════════════════════════════════════════════════

print("=" * 70)
print("  EXISTING PATCH VERIFICATION")
print("=" * 70)

# Create a copy to simulate patches
import copy
patched = bytearray(data)

# Patches from Dockerfile:
patches = [
    (4089051, b'h3cnx30', "openwrt → h3cnx30"),
    (4106351, b'NX30Pro', "OpenWrt → NX30Pro"),
    (4091231, b'h3cnx30-aarch64', "x86_64 → aarch64"),
    (4095722, b'XX_SN', "UU_SN → XX_SN"),
]

for off, new_val, desc in patches:
    old_val = data[off:off+len(new_val)]
    patched[off:off+len(new_val)] = new_val
    printable = old_val.decode(errors='replace')
    print(f"  Offset 0x{off:06x} ({off}): [{desc}]")
    print(f"    Original: {old_val.hex()} = '{printable}'")
    print(f"    Patched:  {new_val.hex()} = '{new_val.decode()}'")
    # Show context
    ctx = data[max(0,off-20):off+len(new_val)+20]
    ctx_p = ''.join(chr(b) if 32<=b<127 else '.' for b in ctx)
    print(f"    Context: ...{ctx_p}...")

# ═══════════════════════════════════════════════════════════════
# 2. Find ALL occurrences of "openwrt" (any case) in binary
# ═══════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  ALL 'openwrt' OCCURRENCES (before patch)")
print("=" * 70)

for target in [b'openwrt', b'OpenWrt', b'OPENWRT']:
    idx = 0
    count = 0
    occ = []
    while True:
        idx = data.find(target, idx)
        if idx == -1: break
        occ.append(idx)
        idx += 1
    
    if occ:
        print(f"\n  [{target.decode()}] {len(occ)} occurrences:")
        for off in occ:
            ctx = data[max(0,off-30):off+len(target)+30]
            ctx_p = ''.join(chr(b) if 32<=b<127 else '.' for b in ctx)
            # Check if this offset is covered by existing patches
            covered = "PATCHED" if any(p[0] <= off <= p[0]+len(p[1]) for p in patches) else "NOT PATCHED"
            print(f"    0x{off:08x} [{covered:12s}]: ...{ctx_p}...")
    else:
        print(f"\n  [{target.decode()}] NOT FOUND")

# ═══════════════════════════════════════════════════════════════
# 3. Find ALL occurrences of "h3c" (any case) in binary
# ═══════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  ALL 'h3c' / 'Nx30' OCCURRENCES")
print("=" * 70)

for target in [b'h3c', b'H3C', b'nx30', b'NX30', b'Nx30']:
    idx = 0
    count = 0
    while True:
        idx = data.find(target, idx)
        if idx == -1: break
        if count < 3:
            ctx = data[max(0,idx-30):idx+len(target)+30]
            ctx_p = ''.join(chr(b) if 32<=b<127 else '.' for b in ctx)
            print(f"  [{target.decode()}] 0x{idx:08x}: ...{ctx_p}...")
        count += 1
        idx += 1
    if count > 3:
        print(f"    ... and {count-3} more")
    elif count == 0:
        print(f"  [{target.decode()}] NOT FOUND")

# ═══════════════════════════════════════════════════════════════
# 4. Find ALL "x86_64" occurrences  
# ═══════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  ALL 'x86_64' / 'x86' OCCURRENCES")
print("=" * 70)

for target in [b'x86_64', b'x86-64', b'x86']:
    idx = 0
    count = 0
    while True:
        idx = data.find(target, idx)
        if idx == -1: break
        if count < 5:
            ctx = data[max(0,idx-20):idx+len(target)+20]
            ctx_p = ''.join(chr(b) if 32<=b<127 else '.' for b in ctx)
            # Check whether in .rodata
            is_rodata = 0x3e3000 <= idx < 0x3e3000 + 0xa7bb0
            print(f"  [{target.decode()}] 0x{idx:08x} ({'rodata' if is_rodata else 'code/data'}): ...{ctx_p}...")
        count += 1
        idx += 1
    if count == 0:
        print(f"  [{target.decode()}] NOT FOUND")
    else:
        print(f"    Total: {count}")

# ═══════════════════════════════════════════════════════════════
# 5. Find the XOR obfuscation key
# ═══════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  XOR OBFUSCATION KEY ANALYSIS")
print("=" * 70)

# The strings appear obfuscated. Look at the pattern near known strings:
# "/P|{{rp" appears before obfuscated paths
# The known plaintext "openwrt-x86_64" is at 0x3e6d5f
# Let's look at the bytes around it and the obfuscated parts

# Extract the obfuscated path structure
# Pattern: /P|{{rp"-<obfuscated>-2!/ or similar
struct_start = data.find(b'/P|{{rp"')
print(f"\n  '/P|{{rp\"' first at: 0x{struct_start:08x}")

# Look at the full string table for patterns
# The string format seems to be:
# /P|{{rp"<flags><type>-2!/  = a path prefix
# The actual paths are separated by 0x00 or 0x2E ('.')

# Let me decode a known pattern
# Looking at 0x3e6d5f area:
ctx = data[0x3e6d30:0x3e6da0]
print(f"\n  Surrounding context at 0x3e6d30:")
for i in range(0, len(ctx), 32):
    chunk = ctx[i:i+32]
    hex_str = ' '.join(f'{b:02x}' for b in chunk)
    ascii_str = ''.join(chr(b) if 32<=b<127 else '.' for b in chunk)
    print(f"    0x{0x3e6d30+i:08x}: {hex_str:96s} {ascii_str}")

# Look for the deobfuscation function
# The pattern "-2!/" appears to end obfuscated strings
# "2!" = 0x32 0x21 = "2!"
# This might be part of a marker

# Try XOR with different keys to find the obfuscation
# Looking at the path prefix pattern:
# "P|{{rp" (50 7c 7b 7b 72 70) appears before obfuscated paths
# Maybe "P|{{rp" is itself obfuscated?

# Try: what if we XOR "P|{{rp" with "/usr/s" or "/opt/"?
prefix = b'P|{{rp'
try_prefixes = [b'/usr/', b'/var/', b'/etc/', b'/opt/', b'/tmp/', b'usr/sb', b'var/tm']
for tp in try_prefixes:
    key = bytes([prefix[i] ^ tp[i % len(tp)] for i in range(len(prefix))])
    print(f"\n  If 'P|{{rp' = '{tp.decode()}': key = {key.hex()} (len={len(key)})")
    
    # Try decoding next few bytes with this key
    next_bytes = data[struct_start+len(prefix):struct_start+len(prefix)+30]
    decoded = bytes([next_bytes[i] ^ key[i % len(key)] for i in range(len(next_bytes))])
    decoded_p = ''.join(chr(b) if 32<=b<127 else '.' for b in decoded)
    print(f"    Next 30 bytes decoded: {decoded_p}")

# ═══════════════════════════════════════════════════════════════
# 6. Check what the current binary ACTUALLY contains
# ═══════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  SUMMARY: WHAT NEEDS TO BE PATCHED")
print("=" * 70)

# Check if any openwrt references are NOT covered by existing patches
print("\n  Unpatched 'openwrt' references:")
for target in [b'openwrt', b'OpenWrt']:
    idx = 0
    while True:
        idx = data.find(target, idx)
        if idx == -1: break
        covered = any(p[0] <= idx <= p[0]+len(p[1]) for p in patches)
        if not covered:
            ctx = data[max(0,idx-20):idx+len(target)+20]
            ctx_p = ''.join(chr(b) if 32<=b<127 else '.' for b in ctx)
            print(f"    0x{idx:08x}: ...{ctx_p}...")
        idx += 1

print("\n" + "=" * 70)
print("  PATCH PLAN")
print("=" * 70)
