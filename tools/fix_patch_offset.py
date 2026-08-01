#!/usr/bin/env python3
"""Verify and fix UU_SN patch offset."""
data = open(r"d:\code03\uugamebooster-docker\bin\uuplugin", "rb").read()

# Find exact UU_SN location
idx = data.find(b'UU_VENDOR')
print(f"UU_VENDOR at 0x{idx:08x}")

# Sequence: UU_VENDOR\0UU_MODEL\0UU_SN\0UU_PLUGIN_VESION\0...
vend_end = idx + 9  # UU_VENDOR + null
model_start = vend_end + 1
print(f"UU_MODEL at 0x{model_start:08x}: {data[model_start:model_start+10]}")

sn_start = model_start + 9  # UU_MODEL\0 + after null
print(f"UU_SN at 0x{sn_start:08x}: {data[sn_start:sn_start+8]}")
print(f"  Correct patch offset: {sn_start} (0x{sn_start:08x})")

# Wrong location from Dockerfile
wrong = 4095722
print(f"\nDockerfile patch offset: {wrong} (0x{wrong:08x})")
print(f"  Bytes at wrong loc: {data[wrong:wrong+10].hex()}")
ctx = data[wrong-20:wrong+30]
ctx_p = ''.join(chr(b) if 32<=b<127 else '.' for b in ctx)
print(f"  Context: ...{ctx_p}...")

print(f"\nDifference: {wrong - sn_start} bytes off!")

# What the correct offset should be for each env var
print("\n=== CORRECT PATCH PLAN ===")
env_vars = [
    ("UU_VENDOR", idx, "XX_VENDOR"),
    ("UU_MODEL", model_start, "XX_MODEL"),
    ("UU_SN", sn_start, "XX_SN"),
]
# Find UU_PLUGIN_VESION (after UU_SN\0)
plug_start = sn_start + 5 + 1  # UU_SN\0
print(f"UU_PLUGIN_VESION at 0x{plug_start:08x}: {data[plug_start:plug_start+18]}")
env_vars.append(("UU_PLUGIN_VESION", plug_start, "XX_PLUGIN_VESION_XX"))

# Find UU_FIRMWARE_VERSION (after UU_PLUGIN_VESION\0)
fw_start = plug_start + 15 + 1
print(f"UU_FIRMWARE_VERSION at 0x{fw_start:08x}: {data[fw_start:fw_start+25]}")
env_vars.append(("UU_FIRMWARE_VERSION", fw_start, "XX_FIRMWARE_VERSION_XX"))

# Find UU_LAN_NAME
lan_start = fw_start + 20 + 1
print(f"UU_LAN_NAME at 0x{lan_start:08x}: {data[lan_start:lan_start+15]}")
env_vars.append(("UU_LAN_NAME", lan_start, "XX_LAN_NAME_XXX"))

print("\n=== PATCH COMMANDS ===")
for name, off, replacement in env_vars:
    replacement = replacement[:len(name)]  # same length
    print(f"printf '{replacement}' | dd of=uuplugin bs=1 seek={off} conv=notrunc  # {name} -> {replacement}")
