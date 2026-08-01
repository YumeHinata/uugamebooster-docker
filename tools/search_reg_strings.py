#!/usr/bin/env python3
"""Search for registration-specific strings in both binaries."""
import os

targets = [
    b'h3cnx30', b'h3c-nx30', b'nx30pro', b'NX30', b'H3C',
    b'v14.3', b'v14.4', b'v14.2',
    b'aarch64', b'x86_64', b'x86-64',
    b'from_file', b'manucode', b'productname',
    b'CertReq', b'CertRes', b'AuthReq', b'AuthRes',
    b'create_private_key', b'create_cert', b'do_sign',
    b'domestic', b'device_id',
    b'UU_MODEL', b'UU_PRODUCT', b'UU_SN',
    b'os=', b'platform=', b'product=',
]

for path, label in [
    (r"d:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin", 'H3C'),
    (r"d:\code03\uugamebooster-docker\bin\uuplugin", 'x86')
]:
    with open(path, 'rb') as f:
        data = f.read()
    print(f"\n=== {label} ({len(data):,} bytes) ===")
    
    for t in targets:
        count = data.count(t)
        if count > 0:
            idx = data.find(t)
            start = max(0, idx - 20)
            end = min(len(data), idx + len(t) + 40)
            ctx = data[start:end]
            printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in ctx)
            print(f'  "{t.decode()}": {count}x @0x{idx:08x} -> ...{printable}...')
