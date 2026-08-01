#!/usr/bin/env python3
"""Find FATAL context and search for the from_file / router.cpp area."""
data = open(r'd:\code03\uugamebooster-docker\bin\uuplugin', 'rb').read()

# Show FATAL context
idx = data.find(b'FATAL')
while idx >= 0:
    start = max(0, idx - 100)
    end = min(len(data), idx + 120)
    printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[start:end])
    print(f'0x{idx:08x}: ...{printable}...')
    print()
    idx = data.find(b'FATAL', idx + 1)

# Search for "router.cpp"
for kw in [b'router.cpp', b'router\0', b'.cpp']:
    idx = data.find(kw)
    if idx >= 0:
        start = max(0, idx - 50)
        end = min(len(data), idx + 50)
        printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[start:end])
        print(f'0x{idx:08x} ({kw}): ...{printable}...')

# Search for %d format specifiers near sn-related strings
for kw in [b'sn', b'_sn', b'SN', b'from_', b'%d']:
    cnt = data.count(kw)
    if 0 < cnt < 20:
        idx = data.find(kw)
        while idx >= 0:
            start = max(0, idx - 30)
            end = min(len(data), idx + 30)
            printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[start:end])
            print(f'0x{idx:08x}: ...{printable}...')
            idx = data.find(kw, idx + 1)
