#!/usr/bin/env python3
"""Deep dive into NX30Pro binary's TLS and registration code."""
import os, re
from collections import defaultdict

H3C_PATH = r"d:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin"
X86_PATH = r"d:\code03\uugamebooster-docker\bin\uuplugin"

def get_all_strings(data, min_len=3):
    """Extract all printable strings."""
    strings = set()
    current = b''
    for b in data:
        if 32 <= b < 127:
            current += bytes([b])
            if len(current) >= min_len:
                strings.add(current.decode('ascii'))
        else:
            current = b''
    return strings

def search_keywords(strings, keywords):
    """Search for strings containing any keyword."""
    results = defaultdict(list)
    for s in strings:
        for kw in keywords:
            if kw.lower() in s.lower():
                results[kw].append(s)
    return results

# TLS/mTLS related keywords
TLS_KEYWORDS = [
    'SSL_CTX_use_certificate', 'SSL_CTX_use_PrivateKey',
    'SSL_CTX_load_verify', 'PEM_read_', 'X509_',
    'cert.pem', 'key.pem', 'client_cert', 'ca_cert',
    '/etc/ssl', '/usr/lib/ssl', 'certificate', 'private_key',
    'SSL_CTX_set_verify', 'SSL_VERIFY_PEER',
    'mTLS', 'mutual', 'client auth',
    # Registration related
    'register', 'login', 'auth_req', 'cert_req',
    'h3c_info', 'factoryinfo', 'from_file',
    # Protocol
    'protobuf', '.proto', 'serialize',
    # Device identity
    'productname', 'manucode', 'hardversion', 'bootversion', 'ethaddr',
    'uu_model', 'UU_MODEL', 'uu_product',
]

print("=" * 70)
print("  DEEP TLS & REGISTRATION ANALYSIS")
print("=" * 70)

for path, label in [(H3C_PATH, "H3C NX30Pro"), (X86_PATH, "x86 Container")]:
    if not os.path.exists(path):
        print(f"\n[SKIP] {label}: not found")
        continue
    
    with open(path, 'rb') as f:
        data = f.read()
    
    strings = get_all_strings(data, min_len=4)
    results = search_keywords(strings, TLS_KEYWORDS)
    
    print(f"\n{'─'*70}")
    print(f"  {label} ({len(data):,} bytes)")
    print(f"{'─'*70}")
    
    for kw, matches in sorted(results.items()):
        print(f"\n  [{kw}] ({len(matches)} matches):")
        for m in sorted(set(matches))[:10]:
            print(f"    {m}")

# ── Look specifically for certificate/key loading functions ──
print(f"\n{'='*70}")
print("  LOOKING FOR mTLS / CLIENT CERT SUPPORT")
print(f"{'='*70}")

for path, label in [(H3C_PATH, "H3C NX30Pro"), (X86_PATH, "x86 Container")]:
    if not os.path.exists(path):
        continue
    
    with open(path, 'rb') as f:
        data = f.read()
    
    strings = get_all_strings(data, min_len=3)
    
    # Critical mTLS indicators
    critical = [
        'SSL_CTX_use_certificate', 'SSL_CTX_use_PrivateKey',
        'SSL_CTX_use_certificate_chain', 'SSL_set_client_cert_cb',
        'PEM_read_X509', 'PEM_read_PrivateKey', 'PEM_read_bio_X509',
        'd2i_X509', 'd2i_PrivateKey',
    ]
    
    print(f"\n  {label}:")
    for kw in critical:
        for s in strings:
            if kw in s:
                print(f"    FOUND: {s}")
                break
        else:
            # Also check for partial matches
            partial_matches = [s for s in strings if any(p in s for p in kw.split('_')[:3])]
            if partial_matches:
                print(f"    PARTIAL: {kw} -> {partial_matches[:3]}")

# ── Look for function names related to registration ──
print(f"\n{'='*70}")
print("  REGISTRATION FUNCTION NAMES")
print(f"{'='*70}")

for path, label in [(H3C_PATH, "H3C NX30Pro"), (X86_PATH, "x86 Container")]:
    if not os.path.exists(path):
        continue
    
    with open(path, 'rb') as f:
        data = f.read()
    
    strings = get_all_strings(data, min_len=5)
    
    # Look for function-like names
    func_patterns = re.findall(rb'[a-z_][a-z0-9_]{5,}(?:register|login|connect|auth|cert|device|init)', data, re.IGNORECASE)
    func_names = set()
    for m in func_patterns:
        try:
            s = m.decode('ascii')
            if '_' in s and not s.startswith('/'):
                func_names.add(s)
        except:
            pass
    
    if func_names:
        print(f"\n  {label} ({len(func_names)} funcs):")
        for f in sorted(func_names)[:30]:
            print(f"    {f}")

print("\nDone.")
