#!/usr/bin/env python3
"""Find the 'from_file' check in uuplugin binary and locate the comparison point."""
import struct

with open(r'd:\code03\uugamebooster-docker\bin\uuplugin', 'rb') as f:
    data = f.read()

# Find the format string "from_file: %d"
target = b'from_file'
idx = data.find(target)
while idx >= 0:
    start = max(0, idx - 80)
    end = min(len(data), idx + 100)
    printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[start:end])
    print(f'Offset 0x{idx:08x}: ...{printable}...')
    idx = data.find(target, idx + 1)

# Also search for "unmatched sn" 
target = b'unmatched sn'
idx = data.find(target)
if idx >= 0:
    start = max(0, idx - 80)
    end = min(len(data), idx + 120)
    printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[start:end])
    print(f'\nOffset 0x{idx:08x}: ...{printable}...')
