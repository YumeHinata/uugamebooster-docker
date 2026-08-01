#!/usr/bin/env python3
"""Manual hex disassembly of the UU_* getenv sequence."""
import struct

data = open(r"d:\code03\uugamebooster-docker\bin\uuplugin", "rb").read()

# KEY AREA: The function that reads all UU_* env vars
print("=== Hex dump of UU_* getenv sequence (0x4486c0 - 0x4487e0) ===")
start = 0x4486c0
end = 0x4487e0
for i in range(start, end, 16):
    chunk = data[i:i+16]
    hex_str = ' '.join(f'{b:02x}' for b in chunk)
    ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
    print(f'  0x{i:06x}: {hex_str:48s} {ascii_str}')

# Find function entry point
print("\n=== Looking for function entry point ===")
for addr in range(0x4486d3, 0x447000, -1):
    if data[addr] == 0x55 and data[addr+1:addr+3] == b'\x48\x89\xe5':
        print(f'  push rbp; mov rbp, rsp at 0x{addr:06x}')
        break

# Manual disassembly of key area around UU_SN
print("\n=== Manual disasm around UU_SN reference ===")

# Parse each instruction
for i in range(0x4486c0, 0x448810):
    b = data[i]
    
    # mov edi, imm32
    if b == 0xBF:
        imm = struct.unpack('<I', data[i+1:i+5])[0]
        # Identify which string
        label = ""
        str_map = {
            0x7e6ed7: "UU_VENDOR",
            0x7e6ee4: "UU_MODEL",  
            0x7e6eea: "UU_SN",
            0x7e6ef0: "UU_PLUGIN_VESION",
            0x7e6f01: "UU_FIRMWARE_VERSION",
            0x7e6f15: "UU_LAN_NAME",
            0x7e6f20: "UU_LAN_IP",
            0x7e6f2a: "UU_WAN_IP",
        }
        if imm in str_map:
            label = f"  ; {str_map[imm]}"
        elif 0x7e0000 <= imm <= 0x900000:
            # Other .rodata reference
            label = f"  ; .rodata+{imm-0x7e3000:#x}"
        print(f'  0x{i:06x}: BF {imm:08x}    mov edi, 0x{imm:x}{label}')
        i += 4
        continue
    
    # call rel32
    if b == 0xE8:
        rel = struct.unpack('<i', data[i+1:i+5])[0]
        target = i + 5 + rel
        label = ""
        # Check if target is getenv
        if 0x3a6000 <= target <= 0x3a8000:
            label = "  ; getenv?"
        elif target == 0x3a6650:
            label = "  ; string op"
        elif target == 0x3a6aca:
            label = "  ; string compare/assign"
        print(f'  0x{i:06x}: E8 {rel:08x}  call 0x{target:x}{label}')
        i += 4
        continue
    
    # ret
    if b == 0xC3:
        print(f'  0x{i:06x}: C3          ret')
        continue
    
    # nop
    if b == 0x90:
        continue
    
    # lea rdi, [rbp + offset]
    if b == 0x48 and i+3 < len(data) and data[i+1] == 0x8D:
        reg_map = {0x7D: 'rbp', 0x45: 'rbp', 0x5D: 'rbp', 0x85: 'rbp'}
        modrm = data[i+2]
        if modrm in [0x7D, 0x45, 0x5D, 0x85, 0xBD, 0xB5, 0xAD, 0xA5]:
            disp = struct.unpack('<i', data[i+4:i+8])[0] if (modrm & 0xC0) == 0x80 else data[i+3]
            reg = {0x7D: 'rdi', 0x45: 'rax', 0x5D: 'rbx', 0x85: 'rax'}.get(modrm & 0x07, '?')
            print(f'  0x{i:06x}: 48 8D ...  lea {reg}, [rbp{disp:+d}]')
    
    # cmp instructions
    if b == 0x48 and i+3 < len(data):
        if data[i+1] == 0x3B:  # cmp
            print(f'  0x{i:06x}: 48 3B ...  cmp ...')
        elif data[i+1] == 0x83:  # cmp with imm
            print(f'  0x{i:06x}: 48 83 ...  cmp ..., imm')
        elif data[i+1] == 0x85:  # test
            print(f'  0x{i:06x}: 48 85 ...  test ...')

# Also analyze: at 0x4481ec, there's a fallback to "openwrt-x86_64"
# This is the MODEL detection logic
print("\n\n=== Model detection logic (around 0x4481ec) ===")
for i in range(0x448180, 0x448240):
    b = data[i]
    
    if b == 0xBF:  # mov edi
        imm = struct.unpack('<I', data[i+1:i+5])[0]
        label = ""
        if imm == 0x7e6d5f:
            label = "  ; 'openwrt-x86_64'"
        print(f'  0x{i:06x}: BF {imm:08x}    mov edi, 0x{imm:x}{label}')
    elif b == 0xBE:  # mov esi
        imm = struct.unpack('<I', data[i+1:i+5])[0]
        label = ""
        if imm == 0x7e6d5f:
            label = "  ; 'openwrt-x86_64'"
        print(f'  0x{i:06x}: BE {imm:08x}    mov esi, 0x{imm:x}{label}')
    elif b == 0xE8:  # call
        rel = struct.unpack('<i', data[i+1:i+5])[0]
        target = i + 5 + rel
        print(f'  0x{i:06x}: E8 {rel:08x}  call 0x{target:x}')
    elif b == 0xC3:  # ret
        print(f'  0x{i:06x}: C3          ret')
    elif b == 0x74 or b == 0x75:  # je/jne
        off = data[i+1]
        if off > 127: off -= 256
        target = i + 2 + off
        name = 'je' if b == 0x74 else 'jne'
        print(f'  0x{i:06x}: {b:02x} {data[i+1]:02x}        {name} 0x{target:x}')
    elif b == 0x0F and i+1 < len(data):
        b2 = data[i+1]
        if b2 == 0x84 or b2 == 0x85:  # jz/jnz
            off = struct.unpack('<i', data[i+2:i+6])[0]
            target = i + 6 + off
            name = 'jz' if b2 == 0x84 else 'jnz'
            print(f'  0x{i:06x}: 0F {b2:02x} ...  {name} 0x{target:x}')
    elif b == 0x48 and i+3 < len(data):
        if data[i+1] == 0x89:  # mov
            if data[i+2] == 0xC3:  # mov rbx, rax
                print(f'  0x{i:06x}: 48 89 C3    mov rbx, rax')
            elif data[i+2] == 0xC7:  # mov rdi, rax
                print(f'  0x{i:06x}: 48 89 C7    mov rdi, rax')

print("\n\n=== .sn file reading logic (around 0x47d2f4) ===")
for i in range(0x47d2d0, 0x47d340):
    b = data[i]
    if b == 0xBE:
        imm = struct.unpack('<I', data[i+1:i+5])[0]
        label = ""
        if 0x7ea858 <= imm <= 0x7ea86f:
            label = "  ; '/usr/sbin/uu/.sn'"
        print(f'  0x{i:06x}: BE {imm:08x}    mov esi, 0x{imm:x}{label}')
    elif b == 0xBF:
        imm = struct.unpack('<I', data[i+1:i+5])[0]
        print(f'  0x{i:06x}: BF {imm:08x}    mov edi, 0x{imm:x}')
    elif b == 0xE8:
        rel = struct.unpack('<i', data[i+1:i+5])[0]
        target = i + 5 + rel
        print(f'  0x{i:06x}: E8 {rel:08x}  call 0x{target:x}')
    elif b == 0xC3:
        print(f'  0x{i:06x}: C3          ret')
    elif b in [0x74, 0x75]:
        off = data[i+1]
        if off > 127: off -= 256
        target = i + 2 + off
        name = 'je' if b == 0x74 else 'jne'
        print(f'  0x{i:06x}: {b:02x} {data[i+1]:02x}        {name} 0x{target:x}')
    elif b == 0x85 and i+1 < len(data) and data[i+1] == 0xC0:
        print(f'  0x{i:06x}: 85 C0       test eax, eax')
    elif b == 0x48 and i+3 < len(data):
        if data[i+1: i+3] == b'\x85\xC0':
            print(f'  0x{i:06x}: 48 85 C0    test rax, rax')
