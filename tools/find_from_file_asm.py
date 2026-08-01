#!/usr/bin/env python3
"""Find the from_file assignment by analyzing x86_64 disassembly around UU_SN usage."""
import struct

with open(r'd:\code03\uugamebooster-docker\bin\uuplugin', 'rb') as f:
    data = f.read()

# Check ELF type
e_type = struct.unpack('H', data[16:18])[0]
print(f"ELF type: {e_type} (2=EXEC/non-PIE, 3=DYN/PIE)")
print(f"Entry: 0x{struct.unpack('Q', data[24:32])[0]:x}")

# Find all occurrences of "UU_SN" string in binary
uu_sn_str = b'UU_SN'
uu_sn_offset = data.find(uu_sn_str)
print(f"\nUU_SN string at file offset: 0x{uu_sn_offset:08x}")

# Find the .rodata section to determine virtual address
# Parse section headers
e_shoff = struct.unpack('Q', data[40:48])[0]
e_shentsize = struct.unpack('H', data[58:60])[0]
e_shnum = struct.unpack('H', data[60:62])[0]
e_shstrndx = struct.unpack('H', data[62:64])[0]

# Read section header string table
shstr_offset = e_shoff + e_shstrndx * e_shentsize
shstr_sh_offset = struct.unpack('Q', data[shstr_offset+24:shstr_offset+32])[0]
shstr_sh_size = struct.unpack('Q', data[shstr_offset+32:shstr_offset+40])[0]
shstrtab = data[shstr_sh_offset:shstr_sh_offset+shstr_sh_size]

# Find .text, .rodata sections
text_va = text_offset = 0
rodata_va = rodata_offset = 0
for i in range(e_shnum):
    sh_off = e_shoff + i * e_shentsize
    sh_name_off = struct.unpack('I', data[sh_off:sh_off+4])[0]
    sh_name = shstrtab[sh_name_off:shstrtab.find(b'\0', sh_name_off)].decode()
    sh_addr = struct.unpack('Q', data[sh_off+16:sh_off+24])[0]
    sh_fileoff = struct.unpack('Q', data[sh_off+24:sh_off+32])[0]
    sh_size = struct.unpack('Q', data[sh_off+32:sh_off+40])[0]
    if sh_name == '.text':
        text_va = sh_addr; text_offset = sh_fileoff
        print(f"\n.text: VA=0x{text_va:x}, file=0x{text_offset:x}, size=0x{sh_size:x}")
    elif sh_name == '.rodata':
        rodata_va = sh_addr; rodata_offset = sh_fileoff
        print(f".rodata: VA=0x{rodata_va:x}, file=0x{rodata_offset:x}, size=0x{sh_size:x}")

# Calculate virtual address of UU_SN string
if rodata_offset:
    uu_sn_va = rodata_va + (uu_sn_offset - rodata_offset)
    print(f"\nUU_SN VA: 0x{uu_sn_va:x}")

# Search .text for references to UU_SN string
# For non-PIE x86_64, mov edi, IMM32 (opcode BF)
if text_va and text_offset:
    text_start = text_offset
    text_data = data[text_offset:text_offset + 0x400000]  # reasonable text size
    uu_sn_va = rodata_va + (uu_sn_offset - rodata_offset)
    
    # Method 1: Search for absolute address in mov edi
    target_bytes = struct.pack('<I', uu_sn_va & 0xFFFFFFFF)
    idx = text_data.find(b'\xBF' + target_bytes)  # mov edi, addr
    while idx >= 0:
        file_off = text_start + idx
        print(f"\nmov edi, 0x{uu_sn_va:x} at file offset 0x{file_off:x}")
        # Show surrounding bytes
        ctx = data[max(0,file_off-20):file_off+30]
        print(f"  Context: {ctx.hex()}")
        # Simple disassembly of surrounding area
        for j in range(max(0, idx-10), min(len(text_data), idx+20)):
            off = text_start + j
            byte = data[off]
        idx = text_data.find(b'\xBF' + target_bytes, idx + 1)
    
    # Method 2: Search for LEA with RIP-relative (for PIE)
    # lea rdi, [rip+offset] = 48 8d 3d XX XX XX XX
    idx = 0
    while True:
        idx = text_data.find(b'\x48\x8d\x3d', idx)
        if idx == -1:
            break
        rel32 = struct.unpack('<i', text_data[idx+3:idx+7])[0]
        target_va = text_va + idx + 7 + rel32  # RIP points to next instruction
        if abs(target_va - uu_sn_va) < 0x1000:
            file_off = text_start + idx
            print(f"\nlea rdi, [rip+0x{rel32:x}] → 0x{target_va:x} at 0x{file_off:x}")
            ctx = data[max(0,file_off-20):file_off+30]
            print(f"  {ctx.hex()}")
        idx += 1
