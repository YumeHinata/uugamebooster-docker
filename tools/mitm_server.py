#!/usr/bin/env python3
"""
Fake UU H3C Registration Server — TLS MITM
Listens on 0.0.0.0:16000 with pre-generated self-signed cert.
Decrypts and logs ALL data uuplugin sends to the registration server.

Usage:
  1. Generate cert: see gen_cert.sh (run in Docker container)
  2. Copy fake_h3c_cert.pem + fake_h3c_key.pem to this directory
  3. Run: python mitm_server.py
  4. In container: redirect DNS to this machine's IP
  5. Restart container

If TLS handshake FAILS (cert rejected), switch to SSLKEYLOGFILE approach:
  docker-compose.yml → add "SSLKEYLOGFILE=/tmp/sslkeys.log"
  tcpdump -i br-lan port 16000 -w capture.pcap
  Wireshark → Preferences → TLS → (Pre)-Master-Secret log → sslkeys.log
"""

import socket
import ssl
import os
import sys
from datetime import datetime

HOST = '0.0.0.0'
PORT = 16000
CERT_FILE = os.path.join(os.path.dirname(__file__), 'fake_h3c_cert.pem')
KEY_FILE = os.path.join(os.path.dirname(__file__), 'fake_h3c_key.pem')

# ── Check cert files ───────────────────────────────────────────────────────
if not os.path.exists(CERT_FILE):
    print(f"[FATAL] Certificate file not found: {CERT_FILE}")
    print(f"        Generate it first:")
    print(f"        docker exec UUgamebooster openssl req -x509 -newkey rsa:2048 \\")
    print(f"          -nodes -keyout /tmp/key.pem -out /tmp/cert.pem -days 365 \\")
    print(f'          -subj "/CN=rglg.uu.163.com" \\')
    print(f'          -addext "subjectAltName=DNS:rglg.uu.163.com,DNS:rglg.uu.netease.com,DNS:h3crglg.uu.163.com"')
    print(f"        docker cp UUgamebooster:/tmp/cert.pem tools/fake_h3c_cert.pem")
    print(f"        docker cp UUgamebooster:/tmp/key.pem tools/fake_h3c_key.pem")
    sys.exit(1)

# ── TLS Context ─────────────────────────────────────────────────────────────
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(CERT_FILE, KEY_FILE)
context.verify_mode = ssl.CERT_NONE
context.check_hostname = False
# Support TLS 1.0-1.2 (binary uses OpenSSL 1.0.2q era)
context.minimum_version = ssl.TLSVersion.TLSv1
context.maximum_version = ssl.TLSVersion.TLSv1_2

print(f"{'='*70}")
print(f"  Fake UU H3C Registration Server (MITM)")
print(f"  Listening: {HOST}:{PORT}")
print(f"  Cert: {CERT_FILE}")
print(f"{'='*70}")
print()
print("Waiting for uuplugin to connect...")
print("(If nothing happens, check:")
print("  1. DNS in container points to this machine's IP")
print("  2. Firewall allows inbound port 16000")
print("  3. Container restarted after DNS change)")
print()

# ── Main loop ───────────────────────────────────────────────────────────────
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((HOST, PORT))
    sock.listen(5)

    conn_id = 0
    while True:
        try:
            client, addr = sock.accept()
        except KeyboardInterrupt:
            print("\n[*] Shutting down...")
            break

        conn_id += 1
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"\n{'='*70}")
        print(f"[+] [{ts}] Connection #{conn_id} from {addr[0]}:{addr[1]}")

        try:
            with context.wrap_socket(client, server_side=True) as tls:
                print(f"[*] TLS version: {tls.version()}")
                print(f"[*] Cipher: {tls.cipher()}")

                total_bytes = 0
                while True:
                    try:
                        tls.settimeout(10.0)
                        data = tls.recv(65536)
                        if not data:
                            print(f"\n[*] Client closed connection (total received: {total_bytes} bytes)")
                            break

                        total_bytes += len(data)
                        print(f"\n[<---] RECEIVED {len(data)} bytes (total: {total_bytes})")

                        # ── Full hex dump ──────────────────────────────
                        for i in range(0, len(data), 32):
                            line_bytes = data[i:i+32]
                            hex_part = ' '.join(f'{b:02x}' for b in line_bytes)
                            ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in line_bytes)
                            print(f"  {i:04x}: {hex_part:<96s} |{ascii_part}|")

                        # ── Try UTF-8 decode ───────────────────────────
                        try:
                            text = data.decode('utf-8')
                            printable = any(c.isprintable() or c in '\n\r\t' for c in text)
                            if printable:
                                print(f"\n  [UTF-8 TEXT]:")
                                for line in text.split('\n')[:100]:
                                    if line.strip():
                                        print(f"    {line}")
                                if len(text.split('\n')) > 100:
                                    print(f"    ... (truncated, {len(text.split('\n'))} lines total)")
                        except UnicodeDecodeError:
                            pass

                        # ── Try to parse as JSON (detect JSON in binary stream) ──
                        import re
                        json_pattern = rb'\{[^{}]*\}'
                        for m in re.finditer(json_pattern, data):
                            try:
                                import json
                                obj = json.loads(m.group())
                                print(f"\n  [JSON FOUND]:")
                                print(f"  {json.dumps(obj, indent=4, ensure_ascii=False)}")
                            except:
                                pass

                        # ── Try protobuf-like detection ──────────────────
                        # Protobuf often has field tags at start of messages
                        for i in range(min(5, len(data) - 1)):
                            b = data[i]
                            if 0x08 <= b <= 0x2f or b in (0x30, 0x38, 0x40, 0x48, 0x50):
                                pass  # Possible protobuf tag

                        # Send minimal response to keep connection alive
                        # (real H3C server would send session/token response)
                        # uuplugin expects some response or it may disconnect
                        try:
                            tls.send(b'\x00')
                        except:
                            pass

                    except ssl.SSLWantReadError:
                        continue
                    except socket.timeout:
                        print(f"\n[*] Timeout after {total_bytes} bytes total")
                        break
                    except (ConnectionResetError, BrokenPipeError):
                        print(f"\n[*] Connection reset by client")
                        break

        except ssl.SSLError as e:
            print(f"\n[!] SSL ERROR: {e}")
            print(f"[!] → Binary REJECTED our self-signed certificate!")
            print(f"[!] → Use SSLKEYLOGFILE approach instead:")
            print(f"[!]   1. Add 'SSLKEYLOGFILE=/tmp/sslkeys.log' to docker-compose.yml env")
            print(f"[!]   2. Restart container + capture with tcpdump")
            print(f"[!]   3. Decrypt in Wireshark with the keylog file")
        except Exception as e:
            print(f"\n[!] Error: {type(e).__name__}: {e}")
        finally:
            try:
                client.close()
            except:
                pass

        print(f"{'='*70}")
