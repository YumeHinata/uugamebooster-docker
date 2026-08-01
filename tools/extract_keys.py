#!/usr/bin/env python3
"""Extract embedded keys and certificates from UU binaries."""

def find_pem_blocks(data, label):
    """Find all PEM blocks in binary data efficiently."""
    results = []
    pos = 0
    while True:
        idx = data.find(b'-----BEGIN', pos)
        if idx == -1:
            break
        # Find matching END
        end_idx = data.find(b'-----END', idx)
        if end_idx == -1:
            pos = idx + 10
            continue
        # Find end of line after END
        eol = data.find(b'-----', end_idx + 10)
        if eol == -1:
            pos = idx + 10
            continue
        block = data[idx:eol+5]
        results.append((idx, block))
        pos = eol + 5
    
    print(f"\n{'='*60}")
    print(f"  {label}")
    print(f"{'='*60}")
    
    if not results:
        print("  (no PEM blocks found)")
        return results
    
    for offset, block in results:
        try:
            text = block.decode('ascii')
            # Get the type line
            first_line = text.split('\n')[0]
            print(f"\n  Offset 0x{offset:08x}: {first_line}")
            print(f"  Length: {len(block)} bytes")
            if len(text) < 500:
                print(text)
        except:
            print(f"  Offset 0x{offset:08x}: [binary data, {len(block)} bytes]")
    
    return results

def find_protobuf_schemas(data, label):
    """Extract protobuf message/field names from binary."""
    import re
    # Try to find .proto-style message names
    # These appear as concatenated namess in the binary (no null terminators between)
    
    # Search for common proto package names
    packages = set()
    for pattern in [b'uu_router_messages', b'uu_', b'h3c_', b'router_']:
        pos = 0
        while True:
            idx = data.find(pattern, pos)
            if idx == -1:
                break
            # Extract up to 200 bytes of context
            end = min(len(data), idx + 200)
            chunk = data[idx:end]
            # Find first non-printable or reasonable boundary
            text = b''
            for b in chunk:
                if 32 <= b < 127:
                    text += bytes([b])
                else:
                    break
            if len(text) > 20:
                packages.add(text.decode('ascii'))
            pos = idx + 1
    
    print(f"\n  [PROTOBUF PACKAGES]")
    for p in sorted(packages):
        print(f"    {p}")
    
    return packages

# --- Main ---
import os

paths = [
    (r"d:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin", "H3C NX30Pro"),
    (r"d:\code03\uugamebooster-docker\bin\uu.nx30pro\uuplugin", "H3C NX30Pro (ref)"),
    (r"d:\code03\uugamebooster-docker\bin\uuplugin", "x86 Container"),
]

for path, label in paths:
    if not os.path.exists(path):
        print(f"\n[SKIP] {label}: not found")
        continue
    
    with open(path, 'rb') as f:
        data = f.read()
    
    print(f"\n{'#'*60}")
    print(f"# {label} ({len(data):,} bytes)")
    print(f"{'#'*60}")
    
    find_pem_blocks(data, label)
    find_protobuf_schemas(data, label)
    
    # Also search for specific auth-related hex patterns
    # Look for TLS certificate chains, ECDSA keys, etc.
    for keyword in [b'auth', b'login', b'register', b'bind', b'cert', b'sign']:
        count = data.count(keyword)
        if count > 0:
            print(f"  Keyword '{keyword.decode()}': {count} occurrences")

print("\nDone.")
