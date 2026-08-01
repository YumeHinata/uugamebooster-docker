#!/usr/bin/env python3
"""Find ALL references to UU_SN string address in the binary code sections."""
import struct

with open(r'd:\code03\uugamebooster-docker\bin\uuplugin', 'rb') as f:
    data = f.read()

# Parse ELF to find sections
e_shoff = struct.unpack('Q', data[40:48])[0]
e_shentsize = struct.unpack('H', data[58:60])[0]
e_shnum = struct.unpack('H', data[60:62])[0]
e_shstrndx = struct.unpack('H', data[62:64])[0]

shstr_offset = e_shoff + e_shstrndx * e_shentsize
shstr_sh_offset = struct.unpack('Q', data[shstr_offset+24:shstr_offset+32])[0]
shstrtab = data[shstr_sh_offset:shstr_sh_offset+struct.unpack('Q', data[shstr_offset+32:shstr_offset+40])[0]]

sections = {}
for i in range(e_shnum):
    sh_off = e_shoff + i * e_shentsize
    sh_name_off = struct.unpack('I', data[sh_off:sh_off+4])[0]
    sh_name = shstrtab[sh_name_off:shstrtab.find(b'\0', sh_name_off)].decode()
    sh_addr = struct.unpack('Q', data[sh_off+16:sh_off+24])[0]
    sh_fileoff = struct.unpack('Q', data[sh_off+24:sh_off+32])[0]
    sh_size = struct.unpack('Q', data[sh_off+32:sh_off+40])[0]
    sections[sh_name] = (sh_addr, sh_fileoff, sh_size)
    if sh_name in ('.text', '.rodata', '.data', '.plt'):
        print(f"Section {sh_name}: VA=0x{sh_addr:x}, file=0x{sh_fileoff:x}, size=0x{sh_size:x}")

# Find UU_SN string
uu_sn_str = b'UU_SN'
uu_sn_offset = data.find(uu_sn_str)
print(f"\nUU_SN string at file offset: 0x{uu_sn_offset:08x} (first occurrence)")

# Find ALL occurrences of UU_SN string
all_positions = []
idx = 0
while True:
    idx = data.find(uu_sn_str, idx)
    if idx == -1:
        break
    all_positions.append(idx)
    idx += 1
print(f"Total occurrences of 'UU_SN' string: {len(all_positions)}")
for pos in all_positions:
    start = max(0, pos - 20)
    end = min(len(data), pos + 30)
    ctx = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[start:end])
    print(f"  0x{pos:08x}: ...{ctx}...")

# Find all CODE references to the UU_SN string
# The UU_SN string is in .rodata. Find all pointers to it.
if '.rodata' in sections:
    rodata_va, rodata_fileoff, rodata_size = sections['.rodata']
    uu_sn_va = rodata_va + (uu_sn_offset - rodata_fileoff)
    uu_sn_va_low = uu_sn_va & 0xFFFFFFFF
    
    print(f"\nUU_SN VA: 0x{uu_sn_va:x}")
    print(f"Searching for references to 0x{uu_sn_va:x} in all sections...")
    
    # Search in .text, .rodata, .data for references
    for sec_name in ['.text', '.rodata', '.data']:
        if sec_name not in sections:
            continue
        sec_va, sec_fileoff, sec_size = sections[sec_name]
        sec_data = data[sec_fileoff:sec_fileoff+sec_size]
        
        # Search for absolute address bytes (little-endian)
        target = struct.pack('<Q', uu_sn_va)
        idx = 0
        count = 0
        while True:
            idx = sec_data.find(target, idx)
            if idx == -1:
                break
            file_off = sec_fileoff + idx
            print(f"\n  [{sec_name}] 8-byte ptr to UU_SN at file 0x{file_off:x}")
            ctx = data[max(0,file_off-10):file_off+20]
            print(f"    hex: {ctx.hex()}")
            count += 1
            idx += 1
        if count == 0:
            print(f"  [{sec_name}] No 8-byte references found")
        
        # Search for 4-byte absolute address
        target = struct.pack('<I', uu_sn_va_low)
        idx = 0
        count = 0
        while True:
            idx = sec_data.find(target, idx)
            if idx == -1:
                break
            file_off = sec_fileoff + idx
            # Check context to avoid false positives
            ctx = data[max(0,file_off-5):file_off+10]
            # Common patterns: mov edi, addr; lea rdi, [addr]; .quad addr
            if file_off > 0:
                prev = data[file_off-1]
                prev2 = data[file_off-2] if file_off > 1 else 0
                prev3 = data[file_off-3] if file_off > 2 else 0
                # mov edi, imm32 → BF XX XX XX XX
                if prev == 0xBF:
                    print(f"\n  [{sec_name}] mov edi, 0x{uu_sn_va_low:x} at file 0x{(file_off-1):x}")
                # mov esi, imm32 → BE XX XX XX XX
                elif prev == 0xBE:
                    print(f"\n  [{sec_name}] mov esi, 0x{uu_sn_va_low:x} at file 0x{(file_off-1):x}")
                # lea rdi, [rip+...] → check 3 bytes back
                elif prev3 == 0x48 and prev2 == 0x8d and prev == 0x3d:
                    print(f"\n  [{sec_name}] lea rdi, [rip+...] at file 0x{(file_off-3):x}")
                else:
                    print(f"\n  [{sec_name}] 4-byte value 0x{uu_sn_va_low:x} at file 0x{file_off:x}")
                print(f"    hex: {ctx.hex()}")
            count += 1
            idx += 1
        if count == 0:
            print(f"  [{sec_name}] No 4-byte references found")
