#!/usr/bin/env python3
"""Check if binaries use DNS resolution or hardcoded IPs."""
import os

for path, label in [
    (r"d:\code03\uugamebooster-docker\bin\uuplugin", 'x86'),
    (r"d:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin", 'H3C')
]:
    with open(path, 'rb') as f:
        data = f.read()
    print(f"\n=== {label} ({len(data):,} bytes) ===")
    
    # DNS-related functions
    for kw in [b'getaddrinfo', b'gethostbyname', b'getent', b'res_ninit',
               b'__res_', b'ns_name', b'dns', b'resolve']:
        c = data.count(kw)
        if c > 0:
            print(f"  DNS func '{kw.decode()}': {c}x")
    
    # UU hostnames  
    for host in [b'uu.163.com', b'uu.netease.com', b'rglg.uu', b'h3crglg',
                 b'router.uu', b'uurouter']:
        c = data.count(host)
        if c > 0:
            idx = data.find(host)
            ctx_start = max(0, idx - 10)
            ctx_end = min(len(data), idx + len(host) + 30)
            ctx = data[ctx_start:ctx_end]
            printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in ctx)
            print(f"  HOST '{host.decode()}': {c}x ctx=...{printable}...")
    
    # Hardcoded IPs
    for ip in [b'106.2.95.34', b'106.2.59.231', b'59.111.45.61', b'42.186.111.127']:
        c = data.count(ip)
        if c > 0:
            print(f"  IP '{ip.decode()}': {c}x HARDCODED!")

print("\nDone.")
