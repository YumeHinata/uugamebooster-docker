#!/usr/bin/env python3
"""
uu_mitm_monitor.py — Pass-through TLS proxy for monitoring uuplugin ↔ UU server.

Based on uu_mitm.py from the x86 MITM scheme, but with ALL modification logic
removed. This is a pure OBSERVER:
  - Accepts TLS from uuplugin (self-signed cert)
  - Connects to real H3C server (42.186.111.127:16000)
  - Relays bidirectionally without ANY modification
  - Logs ALL protobuf frames with parsed fields to /tmp/mitm_monitor.log

Protocol (inside TLS):
  Frame: [4B total_len BE][4B msg_type BE][protobuf payload]

Message types:
  0x00=Heartbeat, 0x01=Pong, 0x02=FullRegister, 0x03=FullRegisterResp,
  0x04=DeviceInfo, 0x06=Device, 0x0A=Log, 0x0E=ScanTarget,
  0x10=ConnectReq, 0x11=ConnectReply, 0x22=RelayNodes,
  0x24=Register, 0x25=RegisterResp, 0x26=CertResp, 0x30=ActivateResp,
  0x3A=DirectAddr
"""

import socket
import ssl
import struct
import sys
import os
import time
import threading
import select
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 16000

# H3C server (from previous MITM scheme + observed connections)
REAL_HOST = os.environ.get('UU_MITM_REAL_HOST', '106.2.95.34')
REAL_PORT = int(os.environ.get('UU_MITM_REAL_PORT', '16000'))

# Cert paths (generated in Dockerfile)
CERT_DIR = Path('/opt/uu/certs')
CERT_FILE = CERT_DIR / 'mitm_cert.pem'
KEY_FILE = CERT_DIR / 'mitm_key.pem'

LOG_FILE = '/tmp/mitm_monitor.log'
FRAME_LOG = '/tmp/mitm_frames.log'  # Raw frame dump

# ═══════════════════════════════════════════════════════════════════════════
# Protobuf parser (minimal, same as uu_mitm.py)
# ═══════════════════════════════════════════════════════════════════════════

def pb_read_varint(data, pos=0):
    value = 0; shift = 0
    while pos < len(data):
        b = data[pos]; pos += 1
        value |= (b & 0x7F) << shift; shift += 7
        if not (b & 0x80): break
    return value, pos

def pb_parse(data):
    result = {}; pos = 0
    while pos < len(data):
        try: fh, pos = pb_read_varint(data, pos)
        except: break
        fn, wt = fh >> 3, fh & 0x07
        if wt == 0:
            v, pos = pb_read_varint(data, pos); result[fn] = v
        elif wt == 2:
            length, pos = pb_read_varint(data, pos)
            raw = data[pos:pos+length]; pos += length
            try:
                t = raw.decode('utf-8', errors='replace')
                if all(32 <= ord(c) < 127 or c in '\n\r\t' for c in t):
                    result[fn] = t
                else:
                    result[fn] = f'<bin:{len(raw)}B>'
            except:
                result[fn] = f'<bin:{len(raw)}B>'
    return result

# ═══════════════════════════════════════════════════════════════════════════
# Message type names
# ═══════════════════════════════════════════════════════════════════════════

TYPE_NAMES = {
    0x00: 'Heartbeat', 0x01: 'Pong', 0x02: 'FullRegister',
    0x03: 'FullRegisterResp', 0x04: 'DeviceInfo', 0x06: 'Device',
    0x0A: 'Log', 0x0E: 'ScanTarget', 0x10: 'ConnectReq',
    0x11: 'ConnectReply', 0x22: 'RelayNodes',
    0x24: 'Register', 0x25: 'RegisterResp', 0x26: 'CertResp',
    0x30: 'ActivateResp', 0x3A: 'DirectAddr',
}

# Types that are interesting enough to always log fully
INTERESTING_TYPES = {0x02, 0x03, 0x04, 0x06, 0x10, 0x11, 0x24, 0x25, 0x3A}

# ═══════════════════════════════════════════════════════════════════════════
# Logging
# ═══════════════════════════════════════════════════════════════════════════

def log(msg):
    ts = datetime.now().strftime('%H:%M:%S.%f')[:-3]
    line = f'[{ts}] {msg}'
    print(line, flush=True)
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(line + '\n')
    except:
        pass

def log_frame(direction, msg_type, raw_frame, parsed):
    """Log a complete frame with hex and parsed fields."""
    tname = TYPE_NAMES.get(msg_type, f'0x{msg_type:02X}')
    pb = raw_frame[8:]  # skip 4B len + 4B type
    ts = datetime.now().strftime('%H:%M:%S.%f')[:-3]

    # Short parsed view for console
    short = {}
    for k, v in parsed.items():
        s = str(v)
        short[k] = s[:100] + ('...' if len(s) > 100 else '')

    # Full log entry
    entry = f'[{ts}] {direction} {tname} (0x{msg_type:02X}) len={len(pb)} fields={short}\n'
    print(entry.strip(), flush=True)

    try:
        with open(FRAME_LOG, 'a') as f:
            f.write(f'[{ts}] {direction} | {tname} (0x{msg_type:02X}) | len={len(pb)}\n')
            f.write(f'  FIELDS: {parsed}\n')
            f.write(f'  HEX: {pb.hex()}\n')
            f.write('---\n')
    except:
        pass

# ═══════════════════════════════════════════════════════════════════════════
# Connection handler
# ═══════════════════════════════════════════════════════════════════════════

def handle_connection(client_sock, addr, conn_id):
    """Relay TLS between uuplugin (client) and H3C server."""
    ts = datetime.now().strftime('%H:%M:%S')
    log(f'[+] Connection #{conn_id} from {addr[0]}:{addr[1]}')

    # TLS server context (accept uuplugin)
    server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    if CERT_FILE.exists() and KEY_FILE.exists():
        server_ctx.load_cert_chain(str(CERT_FILE), str(KEY_FILE))
    else:
        log('[!] WARNING: No certs, using ad-hoc self-signed')
        server_ctx.load_cert_chain(str(CERT_FILE), str(KEY_FILE))  # will fail
    server_ctx.verify_mode = ssl.CERT_NONE
    server_ctx.check_hostname = False
    server_ctx.minimum_version = ssl.TLSVersion.TLSv1
    server_ctx.set_ciphers('ALL:@SECLEVEL=0')

    # TLS client context (connect to H3C server)
    client_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    client_ctx.check_hostname = False
    client_ctx.verify_mode = ssl.CERT_NONE
    client_ctx.minimum_version = ssl.TLSVersion.TLSv1

    server_sock = None
    cl_tls = None
    srv_tls = None
    n_frames = 0

    try:
        client_sock.settimeout(10)
        cl_tls = server_ctx.wrap_socket(client_sock, server_side=True)
        log(f'  [TLS] uuplugin: {cl_tls.version()} / {cl_tls.cipher()[0]}')

        # Connect to real H3C server
        server_sock = socket.socket()
        server_sock.settimeout(10)
        # SO_MARK=1 to bypass iptables DNAT (avoid loop)
        server_sock.setsockopt(socket.SOL_SOCKET, 36, 1)
        server_sock.connect((REAL_HOST, REAL_PORT))
        srv_tls = client_ctx.wrap_socket(server_sock, server_hostname=REAL_HOST)
        log(f'  [TLS] H3C server ({REAL_HOST}:{REAL_PORT}): {srv_tls.version()} / {srv_tls.cipher()[0]}')

        cl_tls.setblocking(False)
        srv_tls.setblocking(False)
        c_buf = b''
        s_buf = b''

        while True:
            try:
                r, _, _ = select.select([cl_tls, srv_tls], [], [], 30.0)
            except:
                break
            if not r:
                continue

            for sock in r:
                is_client = (sock is cl_tls)
                src = cl_tls if is_client else srv_tls
                dst = srv_tls if is_client else cl_tls
                direction = 'C→S' if is_client else 'S→C'

                try:
                    data = src.recv(65536)
                except (ssl.SSLWantReadError, BlockingIOError):
                    continue
                except Exception as e:
                    log(f'  [!] recv error: {e}')
                    return

                if not data:
                    return

                # Accumulate into direction buffer
                if is_client:
                    c_buf += data
                    buf = c_buf
                else:
                    s_buf += data
                    buf = s_buf

                # Extract complete frames
                frames = []
                while len(buf) >= 4:
                    total_len = struct.unpack(">I", buf[:4])[0]
                    if total_len > 1024 * 1024:  # sanity check
                        buf = b''
                        break
                    if len(buf) < 4 + total_len:
                        break
                    raw = buf[:4 + total_len]
                    buf = buf[4 + total_len:]
                    msg_type = struct.unpack(">I", raw[4:8])[0]
                    pb = raw[8:]
                    frames.append((msg_type, pb, raw))

                if is_client:
                    c_buf = buf
                else:
                    s_buf = buf

                # Process each frame
                for msg_type, protobuf, raw_frame in frames:
                    n_frames += 1
                    tname = TYPE_NAMES.get(msg_type, f'0x{msg_type:02X}')
                    parsed = pb_parse(protobuf)

                    # Always log interesting types, throttle heartbeats
                    if msg_type in INTERESTING_TYPES or msg_type not in (0x00, 0x01):
                        log_frame(direction, msg_type, raw_frame, parsed)

                    # Forward unmodified
                    try:
                        dst.sendall(raw_frame)
                    except:
                        return

    except Exception as e:
        log(f'  [!] Error: {e}')
        import traceback
        traceback.print_exc()
    finally:
        for s in [cl_tls, srv_tls, client_sock, server_sock]:
            try:
                s.close()
            except:
                pass
        log(f'  [*] Connection #{conn_id} closed ({n_frames} frames)')

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    log('=' * 55)
    log('  UU MITM MONITOR — Pass-through Observer')
    log(f'  Listen: {LISTEN_HOST}:{LISTEN_PORT}')
    log(f'  → Real: {REAL_HOST}:{REAL_PORT}')
    log(f'  Log:    {LOG_FILE}')
    log(f'  Frames: {FRAME_LOG}')
    log('=' * 55)

    # Check certs
    if not CERT_FILE.exists() or not KEY_FILE.exists():
        log(f'[FATAL] TLS certs missing: {CERT_FILE} / {KEY_FILE}')
        log('        Generate with: openssl req -x509 -newkey rsa:2048 ...')
        sys.exit(1)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((LISTEN_HOST, LISTEN_PORT))
    sock.listen(5)

    log('[READY] Waiting for connections...')

    conn_id = 0
    while True:
        try:
            client, addr = sock.accept()
            conn_id += 1
            t = threading.Thread(
                target=handle_connection,
                args=(client, addr, conn_id),
                daemon=True
            )
            t.start()
        except KeyboardInterrupt:
            log('\n[MITM] Shutting down...')
            break
        except Exception as e:
            log(f'[!] accept error: {e}')
            time.sleep(1)

if __name__ == '__main__':
    main()
