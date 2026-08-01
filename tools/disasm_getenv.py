#!/usr/bin/env python3
"""Extract and disassemble around the getenv("UU_SN") call to find from_file logic."""
import struct

with open(r'd:\code03\uugamebooster-docker\bin\uuplugin', 'rb') as f:
    data = f.read()

# Found: mov edi, 0x7e6eea at file offset 0x486ff
# Let's show 200 bytes around it
target = 0x486ff
start = target - 60
end = target + 140

print(f"Bytes around getenv(UU_SN) at 0x{target:x}:")
print()

# Manual disassembly
code = data[start:end]
i = 0
while i < len(code):
    off = start + i
    b = code[i]
    
    if i == (target - start):
        print(f"\n  >>> getenv('UU_SN') call site <<<\n")
    
    # Basic x86_64 instruction decoding
    if b == 0xBF and i + 4 < len(code):
        imm = struct.unpack('<I', code[i+1:i+5])[0]
        print(f"  0x{off:06x}: mov edi, 0x{imm:x}")
        i += 5
    elif b == 0xBE and i + 4 < len(code):
        imm = struct.unpack('<I', code[i+1:i+5])[0]
        print(f"  0x{off:06x}: mov esi, 0x{imm:x}")
        i += 5
    elif b == 0xBA and i + 4 < len(code):
        imm = struct.unpack('<I', code[i+1:i+5])[0]
        print(f"  0x{off:06x}: mov edx, 0x{imm:x}")
        i += 5
    elif b == 0xB9 and i + 4 < len(code):
        imm = struct.unpack('<I', code[i+1:i+5])[0]
        print(f"  0x{off:06x}: mov ecx, 0x{imm:x}")
        i += 5
    elif b == 0xB8 and i + 4 < len(code):
        imm = struct.unpack('<I', code[i+1:i+5])[0]
        print(f"  0x{off:06x}: mov eax, 0x{imm:x}")
        i += 5
    elif b == 0xE8 and i + 4 < len(code):
        rel = struct.unpack('<i', code[i+1:i+5])[0]
        target_va = 0x400200 + off + 5 + rel  # .text VA=0x400200, file_base=0x200
        print(f"  0x{off:06x}: call 0x{target_va:x}")
        i += 5
    elif b == 0xE9 and i + 4 < len(code):
        rel = struct.unpack('<i', code[i+1:i+5])[0]
        target_va = 0x400200 + off + 5 + rel
        print(f"  0x{off:06x}: jmp 0x{target_va:x}")
        i += 5
    elif b == 0x85:
        # test r/m, r
        modrm = code[i+1]
        reg = (modrm >> 3) & 7
        rm = modrm & 7
        print(f"  0x{off:06x}: test (modrm=0x{modrm:02x})")
        i += 2
    elif b == 0x48 and code[i+1] == 0x85:
        modrm = code[i+2]
        reg = (modrm >> 3) & 7
        rm = modrm & 7
        regs = ['rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi']
        print(f"  0x{off:06x}: test {regs[reg]}, {regs[rm]}")
        i += 3
    elif b == 0x74:
        rel = struct.unpack('b', bytes([code[i+1]]))[0]
        target_off = off + 2 + rel
        print(f"  0x{off:06x}: je 0x{target_off:x}")
        i += 2
    elif b == 0x75:
        rel = struct.unpack('b', bytes([code[i+1]]))[0]
        target_off = off + 2 + rel
        print(f"  0x{off:06x}: jne 0x{target_off:x}")
        i += 2
    elif b == 0x84:
        modrm = code[i+1]
        print(f"  0x{off:06x}: test (modrm=0x{modrm:02x})")
        i += 2
    elif b == 0x0F and code[i+1] == 0x84:
        rel = struct.unpack('<i', code[i+2:i+6])[0]
        target_off = off + 6 + rel
        print(f"  0x{off:06x}: je 0x{target_off:x}")
        i += 6
    elif b == 0x0F and code[i+1] == 0x85:
        rel = struct.unpack('<i', code[i+2:i+6])[0]
        target_off = off + 6 + rel
        print(f"  0x{off:06x}: jne 0x{target_off:x}")
        i += 6
    elif b == 0xC3:
        print(f"  0x{off:06x}: ret")
        i += 1
    elif b == 0x48 and code[i+1] == 0x8B:
        modrm = code[i+2]
        reg = (modrm >> 3) & 7
        rm = modrm & 7
        regs = ['rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi']
        print(f"  0x{off:06x}: mov {regs[reg]}, [{regs[rm]}+...]")
        i += 3 + (1 if (modrm >> 6) == 1 else 4 if (modrm >> 6) == 2 else 0)
    elif b == 0x48 and code[i+1] == 0x89:
        modrm = code[i+2]
        reg = (modrm >> 3) & 7
        rm = modrm & 7
        regs = ['rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi']
        print(f"  0x{off:06x}: mov [{regs[rm]}+...], {regs[reg]}")
        i += 3 + (1 if (modrm >> 6) == 1 else 4 if (modrm >> 6) == 2 else 0)
    elif b == 0xC7 and code[i+1] == 0x45:
        # mov [rbp+disp8], imm32
        disp = code[i+2]
        imm = struct.unpack('<I', code[i+3:i+7])[0]
        print(f"  0x{off:06x}: mov [rbp+0x{disp:x}], 0x{imm:x}")
        i += 7
    elif b == 0xC7 and code[i+1] == 0x85:
        # mov [rbp+disp32], imm32
        disp = struct.unpack('<I', code[i+2:i+6])[0]
        imm = struct.unpack('<I', code[i+6:i+10])[0]
        print(f"  0x{off:06x}: mov [rbp+0x{disp:x}], 0x{imm:x}")
        i += 10
    elif b == 0xC6:
        modrm = code[i+1]
        if modrm == 0x45:
            disp = code[i+2]
            val = code[i+3]
            print(f"  0x{off:06x}: mov BYTE [rbp+0x{disp:x}], 0x{val:x}")
            i += 4
        else:
            print(f"  0x{off:06x}: mov BYTE ...")
            i += 1
    elif b == 0xC7 and code[i+1] == 0x45 and code[i+2] < 0x80:
        disp = code[i+2]
        if i + 6 < len(code):
            imm = struct.unpack('<I', code[i+3:i+7])[0]
            print(f"  0x{off:06x}: mov DWORD [rbp+0x{disp:x}], 0x{imm:x}")
            i += 7
        else:
            i += 1
    elif b == 0xC7 and code[i+1] == 0x85 and i + 9 < len(code):
        disp = struct.unpack('<I', code[i+2:i+6])[0]
        imm = struct.unpack('<I', code[i+6:i+10])[0]
        print(f"  0x{off:06x}: mov DWORD [rbp+0x{disp:x}], 0x{imm:x}")
        i += 10
    elif b == 0x31 and code[i+1] in [0xC0, 0xC9, 0xD2, 0xDB, 0xE4, 0xED, 0xF6, 0xFF]:
        regs = {0xC0:'eax/eax',0xC9:'ecx/ecx',0xD2:'edx/edx',0xDB:'ebx/ebx',
                0xE4:'esp/esp',0xED:'ebp/ebp',0xF6:'esi/esi',0xFF:'edi/edi'}
        print(f"  0x{off:06x}: xor {regs.get(code[i+1], '?')}")
        i += 2
    elif b == 0x41:
        # REX prefix with REX.B
        if code[i+1] == 0x54:
            print(f"  0x{off:06x}: push r12")
            i += 2
        elif code[i+1] == 0x55:
            print(f"  0x{off:06x}: push r13")
            i += 2
        elif code[i+1] == 0x56:
            print(f"  0x{off:06x}: push r14")
            i += 2
        elif code[i+1] == 0x57:
            print(f"  0x{off:06x}: push r15")
            i += 2
        else:
            i += 1
    else:
        i += 1

# Total bytes shown
print(f"\n=== Total: {len(code)} bytes decoded ===")
