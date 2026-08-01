#!/usr/bin/env python3
"""
Find ALL calls to getenv and trace the UU_* env var reading logic.
Uses PLT stub analysis and proper code disassembly.
"""
import struct
from capstone import *
from capstone.x86 import *

data = open(r"d:\code03\uugamebooster-docker\bin\uuplugin", "rb").read()

# Parse ELF
e_type = struct.unpack('H', data[16:18])[0]
print(f"ELF type: {e_type} (2=EXEC, 3=DYN)")
e_shoff = struct.unpack('Q', data[40:48])[0]
e_shentsize = struct.unpack('H', data[58:60])[0]
e_shnum = struct.unpack('H', data[60:62])[0]
e_shstrndx = struct.unpack('H', data[62:64])[0]

shstr_off = e_shoff + e_shstrndx * e_shentsize
shstr_sh_off = struct.unpack('Q', data[shstr_off+24:shstr_off+32])[0]
shstr_sh_size = struct.unpack('Q', data[shstr_off+32:shstr_off+40])[0]
shstrtab = data[shstr_sh_off:shstr_sh_off+shstr_sh_size]

sections = {}
for i in range(e_shnum):
    sh_off = e_shoff + i * e_shentsize
    sh_name_off = struct.unpack('I', data[sh_off:sh_off+4])[0]
    sh_name = shstrtab[sh_name_off:shstrtab.find(b'\0', sh_name_off)].decode(errors='replace')
    sh_addr = struct.unpack('Q', data[sh_off+16:sh_off+24])[0]
    sh_fileoff = struct.unpack('Q', data[sh_off+24:sh_off+32])[0]
    sh_size = struct.unpack('Q', data[sh_off+32:sh_off+40])[0]
    sections[sh_name] = {'va': sh_addr, 'file_off': sh_fileoff, 'size': sh_size}

for name, sec in sections.items():
    if sec['size'] > 1000:
        print(f"  {name}: VA=0x{sec['va']:x} file=0x{sec['file_off']:x} size=0x{sec['size']:x}")

# ═══════════════════════════════════════════════════════════
# Find getenv in PLT
# ═══════════════════════════════════════════════════════════

# First, find .dynsym and .dynstr to locate getenv
dynsym = sections.get('.dynsym')
dynstr = sections.get('.dynstr')

getenv_got = None
getenv_plt = None

if dynsym and dynstr:
    dynsym_data = data[dynsym['file_off']:dynsym['file_off']+dynsym['size']]
    dynstr_data = data[dynstr['file_off']:dynstr['file_off']+dynstr['size']]
    
    # Each dynsym entry is 24 bytes
    for i in range(0, len(dynsym_data), 24):
        entry = dynsym_data[i:i+24]
        if len(entry) < 24:
            break
        st_name = struct.unpack('I', entry[0:4])[0]
        name = dynstr_data[st_name:dynstr_data.find(b'\0', st_name)].decode()
        if name == 'getenv':
            st_value = struct.unpack('Q', entry[8:16])[0]
            st_size = struct.unpack('Q', entry[16:24])[0]
            print(f"\n  getenv in dynsym: value=0x{st_value:x}, size={st_size}")
            getenv_got = st_value
            break

# Now find the PLT stub for getenv
# PLT stubs: ff 25 XX XX XX XX (jmp [rip+offset]) + 68 XX XX XX XX (push) + E9 XX XX XX XX (jmp)
# We need to find which PLT entry corresponds to getenv GOT entry
rela_plt = sections.get('.rela.plt')
if rela_plt and getenv_got:
    rela_data = data[rela_plt['file_off']:rela_plt['file_off']+rela_plt['size']]
    # Each Rela entry is 24 bytes
    for i in range(0, len(rela_data), 24):
        entry = rela_data[i:i+24]
        if len(entry) < 24:
            break
        r_offset = struct.unpack('Q', entry[0:8])[0]
        r_info = struct.unpack('Q', entry[8:16])[0]
        if r_offset == getenv_got:
            # This is the relocation entry for getenv
            # PLT entry index = i / 24
            plt_idx = i // 24
            # PLT starts at .plt VA
            plt = sections.get('.plt')
            if plt:
                # PLT entry size varies (typically 16 bytes)
                # Entry 0 is special (resolver), entries start at index 1
                getenv_plt = plt['va'] + 16 * plt_idx  # PLT stub
                print(f"  getenv PLT stub at VA 0x{getenv_plt:x} (plt_idx={plt_idx})")
                # Dump the PLT stub
                stub_off = plt['file_off'] + 16 * plt_idx
                stub = data[stub_off:stub_off+16]
                print(f"  PLT stub hex: {stub.hex()}")

# ═══════════════════════════════════════════════════════════
# Now search .text for calls to getenv PLT
# ═══════════════════════════════════════════════════════════

if getenv_plt:
    text = sections['.text']
    text_data = data[text['file_off']:text['file_off']+text['size']]
    text_va = text['va']
    
    print(f"\n  Searching .text for calls to getenv@PLT (0x{getenv_plt:x})...")
    
    # call rel32 = E8 XX XX XX XX
    # target = insn_addr + 5 + rel32
    call_sites = []
    for i in range(0, len(text_data) - 5):
        if text_data[i] == 0xE8:
            rel32 = struct.unpack('<i', text_data[i+1:i+5])[0]
            target = text_va + i + 5 + rel32
            if target == getenv_plt:
                va = text_va + i
                file_off = text['file_off'] + i
                call_sites.append((va, file_off))
    
    print(f"  Found {len(call_sites)} calls to getenv")
    
    # Disassemble around each call
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    
    for va, file_off in call_sites:
        # Look at the 5 bytes before the call (usually mov edi, ...)
        pre_bytes = data[file_off-5:file_off]
        call_bytes = data[file_off:file_off+5]
        
        # Check if this is mov edi, imm32; call getenv
        if pre_bytes[0] == 0xBF:
            # mov edi, imm32
            imm = struct.unpack('<I', pre_bytes[1:5])[0]
            # Check if this is in .rodata string range
            rodata = sections.get('.rodata', {})
            if rodata and rodata['va'] <= imm <= rodata['va'] + rodata['size']:
                # Read the string
                str_off = rodata['file_off'] + (imm - rodata['va'])
                str_data = data[str_off:str_off+60]
                str_val = str_data[:str_data.find(b'\0')].decode(errors='replace')
                if any(kw in str_val for kw in ['UU_', 'VENDOR', 'MODEL', 'SN', 'LAN', 'WAN', 'model', 'vendor', 'product']):
                    print(f"\n  getenv call at 0x{va:x} (file 0x{file_off:x})")
                    print(f"    mov edi, 0x{imm:x}  ; \"{str_val}\"")
                    
                    # Show more context
                    insns = list(md.disasm(data[file_off-20:file_off+30], va-20))
                    for insn in insns:
                        marker = " <-- getenv" if insn.address == va else ""
                        print(f"    0x{insn.address:06x}: {insn.mnemonic:8s} {insn.op_str}{marker}")
        elif pre_bytes[1] == 0xBF and pre_bytes[0] == 0x48:
            # Might be: 48 BF ... movabs rdi, imm64 (less common)
            pass
        else:
            # Might be a different pattern (e.g., lea rdi, [rip+...])
            # Disassemble to see
            insns = list(md.disasm(data[file_off-16:file_off+5], va-16))
            last_rdi = None
            for insn in insns:
                if insn.address < va and 'rdi' in insn.op_str:
                    last_rdi = insn
            if last_rdi:
                print(f"\n  getenv call at 0x{va:x} (file 0x{file_off:x})")
                print(f"    Previous rdi-set: 0x{last_rdi.address:x}: {last_rdi.mnemonic} {last_rdi.op_str}")
                for insn in insns:
                    marker = " <-- getenv" if insn.address == va else " <-- sets rdi" if insn == last_rdi else ""
                    print(f"    0x{insn.address:06x}: {insn.mnemonic:8s} {insn.op_str}{marker}")
else:
    print("  ERROR: getenv PLT not found!")
    print("  Trying alternative: search for imports in .dynsym...")
    # Find all dynamic symbols that might be getenv-like
    if dynsym and dynstr:
        dynsym_data = data[dynsym['file_off']:dynsym['file_off']+dynsym['size']]
        dynstr_data = data[dynstr['file_off']:dynstr['file_off']+dynstr['size']]
        for i in range(0, len(dynsym_data), 24):
            entry = dynsym_data[i:i+24]
            if len(entry) < 24:
                break
            st_name = struct.unpack('I', entry[0:4])[0]
            name = dynstr_data[st_name:dynstr_data.find(b'\0', st_name)].decode(errors='replace')
            if 'getenv' in name.lower() or 'env' in name.lower():
                st_value = struct.unpack('Q', entry[8:16])[0]
                print(f"  Found: {name} at value=0x{st_value:x}")
