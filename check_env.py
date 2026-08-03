import re, sys

binary = open(sys.argv[1], 'rb').read()
start_sh = open(sys.argv[2], 'r').read()

# extract all printable strings 3-40 chars from binary
strings = set()
cur = b''
for b in binary:
    if 32 <= b < 127:
        cur += bytes([b])
    else:
        if 3 <= len(cur) <= 40:
            strings.add(cur.decode('ascii', errors='ignore'))
        cur = b''

# filter: strings that look like getenv() arguments (ALL_CAPS with underscores)
env_candidates = sorted(s for s in strings if re.match(r'^[A-Z][A-Z0-9_]{2,39}$', s))

# find which ones are EXPORTed in start.sh
exported = set(re.findall(r'export\s+(\w+)', start_sh))

print(f"Total env-candidate strings in binary: {len(env_candidates)}")
print(f"Total exports in start.sh: {len(exported)}")
print()

missing = [s for s in env_candidates if s not in exported]
if missing:
    print("MISSING (in binary but NOT exported):")
    for s in missing:
        print(f"  {s}")
else:
    print("All env-style strings are exported.")

# Also show all UU_* strings
uu_strings = [s for s in strings if s.startswith('UU_')]
print(f"\nAll UU_* strings in binary ({len(uu_strings)}):")
for s in sorted(uu_strings):
    status = "EXPORTED" if s in exported else "MISSING"
    print(f"  {s:40s} {status}")
