#!/usr/bin/env python3
"""
Patch uuplugin binary for H3C NX30Pro identity + from_file=1 fix.

Usage: python3 patch_binary.py <path_to_uuplugin>

Patches:
  1a. "openwrt"    (file 0x3E64DB) → "h3cnx30"   [7 bytes, same length]
  1b. "OpenWrt"    (file 0x3EA86F) → "NX30Pro"   [7 bytes, same length]
  1c. "openwrt-x86_64\\0" (file 0x3E6D5F) → "h3c-nx30pro\\0\\0\\0" [15 bytes exact, null-terminated]
      ** FIXED from previous: printf wrote "h3cnx30-aarch64" (15 bytes, no null!)
  2.  "UU_SN"      (file 0x3E6EEA) → "XX_SN"     [5 bytes, same length]
      ** CORRECTED: previous patch at offset 4095722 (0x3E7EEA) was off by 0x1000=4096!

Why patching UU_SN → XX_SN works:
  - Binary calls getenv("UU_SN") via hardcoded string in .rodata
  - After patch, it calls getenv("XX_SN") instead
  - XX_SN env var is NOT set → getenv returns NULL
  - Binary detects NULL → uses file-based SN detection → from_file=1
  - UU_SN env var is still set (prevents crashes on other code paths)
"""
import sys
import os

PATCHES = [
    # (file_offset, new_bytes, description)
    (4089051, b'h3cnx30',                    "openwrt → h3cnx30"),
    (4106351, b'NX30Pro',                    "OpenWrt → NX30Pro"),
    (4091231, b'h3c-nx30pro\x00\x00\x00',    "openwrt-x86_64\\0 → h3c-nx30pro\\0\\0\\0"),
    (4091626, b'XX_SN',                      "UU_SN → XX_SN [CORRECTED OFFSET]"),
]

def patch_binary(path):
    if not os.path.exists(path):
        print(f"ERROR: {path} not found", file=sys.stderr)
        sys.exit(1)
    
    data = bytearray(open(path, 'rb').read())
    orig_size = len(data)
    
    print(f"[PATCH] Loading {path} ({orig_size:,} bytes)")
    
    for offset, new_bytes, desc in PATCHES:
        old_bytes = data[offset:offset + len(new_bytes)]
        if len(old_bytes) < len(new_bytes):
            print(f"  ERROR: offset {offset} exceeded file size", file=sys.stderr)
            sys.exit(1)
        
        old_str = ''.join(chr(b) if 32 <= b < 127 else f'\\x{b:02x}' for b in old_bytes)
        new_str = ''.join(chr(b) if 32 <= b < 127 else f'\\x{b:02x}' for b in new_bytes)
        
        print(f"  [{desc}]")
        print(f"    0x{offset:08x}: {old_str} → {new_str}")
        
        data[offset:offset + len(new_bytes)] = new_bytes
    
    # Verify patches
    print("\n[VERIFY] Checking patches...")
    all_ok = True
    for offset, expected, desc in PATCHES:
        actual = data[offset:offset + len(expected)]
        if actual != expected:
            print(f"  FAIL: {desc} — expected {expected}, got {actual}")
            all_ok = False
        else:
            print(f"  OK:   {desc}")
    
    if not all_ok:
        print("\nERROR: Some patches failed verification!", file=sys.stderr)
        sys.exit(1)
    
    open(path, 'wb').write(data)
    print(f"\n[OK] All {len(PATCHES)} patches applied successfully ({orig_size:,} bytes)")
    print("     Binary now identifies as H3C NX30Pro with from_file=1")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        target = r"d:\code03\uugamebooster-docker\bin\uuplugin"
    else:
        target = sys.argv[1]
    patch_binary(target)
