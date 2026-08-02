#!/usr/bin/env python3
"""
analyze_binary.py — Extract device_discover related info from uuplugin binary.
Uses strings + heuristics since the binary is stripped (no symbol table).
"""

import re
import sys
from pathlib import Path
from collections import defaultdict

BINARY = Path(__file__).parent.parent / "bin" / "uuplugin"

def extract_strings(path, min_len=4):
    """Extract printable strings from binary."""
    with open(path, 'rb') as f:
        data = f.read()
    # Extract ASCII strings (4+ chars)
    strings = []
    current = []
    for b in data:
        if 32 <= b < 127:
            current.append(chr(b))
        else:
            if len(current) >= min_len:
                strings.append(''.join(current))
            current = []
    if len(current) >= min_len:
        strings.append(''.join(current))
    return strings

def analyze():
    print(f"[*] Loading: {BINARY} ({BINARY.stat().st_size / 1024 / 1024:.1f} MB)")
    strings = extract_strings(BINARY)
    print(f"[*] Extracted {len(strings)} strings")

    # Categorize
    paths = set()
    files = set()
    modules = set()
    env_vars = set()
    proto = set()
    err_msgs = set()

    for s in strings:
        s = s.strip()
        if s.startswith('/'):
            if any(s.endswith(ext) for ext in ('.cpp', '.h', '.hpp')):
                modules.add(s)
            else:
                paths.add(s)
        elif s.endswith('.cpp') or s.endswith('.h'):
            modules.add(s)
        elif s.startswith('UU_'):
            env_vars.add(s)
        elif re.search(r'getenv|setenv|environ', s, re.I):
            err_msgs.add(s)
        elif re.search(r'proto|protobuf|\.proto', s, re.I):
            proto.add(s)
        elif 'nmp_client' in s or 'client_list' in s:
            files.add(s)

    # ── Device Discovery Subsystem ──
    print("\n" + "=" * 60)
    print("DEVICE DISCOVERY SUBSYSTEM")
    print("=" * 60)

    dd_modules = [m for m in modules if 'discover' in m.lower() or 'dhcp' in m.lower() or 'arp' in m.lower()]
    print("\n[Modules]")
    for m in sorted(dd_modules):
        print(f"  {m}")

    dd_paths = [p for p in paths if any(k in p.lower() for k in ('dhcp', 'arp', 'lease', 'client', 'nmp', 'neigh', 'discover', 'nft_'))]
    print("\n[Data Files]")
    for p in sorted(dd_paths):
        print(f"  {p}")

    # ── Environment Variables ──
    print("\n" + "=" * 60)
    print("ENVIRONMENT VARIABLES (getenv)")
    print("=" * 60)
    for v in sorted(env_vars):
        print(f"  {v}")

    # ── Configuration ──
    print("\n" + "=" * 60)
    print("REFERENCED FILES & PATHS")
    print("=" * 60)
    for p in sorted(paths):
        if '/tmp' in p or '/var' in p or '/proc' in p or '/dev' in p:
            print(f"  {p}")

    # ── Protobuf ──
    print("\n" + "=" * 60)
    print("PROTOBUF / WIRE PROTOCOL")
    print("=" * 60)
    for p in sorted(proto):
        print(f"  {p}")

    # ── Guardian ──
    guardian = [s for s in strings if 'guardian' in s.lower() or 'xuplugin' in s.lower()]
    print("\n" + "=" * 60)
    print("GUARDIAN / PROCESS MANAGEMENT")
    print("=" * 60)
    for g in sorted(set(guardian)):
        print(f"  {g}")

if __name__ == '__main__':
    analyze()
