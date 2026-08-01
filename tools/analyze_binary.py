#!/usr/bin/env python3
"""
Deep binary analysis for UU plugin binaries.
Extracts protocol messages, certificates, authentication flows, and configuration.
"""

import os, struct, re, sys
from collections import defaultdict

BIN_X86 = r"d:\code03\uugamebooster-docker\bin\uuplugin"
BIN_H3C = r"d:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin"

def get_strings(data, min_len=4):
    """Extract all printable ASCII strings from binary data."""
    strings = set()
    current = b''
    for byte in data:
        if 32 <= byte < 127:
            current += bytes([byte])
            if len(current) >= min_len:
                strings.add(current.decode('ascii'))
        else:
            current = b''
    return sorted(strings, key=len, reverse=True)

def find_in_binary(data, pattern, context=50):
    """Find pattern in binary and return surrounding context."""
    results = []
    if isinstance(pattern, str):
        pattern = pattern.encode('ascii')
    pos = 0
    while True:
        idx = data.find(pattern, pos)
        if idx == -1:
            break
        start = max(0, idx - context)
        end = min(len(data), idx + len(pattern) + context)
        chunk = data[start:end]
        # Show hex and ASCII
        hex_str = chunk.hex()
        ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
        results.append((idx, hex_str, ascii_str))
        pos = idx + 1
    return results

def categorize_strings(strings):
    """Categorize extracted strings."""
    cats = defaultdict(list)
    
    # Common keywords
    patterns = {
        'cert': ['BEGIN CERTIFICATE', 'PRIVATE KEY', '.pem', '.crt', '.key', 'certificate', 'x509'],
        'protobuf': ['Req', 'Res', 'Request', 'Response', '.proto'],
        'tls': ['SSL', 'TLS', 'ssl_ctx', 'SSL_CTX', 'openssl', 'cipher'],
        'url': ['uu.163.com', 'uu.netease', 'netease', 'router.uu', 'uurouter'],
        'auth': ['auth', 'login', 'bind', 'token', 'secret', 'password', 'username', 'credential'],
        'device': ['manucode', 'factoryinfo', 'h3c_info', 'productname', 'from_file', 'hardversion', 'ethaddr'],
        'config': ['/etc/', '/var/', '/tmp/', '/proc/', '/usr/'],
        'ssh': ['SSH', 'dropbear', 'authorized_keys', 'shadow', 'passwd', 'chpasswd'],
        'version': ['v14.', 'v13.', 'v15.', 'version='],
    }
    
    for s in strings:
        for cat, keywords in patterns.items():
            for kw in keywords:
                if kw.lower() in s.lower():
                    cats[cat].append(s)
                    break
    
    return cats

def extract_protobuf_schemas(strings):
    """Try to extract protobuf message schemas from strings."""
    pb_re = re.compile(r'^[A-Z][A-Za-z]{2,}(Req|Res|Request|Response|Msg|Info|Data)$')
    schemas = [s for s in strings if pb_re.match(s)]
    return sorted(set(schemas))

def analyze_elf_sections(path):
    """Check ELF sections for embedded data."""
    with open(path, 'rb') as f:
        data = f.read()
    
    # Check for .rodata, .data sections (approximate)
    # Look for common data patterns
    results = {}
    
    # Find all offsets of specific patterns
    for name, pattern in [
        ('PEM_cert', b'-----BEGIN CERTIFICATE-----'),
        ('PEM_key', b'-----BEGIN PRIVATE KEY-----'),
        ('EC_KEY', b'-----BEGIN EC'),
        ('RSA_KEY', b'-----BEGIN RSA'),
    ]:
        offsets = find_in_binary(data, pattern)
        if offsets:
            results[name] = len(offsets)
    
    return results

def compare_binaries(h3c_path, x86_path):
    """Compare two binaries for differences."""
    with open(h3c_path, 'rb') as f:
        h3c_data = f.read()
    with open(x86_path, 'rb') as f:
        x86_data = f.read()
    
    h3c_strings = set(get_strings(h3c_data))
    x86_strings = set(get_strings(x86_data))
    
    h3c_only = h3c_strings - x86_strings
    x86_only = x86_strings - h3c_strings
    common = h3c_strings & x86_strings
    
    return h3c_only, x86_only, common

def main():
    print("=" * 80)
    print("  UU BINARY DEEP ANALYSIS")
    print("=" * 80)
    
    for path, label in [(BIN_H3C, "H3C NX30Pro v14.4.20"), (BIN_X86, "x86 Container")]:
        if not os.path.exists(path):
            print(f"\n[SKIP] {label}: file not found at {path}")
            continue
            
        with open(path, 'rb') as f:
            data = f.read()
        
        print(f"\n{'─' * 80}")
        print(f"  {label}  ({len(data):,} bytes)")
        print(f"{'─' * 80}")
        
        strings = get_strings(data, min_len=4)
        cats = categorize_strings(strings)
        
        # 1. Certificates
        if cats['cert']:
            print("\n  [CERTIFICATES / KEYS]")
            for s in sorted(set(cats['cert'])):
                print(f"    {s}")
        
        # 2. Protobuf messages
        pb = extract_protobuf_schemas(strings)
        if pb:
            print(f"\n  [PROTOBUF MESSAGES] ({len(pb)} found)")
            for s in pb:
                print(f"    {s}")
        
        # 3. TLS/SSL
        if cats['tls']:
            print("\n  [TLS/SSL]")
            for s in sorted(set(cats['tls']))[:15]:
                print(f"    {s}")
        
        # 4. URLs
        if cats['url']:
            print("\n  [URLs / ENDPOINTS]")
            for s in sorted(set(cats['url'])):
                print(f"    {s}")
        
        # 5. Auth
        if cats['auth']:
            print("\n  [AUTHENTICATION]")
            for s in sorted(set(cats['auth']))[:20]:
                print(f"    {s}")
        
        # 6. Device info
        if cats['device']:
            print("\n  [DEVICE INFO]")
            for s in sorted(set(cats['device'])):
                print(f"    {s}")
        
        # 7. Config paths
        if cats['config']:
            print("\n  [CONFIG PATHS]")
            for s in sorted(set(cats['config']))[:15]:
                print(f"    {s}")
        
        # 8. SSH
        if cats['ssh']:
            print("\n  [SSH / PASSWORD]")
            for s in sorted(set(cats['ssh'])):
                print(f"    {s}")
        
        # 9. Check for embedded PEM blocks
        print("\n  [EMBEDDED PEM SEARCH]")
        certs = find_in_binary(data, b'-----BEGIN')
        if certs:
            for offset, hex_str, ascii_str in certs:
                print(f"    Offset 0x{offset:08x}:")
                # Show the PEM data
                pem_start = ascii_str.find('-----BEGIN')
                if pem_start >= 0:
                    print(f"      {ascii_str[pem_start:pem_start+80]}")
        else:
            print("    (none found)")
    
    # ── COMPARISON ──
    print(f"\n{'=' * 80}")
    print("  COMPARISON: H3C vs x86")
    print(f"{'=' * 80}")
    
    if os.path.exists(BIN_H3C) and os.path.exists(BIN_X86):
        h3c_only, x86_only, common = compare_binaries(BIN_H3C, BIN_X86)
        
        print(f"\n  H3C only ({len(h3c_only)} strings):")
        for s in sorted(h3c_only, key=len, reverse=True)[:30]:
            print(f"    {s}")
        
        print(f"\n  x86 only ({len(x86_only)} strings):")
        for s in sorted(x86_only, key=len, reverse=True)[:30]:
            print(f"    {s}")
        
        # Key differences
        print(f"\n  [KEY DIFFERENCES]")
        h3c_proto = extract_protobuf_schemas(h3c_only)
        x86_proto = extract_protobuf_schemas(x86_only)
        if h3c_proto:
            print(f"    H3C-specific protobuf: {h3c_proto}")
        if x86_proto:
            print(f"    x86-specific protobuf: {x86_proto}")

if __name__ == "__main__":
    main()
