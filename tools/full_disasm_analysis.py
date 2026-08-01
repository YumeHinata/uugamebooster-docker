#!/usr/bin/env python3
"""
Full disassembly analysis of x86 uuplugin binary.
Goals:
1. Find all from_file references and understand its logic
2. Trace vendor/model detection flow
3. Compare x86 vs NX30Pro (aarch64) binaries
4. Identify patch points to make x86 behave like H3C NX30Pro
"""
import struct
import os
from capstone import *
from collections import defaultdict
import re

X86_PATH = r"d:\code03\uugamebooster-docker\bin\uuplugin"
NX30_PATH = r"d:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin"

# ═══════════════════════════════════════════════════════════════════════════
# ELF Parsing
# ═══════════════════════════════════════════════════════════════════════════

def parse_elf(data):
    """Parse ELF header and return sections map."""
    ei_class = data[4]  # 1=32bit, 2=64bit
    is_64 = (ei_class == 2)
    
    if is_64:
        e_shoff = struct.unpack('Q', data[40:48])[0]
        e_shentsize = struct.unpack('H', data[58:60])[0]
        e_shnum = struct.unpack('H', data[60:62])[0]
        e_shstrndx = struct.unpack('H', data[62:64])[0]
        entry = struct.unpack('Q', data[24:32])[0]
    else:
        e_shoff = struct.unpack('I', data[32:36])[0]
        e_shentsize = struct.unpack('H', data[46:48])[0]
        e_shnum = struct.unpack('H', data[48:50])[0]
        e_shstrndx = struct.unpack('H', data[50:52])[0]
        entry = struct.unpack('I', data[24:28])[0]
    
    # Read section header string table
    shstr_off = e_shoff + e_shstrndx * e_shentsize
    if is_64:
        shstr_sh_off = struct.unpack('Q', data[shstr_off+24:shstr_off+32])[0]
        shstr_sh_size = struct.unpack('Q', data[shstr_off+32:shstr_off+40])[0]
    else:
        shstr_sh_off = struct.unpack('I', data[shstr_off+16:shstr_off+20])[0]
        shstr_sh_size = struct.unpack('I', data[shstr_off+20:shstr_off+24])[0]
    shstrtab = data[shstr_sh_off:shstr_sh_off+shstr_sh_size]
    
    sections = {}
    for i in range(e_shnum):
        sh_off = e_shoff + i * e_shentsize
        sh_name_off = struct.unpack('I', data[sh_off:sh_off+4])[0]
        sh_name = shstrtab[sh_name_off:shstrtab.find(b'\0', sh_name_off)].decode(errors='replace')
        
        if is_64:
            sh_addr = struct.unpack('Q', data[sh_off+16:sh_off+24])[0]
            sh_fileoff = struct.unpack('Q', data[sh_off+24:sh_off+32])[0]
            sh_size = struct.unpack('Q', data[sh_off+32:sh_off+40])[0]
        else:
            sh_addr = struct.unpack('I', data[sh_off+12:sh_off+16])[0]
            sh_fileoff = struct.unpack('I', data[sh_off+16:sh_off+20])[0]
            sh_size = struct.unpack('I', data[sh_off+20:sh_off+24])[0]
        
        if sh_size > 0:
            sections[sh_name] = {
                'va': sh_addr, 'file_off': sh_fileoff,
                'size': sh_size, 'data': data[sh_fileoff:sh_fileoff+sh_size]
            }
    
    return {
        'is_64': is_64, 'entry': entry,
        'sections': sections, 'data': data,
        'e_shoff': e_shoff, 'e_shentsize': e_shentsize
    }

# ═══════════════════════════════════════════════════════════════════════════
# String Search
# ═══════════════════════════════════════════════════════════════════════════

def find_all_strings(data, target, context=60):
    """Find all occurrences of target bytes with context."""
    results = []
    idx = 0
    while True:
        idx = data.find(target, idx)
        if idx == -1:
            break
        start = max(0, idx - context)
        end = min(len(data), idx + len(target) + context)
        results.append((idx, data[start:end]))
        idx += 1
    return results

def printable_ctx(data_bytes, max_len=100):
    """Convert bytes to printable string."""
    return ''.join(chr(b) if 32 <= b < 127 else '.' for b in data_bytes[:max_len])

# ═══════════════════════════════════════════════════════════════════════════
# Disassembly Analysis
# ═══════════════════════════════════════════════════════════════════════════

def disasm_x86_range(elf, file_start, file_end):
    """Disassemble a range of x86 code."""
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    code = elf['data'][file_start:file_end]
    instructions = []
    for insn in md.disasm(code, file_start):
        instructions.append(insn)
        if insn.address >= file_end:
            break
    return instructions

def disasm_arm_range(elf, file_start, file_end):
    """Disassemble a range of ARM64 code."""
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    md.detail = True
    code = elf['data'][file_start:file_end]
    instructions = []
    for insn in md.disasm(code, file_start):
        instructions.append(insn)
        if insn.address >= file_end:
            break
    return instructions

def find_function_boundaries_x86(instructions):
    """Find function boundaries in x86 disassembly."""
    funcs = []
    current_start = None
    for insn in instructions:
        # Function prologue: push rbp; mov rbp, rsp
        if insn.mnemonic == 'push' and 'rbp' in insn.op_str:
            if current_start is not None:
                funcs.append((current_start, insn.address))
            current_start = insn.address
        # ret instruction
        elif insn.mnemonic == 'ret' and current_start is not None:
            funcs.append((current_start, insn.address + insn.size))
            current_start = None
    return funcs

# ═══════════════════════════════════════════════════════════════════════════
# Cross-reference Analysis
# ═══════════════════════════════════════════════════════════════════════════

def find_xrefs_to_string(elf, target_bytes):
    """Find all code references to a string in .rodata."""
    data = elf['data']
    
    # Find the string offset in .rodata
    rodata = elf['sections'].get('.rodata', {})
    if not rodata:
        print("ERROR: .rodata not found")
        return []
    
    rodata_va = rodata['va']
    rodata_off = rodata['file_off']
    
    # Find all occurrences of target in binary
    str_offsets = [pos for pos, _ in find_all_strings(data, target_bytes)]
    
    xrefs = []
    for str_off in str_offsets:
        # Calculate VA of this string
        str_va = rodata_va + (str_off - rodata_off) if str_off >= rodata_off else str_off
        str_va_low = str_va & 0xFFFFFFFF
        
        # Search in .text for references
        text = elf['sections'].get('.text', {})
        if not text:
            continue
        
        text_data = text['data']
        text_va = text['va']
        text_off = text['file_off']
        
        # Search for 32-bit absolute references (mov edi, IMM32; lea rdi, [rip+...])
        target_32 = struct.pack('<I', str_va_low)
        idx = 0
        while True:
            idx = text_data.find(target_32, idx)
            if idx == -1:
                break
            
            file_off = text_off + idx
            va_addr = text_va + idx
            
            # Check instruction context
            if idx >= 1:
                prev = text_data[idx-1]
                # mov edi, imm32 = BF
                if prev == 0xBF:
                    xrefs.append({
                        'type': 'mov_edi',
                        'file_off': file_off - 1,
                        'va': va_addr - 1,
                        'str_off': str_off,
                        'str_va': str_va
                    })
                # mov esi, imm32 = BE
                elif prev == 0xBE:
                    xrefs.append({
                        'type': 'mov_esi',
                        'file_off': file_off - 1,
                        'va': va_addr - 1,
                        'str_off': str_off,
                        'str_va': str_va
                    })
                # Check for RIP-relative LEA (48 8d 3d XX XX XX XX)
                if idx >= 3:
                    prev3 = text_data[idx-3:idx]
                    if prev3 == b'\x48\x8d\x3d':  # lea rdi, [rip+...]
                        rel32 = struct.unpack('<i', text_data[idx:idx+4])[0]
                        target_va = va_addr + 4 + rel32
                        xrefs.append({
                            'type': 'lea_rdi_rip',
                            'file_off': file_off - 3,
                            'va': va_addr - 3,
                            'str_off': str_off,
                            'str_va': str_va,
                            'computed_va': target_va
                        })
                    elif prev3 == b'\x48\x8d\x35':  # lea rsi, [rip+...]
                        rel32 = struct.unpack('<i', text_data[idx:idx+4])[0]
                        target_va = va_addr + 4 + rel32
                        xrefs.append({
                            'type': 'lea_rsi_rip',
                            'file_off': file_off - 3,
                            'va': va_addr - 3,
                            'str_off': str_off,
                            'str_va': str_va,
                            'computed_va': target_va
                        })
            
            idx += 1
    
    return xrefs

# ═══════════════════════════════════════════════════════════════════════════
# Function context (disassemble around an address)
# ═══════════════════════════════════════════════════════════════════════════

def disasm_context(elf, file_off, before_bytes=100, after_bytes=200):
    """Disassemble around a specific file offset."""
    start = max(0, file_off - before_bytes)
    end = min(len(elf['data']), file_off + after_bytes)
    return disasm_x86_range(elf, start, end)

# ═══════════════════════════════════════════════════════════════════════════
# MAIN ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════

def analyze_x86():
    print("=" * 80)
    print("  X86 UUPLUGIN — FULL DISASSEMBLY ANALYSIS")
    print("=" * 80)
    
    elf = parse_elf(open(X86_PATH, 'rb').read())
    print(f"\n  Arch: {'x86_64' if elf['is_64'] else 'x86'}")
    print(f"  Entry: 0x{elf['entry']:x}")
    
    for name, sec in elf['sections'].items():
        if sec['size'] > 1024:
            print(f"  Section {name}: VA=0x{sec['va']:x} file_off=0x{sec['file_off']:x} size=0x{sec['size']:x}")
    
    # ── 1. Find all key strings and their cross-references ──
    print("\n" + "=" * 80)
    print("  STRING CROSS-REFERENCE ANALYSIS")
    print("=" * 80)
    
    key_strings = [
        b'UU_VENDOR', b'UU_MODEL', b'UU_SN', b'UU_LAN_NAME',
        b'UU_PLUGIN_VESION', b'UU_FIRMWARE_VERSION', b'UU_LAN_IP', b'UU_WAN_IP',
        b'from_file', b'unmatched sn', b'OpenWrt', b'router.cpp',
        b'openwrt-x86_64', b'/usr/sbin/uu/.sn', b'.sn', b'/var/model',
        b'getenv', b'getenv\0',  # C library function
    ]
    
    for ks in key_strings:
        xrefs = find_xrefs_to_string(elf, ks)
        if xrefs:
            print(f"\n  [{ks.decode(errors='replace')}] {len(xrefs)} xrefs:")
            for xr in xrefs[:8]:
                print(f"    {xr['type']:15s} at file 0x{xr['file_off']:06x}  (VA 0x{xr['va']:x})")
    
    # ── 2. Detailed analysis of from_file string references ──
    print("\n" + "=" * 80)
    print("  'from_file' STRING — DETAILED CONTEXT")
    print("=" * 80)
    
    for pos, ctx in find_all_strings(elf['data'], b'from_file'):
        print(f"\n  File offset: 0x{pos:08x}")
        print(f"  Context: {printable_ctx(ctx)}")
    
    # ── 3. Find and analyze the from_file logging function ──
    print("\n" + "=" * 80)
    print("  FUNCTIONS USING 'from_file' — DISASSEMBLY")
    print("=" * 80)
    
    xrefs = find_xrefs_to_string(elf, b'from_file')
    for xr in xrefs:
        print(f"\n  --- Reference at file 0x{xr['file_off']:06x} ---")
        insns = disasm_context(elf, xr['file_off'], before_bytes=150, after_bytes=80)
        for insn in insns:
            marker = " <--" if insn.address == xr['file_off'] else ""
            print(f"    0x{insn.address:06x}: {insn.mnemonic:10s} {insn.op_str}{marker}")
    
    # ── 4. Find the getenv calls ──
    print("\n" + "=" * 80)
    print("  CALLS TO getenv() — ENV VAR READING")
    print("=" * 80)
    
    # Instead of searching for "getenv" string, search for PLT entries
    # In the .plt section, find the getenv stub
    plt = elf['sections'].get('.plt', {})
    if plt:
        # Disassemble PLT to find getenv
        insns = disasm_x86_range(elf, plt['file_off'], plt['file_off'] + plt['size'])
        getenv_plt_addr = None
        for insn in insns:
            if insn.mnemonic == 'jmp' and 'getenv' in insn.op_str:
                getenv_plt_addr = insn.address
                print(f"  getenv@PLT at VA 0x{insn.address:x} (file 0x{insn.address:x})")
                break
        
        # Search for calls to getenv
        text = elf['sections'].get('.text', {})
        text_data = text['data']
        text_va = text['va']
        text_off = text['file_off']
        
        if getenv_plt_addr:
            # call rel32: E8 XX XX XX XX
            # Find all call instructions in .text
            md = Cs(CS_ARCH_X86, CS_MODE_64)
            md.detail = True
            
            # Read .plt.sec or .rela.plt to find GOT entries
            # Alternative: disassemble .text and look for calls
            print("\n  Searching .text for calls to getenv...")
            
            # Get getenv GOT entry from PLT stub disassembly
            # First bytes of PLT stub should be: ff 25 XX XX XX XX (jmp [rip+offset])
            plt_stub_data = elf['data'][getenv_plt_addr:getenv_plt_addr+16]
            if plt_stub_data[:2] == b'\xff\x25':
                got_offset = struct.unpack('<i', plt_stub_data[2:6])[0]
                got_addr = getenv_plt_addr + 6 + got_offset
                print(f"  getenv GOT entry at VA 0x{got_addr:x}")
                
                # Search .text for calls to getenv PLT
                call_target_bytes = struct.pack('<i', getenv_plt_addr)  # This won't work—need relative offset
                
                # Better approach: search for E8 followed by relative offset to getenv PLT
                target_plt = getenv_plt_addr
                call_count = 0
                for idx in range(0, len(text_data) - 5, 1):
                    if text_data[idx] == 0xE8:  # call rel32
                        rel32 = struct.unpack('<i', text_data[idx+1:idx+5])[0]
                        target = text_va + idx + 5 + rel32
                        if target == target_plt:
                            file_off = text_off + idx
                            print(f"\n  call getenv at file 0x{file_off:x} (VA 0x{text_va + idx:x})")
                            call_count += 1
                            if call_count < 20:
                                # Show surrounding context
                                insns = disasm_context(elf, file_off, before_bytes=60, after_bytes=40)
                                for insn in insns:
                                    marker = " <-- CALL getenv" if insn.address == file_off else ""
                                    print(f"    0x{insn.address:06x}: {insn.mnemonic:10s} {insn.op_str}{marker}")
                            if call_count >= 30:
                                print(f"  ... (showing first 20 of many calls)")
                                break
                print(f"\n  Total calls to getenv: {call_count}")
    
    # ── 5. Search for specific constant patterns that identify from_file variable ──
    print("\n" + "=" * 80)
    print("  SEARCHING FOR from_file VARIABLE ASSIGNMENT")
    print("=" * 80)
    
    # from_file is likely a boolean variable. Look for patterns like:
    # - cmp [var], 0 / cmp [var], 1
    # - mov [var], 0 / mov [var], 1
    # near the "unmatched sn" log
    unmatched_refs = find_xrefs_to_string(elf, b'unmatched sn')
    if unmatched_refs:
        print("\n  'unmatched sn' references:")
        for xr in unmatched_refs:
            print(f"\n  --- Reference at file 0x{xr['file_off']:06x} ---")
            insns = disasm_context(elf, xr['file_off'], before_bytes=300, after_bytes=100)
            for insn in insns:
                marker = " <-- STRING REF" if insn.address == xr['file_off'] else ""
                print(f"    0x{insn.address:06x}: {insn.mnemonic:10s} {insn.op_str}{marker}")

    # ── 6. Find the model string and how it's used ──
    print("\n" + "=" * 80)
    print("  MODEL STRING ANALYSIS ('openwrt-x86_64')")
    print("=" * 80)
    
    for pos, ctx in find_all_strings(elf['data'], b'openwrt-x86_64'):
        print(f"\n  'openwrt-x86_64' at file 0x{pos:08x}")
        print(f"  Context: {printable_ctx(ctx, 200)}")
    
    model_xrefs = find_xrefs_to_string(elf, b'openwrt-x86_64')
    if model_xrefs:
        print(f"\n  {len(model_xrefs)} references to 'openwrt-x86_64':")
        for xr in model_xrefs:
            print(f"    {xr['type']} at file 0x{xr['file_off']:06x}")
            insns = disasm_context(elf, xr['file_off'], before_bytes=80, after_bytes=60)
            for insn in insns:
                marker = " <-- MODEL STR" if insn.address == xr['file_off'] else ""
                print(f"      0x{insn.address:06x}: {insn.mnemonic:10s} {insn.op_str}{marker}")
    
    # ── 7. Cross-check: find what path NX30Pro uses vs x86 ──
    print("\n" + "=" * 80)
    print("  COMPARISON: MODEL/SN PATHS")
    print("=" * 80)
    
    print("\n  NX30Pro (aarch64):")
    nx30_data = open(NX30_PATH, 'rb').read() if os.path.exists(NX30_PATH) else b''
    for kw in [b'h3c-nx30pro', b'h3c_info', b'factoryinfo', b'/var/model']:
        for pos, ctx in find_all_strings(nx30_data, kw):
            print(f"    [{kw.decode()}] at 0x{pos:08x}: {printable_ctx(ctx, 120)}")
    
    print("\n  x86:")
    for kw in [b'openwrt-x86_64', b'/usr/sbin/uu/.sn', b'/var/model', b'.sn']:
        for pos, ctx in find_all_strings(elf['data'], kw):
            print(f"    [{kw.decode()}] at 0x{pos:08x}: {printable_ctx(ctx, 120)}")


if __name__ == '__main__':
    analyze_x86()
