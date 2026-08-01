#!/usr/bin/env python3
"""
Deep analysis of from_file logic.
1. Decode XOR-obfuscated strings
2. Disassemble the key model-detection function
3. Trace from_file variable flow
"""
import struct
from capstone import *
from capstone.x86 import *

X86_PATH = r"d:\code03\uugamebooster-docker\bin\uuplugin"

data = open(X86_PATH, 'rb').read()

# ═══════════════════════════════════════════════════════════════════
# 1. Decode XOR-obfuscated strings
# ═══════════════════════════════════════════════════════════════════

print("=" * 70)
print("  XOR OBFUSCATION ANALYSIS")
print("=" * 70)

# The pattern "P|{{rp" = 50 7c 7b 7b 72 70 appears before many paths
# Let's look at the surrounding bytes to find the key
# If we XOR with known plaintext like "openwrt-x86_64":
enc = data[0x003e6d5f:0x003e6d5f + 14]  # openwrt-x86_64 location
print(f"\n  Known: 'openwrt-x86_64' at 0x003e6d5f")
print(f"  Raw: {enc}")

# Look at the pattern near openwrt
ctx = data[0x003e6d40:0x003e6d90]
print(f"\n  Context around 'openwrt-x86_64':")
print(f"  Raw: {ctx}")
print(f"  Printable: {''.join(chr(b) if 32<=b<127 else '.' for b in ctx)}")

# The structure seems: [obfuscated_path].[plaintext_model].[obfuscated_path]
# Pattern before "openwrt-x86_64": ...2q/./P|{{rp"-!{-2!/./P|{{rp"-z|qry-2!/.openwrt-x86_64./P|{{rp"-"'r-2!/...
# Let me extract the obfuscated strings and try to decode them

# Key insight: "P|{{rp" appears as prefix. If we look at known patterns:
# - Paths start with "/" (0x2F)
# - "P" (0x50) XOR with something gives "/" (0x2F)
# 0x50 ^ 0x2F = 0x7F
# "|" (0x7C) XOR with something gives "v" (0x76)? No - these are path chars

# Let me try: "P|{{rp" decoded:
# If first char is '/': key = 0x50 ^ 0x2F = 0x7f
# Then: '|' (0x7C) ^ 0x7F = 0x03 (not printable)
# So single-byte XOR key doesn't work

# Try multi-byte: "P|{{rp" is 50 7c 7b 7b 72 70
# This might be a prefix marker, not XOR key

# Let's look at the bytes BEFORE each obfuscated path
# Looking at the format more carefully, each path segment is: 0x2f + obfuscated + 0x2f
# That 0x2f is '/' (path separator)

# Let me find the deobfuscation function in the code
# Search for the XOR pattern or decoding routine

# Actually, let me trace the function that reads these strings
# The getenv function is called by the binary. Let me find the string deobfuscation

# Look for the function that references "P|{{rp" pattern
pidx = data.find(b'P|{{rp')
print(f"\n  'P|{{rp' pattern first at: 0x{pidx:08x}")

# ═══════════════════════════════════════════════════════════════════
# 2. Disassemble the model detection function
# ═══════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  MODEL DETECTION FUNCTION (0x447f00 - 0x449000)")
print("=" * 70)

md = Cs(CS_ARCH_X86, CS_MODE_64)
md.detail = True

# Find function start - scan backward from 0x4486d3 (first UU_VENDOR ref)
# The function contains all UU_* getenv calls in sequence
# Function boundaries: entry at 0x447ec0? Let's find the right entry
# We'll disassemble a wider range and look for the big function

code = data[0x447e00:0x449300]
base = 0x447e00
all_insns = list(md.disasm(code, base))

# Print the entire function
print("\n  Full function disassembly (key instructions):")
for insn in all_insns:
    marker = ""
    op_str = insn.op_str
    
    # Mark important instructions
    if insn.address in [0x4486d3, 0x4486e9, 0x4486ff, 0x448715, 
                         0x44872b, 0x448741, 0x448776, 0x4487bf]:
        # These are the getenv calls for UU_* vars
        marker = " <-- getenv(UU_*)"
    elif insn.address == 0x4481ec:
        marker = " <-- fallback model 'openwrt-x86_64'"
    elif 'call' in insn.mnemonic:
        # Check if it's calling getenv
        marker = ""
    
    if any(kw in (insn.mnemonic + ' ' + op_str).lower() 
           for kw in ['call', 'cmp', 'test', 'je', 'jne', 'jmp', 'jz', 'jnz',
                       'mov edi', 'mov esi', 'ret', 'push rbp', 'mov rbp']):
        # Shorten long op_str
        if len(op_str) > 45:
            op_str = op_str[:42] + "..."
        print(f"  0x{insn.address:06x}: {insn.mnemonic:8s} {op_str:45s}{marker}")

# ═══════════════════════════════════════════════════════════════════
# 3. Analyze the .sn reading function
# ═══════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  .sn FILE READING FUNCTION (0x47d200 - 0x47da00)")
print("=" * 70)

code2 = data[0x47d200:0x47da00]
base2 = 0x47d200
all_insns2 = list(md.disasm(code2, base2))

print("\n  Function around /usr/sbin/uu/.sn reference:")
for insn in all_insns2:
    marker = ""
    op_str = insn.op_str
    if insn.address in [0x47d2f4, 0x47d88d]:
        marker = " <-- '/usr/sbin/uu/.sn'"
    
    if any(kw in (insn.mnemonic + ' ' + op_str).lower() 
           for kw in ['call', 'cmp', 'test', 'je', 'jne', 'jmp', 'jz', 'jnz',
                       'mov edi', 'mov esi', 'ret', 'push rbp', 'mov rbp']):
        if len(op_str) > 45:
            op_str = op_str[:42] + "..."
        print(f"  0x{insn.address:06x}: {insn.mnemonic:8s} {op_str:45s}{marker}")

# ═══════════════════════════════════════════════════════════════════
# 4. Search for "from_file" related constants
# ═══════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  SEARCHING FOR from_file VARIABLE ASSIGNMENTS")
print("=" * 70)

# from_file is likely a global/static variable in .bss or .data
# Let's search for patterns like: mov [var], 0 or mov [var], 1
# that appear before the "unmatched sn" related code

# Since "unmatched sn" is obfuscated, let's look for the function
# that calls the logging with FATAL level

# Search for references to the FATAL log format string
fatal_ref = data.find(b'FATAL')
print(f"\n  FATAL string at: 0x{fatal_ref:08x}")

# Now find all references to the FATAL string address in code
# First, find the .rodata section to calculate VA
# Parse ELF sections
e_shoff = struct.unpack('Q', data[40:48])[0]
e_shentsize = struct.unpack('H', data[58:60])[0]
e_shnum = struct.unpack('H', data[60:62])[0]
e_shstrndx = struct.unpack('H', data[62:64])[0]

shstr_off = e_shoff + e_shstrndx * e_shentsize
shstr_sh_off = struct.unpack('Q', data[shstr_off+24:shstr_off+32])[0]
shstr_sh_size = struct.unpack('Q', data[shstr_off+32:shstr_off+40])[0]
shstrtab = data[shstr_sh_off:shstr_sh_off+shstr_sh_size]

rodata_va = 0
rodata_off = 0
text_va = 0
text_off = 0
for i in range(e_shnum):
    sh_off = e_shoff + i * e_shentsize
    sh_name_off = struct.unpack('I', data[sh_off:sh_off+4])[0]
    sh_name = shstrtab[sh_name_off:shstrtab.find(b'\0', sh_name_off)].decode(errors='replace')
    sh_addr = struct.unpack('Q', data[sh_off+16:sh_off+24])[0]
    sh_fileoff = struct.unpack('Q', data[sh_off+24:sh_off+32])[0]
    if sh_name == '.rodata':
        rodata_va = sh_addr
        rodata_off = sh_fileoff
    elif sh_name == '.text':
        text_va = sh_addr
        text_off = sh_fileoff

# FATAL VA
fatal_va = rodata_va + (fatal_ref - rodata_off)
print(f"  FATAL VA: 0x{fatal_va:x}")

# Find references to FATAL in .text
text_data = data[text_off:text_off + 0x400000]
fatal_va_low = fatal_va & 0xFFFFFFFF

# Search for mov edi, FATAL_VA (BF XX XX XX XX)
target = b'\xBF' + struct.pack('<I', fatal_va_low)
fatal_xrefs = []
idx = 0
while True:
    idx = text_data.find(target, idx)
    if idx == -1:
        break
    fatal_xrefs.append(text_off + idx)
    idx += 1

print(f"\n  References to FATAL string (mov edi): {len(fatal_xrefs)}")
for fx in fatal_xrefs[:10]:
    print(f"    at file 0x{fx:06x} (VA 0x{text_va + (fx - text_off):x})")

# ═══════════════════════════════════════════════════════════════════
# 5. THE KEY INSIGHT: Model override logic
# ═══════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("  KEY INSIGHT: MODEL OVERRIDE FLOW")
print("=" * 70)

print("""
The x86 binary works like this:

1. INITIALIZATION (function at ~0x447ec0):
   - First, calls getenv("UU_MODEL") 
   - If UU_MODEL is set → use it as model, set from_file=0
   - If UU_MODEL NOT set → use hardcoded "openwrt-x86_64", set from_file=1

2. SN READING:
   - from_file=1: read SN from /usr/sbin/uu/.sn file
   - from_file=0: read SN from getenv("UU_SN")

3. The CRITICAL BUG:
   - When from_file=0, the SN from env var goes through validation 
   - The validation FAILS because it expects a specific format
   - Result: "unmatched sn, from_file: 0" FATAL

4. SOLUTION A (model string patch):
   - Patch "openwrt-x86_64" → "h3c-nx30pro" everywhere
   - Also need to make from_file=1 (remove env vars)
   
5. SOLUTION B (from_file logic patch):
   - Find the comparison that sets from_file and hardcode it to 1
""")

# 6. Find the exact comparison that sets from_file
print("\n" + "=" * 70)
print("  ANALYZING FUNCTION RETURN VALUES (getenv results)")
print("=" * 70)

# The code pattern at 0x4481ec:
#   cmp rdi, 0xb47e00
#   je ...
#   mov esi, 0x7e6d5f  (openwrt-x86_64)
#   call some_function
# 
# 0xb47e00 is in .bss range (0xb44cc0 - 0xb55da0)
# It might be a sentinel value for "no result" or an empty string address

# Let's check what 0xb47e00 is
bss_start = 0xb44cc0
print(f"\n  .bss VA range: 0x{bss_start:x} - 0x{bss_start + 0xb0e0:x}")
print(f"  0xb47e00 is in .bss (offset {0xb47e00 - bss_start} into .bss)")

# This might be a static object address (like an empty std::string)
print("\n  Key question: what does getenv return when var is not set?")
print("  - Returns NULL (0)")
print("  - Binary compares with 0xb47e00 (a .bss address)")
print("  - If equal → env var NOT set → use fallback model")
print("  - If NOT equal → env var IS set → use it (from_file=0)")

print("\n" + "=" * 70)
print("  ANALYSIS COMPLETE")
print("=" * 70)
