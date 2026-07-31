#!/usr/bin/env python3
"""
UU H3C Registration MITM Proxy — Full Bidirectional Decrypt
Accepts TLS from container (fake cert), connects to real H3C server,
relays data both ways and logs ALL plaintext.

Usage:
  1. Ensure fake_h3c_cert.pem + fake_h3c_key.pem exist in this dir
  2. Run: python mitm_server.py
  3. In container: redirect DNS to this machine's IP
  4. Kill uuplugin to force reconnect
"""

import socket
import ssl
import os
import sys
import select
import threading
from datetime import datetime

# ── Configuration ───────────────────────────────────────────────────────────
LISTEN_HOST = '0.0.0.0'
LISTEN_PORT = 16000
REAL_HOST = '42.186.111.127'   # h3crglg.uu.163.com real IP
REAL_PORT = 16000

CERT_FILE = os.path.join(os.path.dirname(__file__), 'fake_h3c_cert.pem')
KEY_FILE = os.path.join(os.path.dirname(__file__), 'fake_h3c_key.pem')

# ── Check cert files ───────────────────────────────────────────────────────
if not os.path.exists(CERT_FILE):
    print(f"[FATAL] Certificate file not found: {CERT_FILE}")
    print(f"        Generate: docker exec UUgamebooster openssl req -x509 -newkey rsa:2048 \\")
    print(f"          -nodes -keyout /tmp/key.pem -out /tmp/cert.pem -days 365 \\")
    print(f'          -subj "/CN=rglg.uu.163.com" \\')
    print(f'          -addext "subjectAltName=DNS:rglg.uu.163.com,DNS:rglg.uu.netease.com"')
    print(f"        docker cp UUgamebooster:/tmp/cert.pem tools/fake_h3c_cert.pem")
    print(f"        docker cp UUgamebooster:/tmp/key.pem tools/fake_h3c_key.pem")
    sys.exit(1)

# ── TLS Contexts ────────────────────────────────────────────────────────────
# Server-side: accept from container with our fake cert
server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server_ctx.load_cert_chain(CERT_FILE, KEY_FILE)
server_ctx.verify_mode = ssl.CERT_NONE
server_ctx.check_hostname = False
server_ctx.minimum_version = ssl.TLSVersion.TLSv1
server_ctx.maximum_version = ssl.TLSVersion.TLSv1_2

# Client-side: connect to real server (no cert verification)
client_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
client_ctx.check_hostname = False
client_ctx.verify_mode = ssl.CERT_NONE
client_ctx.minimum_version = ssl.TLSVersion.TLSv1
client_ctx.maximum_version = ssl.TLSVersion.TLSv1_2

# ── Utility ─────────────────────────────────────────────────────────────────
def hexdump(data, label="DATA", indent=2):
    prefix = " " * indent
    lines = []
    for i in range(0, len(data), 32):
        chunk = data[i:i+32]
        hex_part = ' '.join(f'{b:02x}' for b in chunk)
        ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
        lines.append(f"{prefix}{i:04x}: {hex_part:<96s} |{ascii_part}|")
    return '\n'.join(lines)

def decode_text(data):
    """Try to extract readable text/protobuf/JSON from binary data."""
    results = []
    try:
        text = data.decode('utf-8')
        # Extract printable runs
        import re
        runs = re.findall(r'[\x20-\x7E]{4,}', text)
        for r in runs:
            if len(r) >= 4:
                results.append(f"    [TEXT] {r}")
    except:
        pass
    
    # Try JSON
    import re
    for m in re.finditer(rb'\{[^{}]*\}', data):
        try:
            import json
            obj = json.loads(m.group())
            formatted = json.dumps(obj, indent=6, ensure_ascii=False)
            results.append(f"    [JSON]\n{formatted}")
        except:
            pass
    
    # Try protobuf field detection
    pb_fields = []
    i = 0
    while i < len(data):
        if data[i] & 0x80 == 0 and data[i] != 0:
            field_num = data[i] >> 3
            wire_type = data[i] & 0x07
            if 1 <= field_num <= 100:
                pb_fields.append(f"field={field_num},wire={wire_type}")
        i += 1
    if pb_fields:
        results.append(f"    [PROTOBUF] Possible fields: {', '.join(pb_fields[:10])}")
    
    return '\n'.join(results)

# ── Relay ───────────────────────────────────────────────────────────────────
def relay(src, dst, src_name, dst_name, conn_id, stats, direction):
    """Relay data from src to dst, return True if connection closed."""
    try:
        data = src.recv(65536)
        if not data:
            print(f"\n  [{src_name} → CLOSED]")
            return False
        
        stats[direction] += len(data)
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        
        print(f"\n  [{ts}] {src_name} → {dst_name}  [{len(data)} bytes, total {direction}: {stats[direction]}]")
        print(hexdump(data))
        decoded = decode_text(data)
        if decoded:
            print(decoded)
        
        dst.send(data)
        return True
    except ssl.SSLWantReadError:
        return True
    except (ConnectionResetError, BrokenPipeError, OSError):
        print(f"\n  [{src_name} → CONNECTION LOST]")
        return False

# ── Handle one client connection ────────────────────────────────────────────
def handle_client(client_sock, addr, conn_id):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n{'='*70}")
    print(f"[+] [{ts}] Connection #{conn_id} from {addr[0]}:{addr[1]}")
    
    remote_sock = None
    client_tls = None
    remote_tls = None
    
    try:
        # Step 1: TLS handshake with client (container)
        client_tls = server_ctx.wrap_socket(client_sock, server_side=True)
        print(f"[*] Client TLS: {client_tls.version()} / {client_tls.cipher()[0]}")
        
        # Step 2: Connect to real H3C server
        print(f"[*] Connecting to real server {REAL_HOST}:{REAL_PORT}...")
        raw = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        raw.settimeout(10)
        raw.connect((REAL_HOST, REAL_PORT))
        
        remote_tls = client_ctx.wrap_socket(raw, server_hostname=REAL_HOST)
        print(f"[*] Server TLS: {remote_tls.version()} / {remote_tls.cipher()[0]}")
        print(f"[*] PROXY ACTIVE — relaying bidirectionally...")
        
        # Step 3: Bidirectional relay
        client_tls.setblocking(False)
        remote_tls.setblocking(False)
        
        stats = {'C→S': 0, 'S→C': 0}
        
        while True:
            readable, _, exceptional = select.select(
                [client_tls, remote_tls],
                [],
                [client_tls, remote_tls],
                30.0
            )
            
            if exceptional:
                break
            
            if not readable:
                # Timeout — check if both sides are still alive
                continue
            
            for sock in readable:
                if sock is client_tls:
                    if not relay(client_tls, remote_tls, "CLIENT", "SERVER", conn_id, stats, 'C→S'):
                        return
                elif sock is remote_tls:
                    if not relay(remote_tls, client_tls, "SERVER", "CLIENT", conn_id, stats, 'S→C'):
                        return
    
    except ssl.SSLError as e:
        print(f"\n[!] SSL ERROR: {e}")
    except Exception as e:
        print(f"\n[!] Error: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
    finally:
        total = sum(stats.values()) if 'stats' in dir() else 0
        print(f"\n[*] Connection #{conn_id} closed (total relayed: {total} bytes, C→S: {stats.get('C→S',0)}, S→C: {stats.get('S→C',0)})")
        print(f"{'='*70}")
        for s in [client_tls, remote_tls, client_sock, remote_sock]:
            try:
                s.close()
            except:
                pass

# ── Main ────────────────────────────────────────────────────────────────────
print(f"{'='*70}")
print(f"  UU H3C MITM PROXY — Bidirectional Decrypt")
print(f"  Listen:  {LISTEN_HOST}:{LISTEN_PORT}")
print(f"  Upstream: {REAL_HOST}:{REAL_PORT}")
print(f"{'='*70}")
print()
print("Accepting connections from container...")
print(f"(Ensure container DNS points rglg.* → this machine's IP)")
print()

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((LISTEN_HOST, LISTEN_PORT))
    sock.listen(5)
    
    conn_id = 0
    while True:
        try:
            client, addr = sock.accept()
        except KeyboardInterrupt:
            print("\n[*] Shutting down...")
            break
        
        conn_id += 1
        t = threading.Thread(target=handle_client, args=(client, addr, conn_id), daemon=True)
        t.start()
