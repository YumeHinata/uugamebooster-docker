#!/usr/bin/env python3
"""
UU Registration MITM — Response Modifier

Intercepts the RegisterResp (type 0x25) from server and replaces 
"router not found" with a success response to trick the container
into thinking registration succeeded.

Also tries different "success" response formats to find what works.

Usage:
  python uu_mitm_mod.py --listen 0.0.0.0:16000 --target 106.2.95.34:16000 [--dry-run]
"""

import socket
import ssl
import struct
import sys
import os
import time
import threading
import argparse
import json
import select
import traceback
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CERT_FILE = SCRIPT_DIR / "mitm_cert.pem"
KEY_FILE = SCRIPT_DIR / "mitm_key.pem"

# ═══════════════════════════════════════════════════════════════════════════
# Protobuf helpers
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
                t = raw.decode('utf-8')
                result[fn] = t if all(32<=ord(c)<127 or c in '\n\r\t' for c in t) else f'<hex:{raw[:20].hex()}>'
            except: result[fn] = f'<hex:{raw[:20].hex()}>'
    return result

def pb_varint(v):
    r = []
    while v > 0x7F: r.append((v & 0x7F) | 0x80); v >>= 7
    r.append(v & 0x7F); return bytes(r)

def pb_str(fn, s):
    d = s.encode() if isinstance(s, str) else s
    return pb_varint((fn << 3) | 2) + pb_varint(len(d)) + d

def pb_int(fn, v):
    return pb_varint((fn << 3) | 0) + pb_varint(v)

def make_frame(msg_type, protobuf):
    total = 4 + len(protobuf)
    return struct.pack(">I", total) + struct.pack(">I", msg_type) + protobuf

# ═══════════════════════════════════════════════════════════════════════════
# Success response generator
# ═══════════════════════════════════════════════════════════════════════════

def make_success_response():
    """Build a RegisterResp that says router was found."""
    # Try different formats:
    # Format 1: code=1, msg="router found"
    # Format 2: code=200, msg="success"  
    # Format 3: just msg="router found", code=0 (server might use code=0 for success)
    
    pb = b''
    pb += pb_int(2, 1)           # field 2: code = 1 (success)
    pb += pb_str(3, "router found")  # field 3: message
    
    return make_frame(0x25, pb)

def make_success_response_v2():
    """Alternative: code=0 might mean success in their protocol."""
    pb = b''
    pb += pb_int(2, 0)
    pb += pb_str(3, "success")
    return make_frame(0x25, pb)

def make_success_response_v3():
    """Try with router_id field."""
    pb = b''
    pb += pb_str(1, "0000000000000001")  # field 1: router_id
    pb += pb_int(2, 1)                    # field 2: code
    pb += pb_str(3, "success")            # field 3: msg
    return make_frame(0x25, pb)

SUCCESS_FRAMES = [
    ("code=1+found", make_success_response()),
    ("code=0+success", make_success_response_v2()),
    ("rid+code=1+success", make_success_response_v3()),
]

# ═══════════════════════════════════════════════════════════════════════════
# Post-registration activation messages (injected after RegisterResp success)
# ═══════════════════════════════════════════════════════════════════════════

def make_activate_message():
    """Simulate a server activation/auth response that might trigger activate_status write."""
    pb = b''
    pb += pb_int(1, 0)           # field 1: code = 0 (success)
    pb += pb_str(2, "activated")  # field 2: status
    pb += pb_int(3, 1)           # field 3: auth_pass = 1
    return make_frame(0x30, pb)  # Use type 0x30 (AuthRes-like)

def make_cert_message():
    """Simulate a certificate/auth token delivery."""
    pb = b''
    pb += pb_int(1, 0)           # code
    pb += pb_str(2, "OK")        # status
    pb += pb_str(3, "token_placeholder_32bytes_")  # token
    return make_frame(0x26, pb)

def make_config_message():
    """Simulate a device config push after registration."""
    pb = b''
    pb += pb_int(1, 1)           # enabled
    pb += pb_str(2, "h3cnx30")   # model confirm
    pb += pb_int(3, 1)           # features_enabled
    return make_frame(0x06, pb)  # type 0x06 = Device

# After each RegisterResp success injection, rotate through these follow-up messages
ACTIVATION_MESSAGES = [
    ("activate", make_activate_message()),
    ("cert_token", make_cert_message()),
    ("config", make_config_message()),
]

# ═══════════════════════════════════════════════════════════════════════════
# MITM
# ═══════════════════════════════════════════════════════════════════════════

class ModMITM:
    def __init__(self, listen, target, dry_run=False):
        self.listen_addr = listen
        self.target_addr = target
        self.dry_run = dry_run
        self.n_modified = 0
        self.n_passed = 0
        self.conn_id = 0
    
    def start(self):
        server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        server_ctx.load_cert_chain(str(CERT_FILE), str(KEY_FILE))
        server_ctx.verify_mode = ssl.CERT_NONE
        server_ctx.check_hostname = False
        
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(self.listen_addr)
        sock.listen(10)
        
        print(f"\n{'='*60}")
        print(f"  UU REGISTRATION MITM — Response Modifier")
        print(f"  Listen:  {self.listen_addr[0]}:{self.listen_addr[1]}")
        print(f"  Upstream: {self.target_addr[0]}:{self.target_addr[1]}")
        print(f"  Mode: {'DRY RUN (no modification)' if self.dry_run else 'MODIFYING RESPONSES'}")
        print(f"  Success formats to try: {[f[0] for f in SUCCESS_FRAMES]}")
        print(f"{'='*60}\n")
        
        while True:
            try:
                client, addr = sock.accept()
                self.conn_id += 1
                t = threading.Thread(target=self.handle, args=(client, addr), daemon=True)
                t.start()
            except KeyboardInterrupt:
                print("\n[MITM] Shutting down...")
                break
    
    def handle(self, client_sock, addr):
        print(f"\n[+] Connection #{self.conn_id} from {addr[0]}:{addr[1]}", flush=True)
        
        server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        server_ctx.load_cert_chain(str(CERT_FILE), str(KEY_FILE))
        server_ctx.verify_mode = ssl.CERT_NONE; server_ctx.check_hostname = False
        # Allow older TLS versions for compatibility
        server_ctx.minimum_version = ssl.TLSVersion.TLSv1
        
        client_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        client_ctx.check_hostname = False; client_ctx.verify_mode = ssl.CERT_NONE
        client_ctx.minimum_version = ssl.TLSVersion.TLSv1
        
        server_sock = None; cl_tls = None; srv_tls = None
        session_frames = []
        success_idx = 0  # Which success format to try
        activate_idx = 0  # Which activation message to try
        n_fatal_suppressed = 0
        
        try:
            client_sock.settimeout(10)
            print(f"  [TLS] Waiting for client TLS handshake...", flush=True)
            cl_tls = server_ctx.wrap_socket(client_sock, server_side=True)
            print(f"  [TLS] Client connected: {cl_tls.version()}, cipher: {cl_tls.cipher()[0]}", flush=True)
            
            print(f"  [TCP] Connecting to upstream {self.target_addr[0]}:{self.target_addr[1]}...", flush=True)
            server_sock = socket.socket(); server_sock.settimeout(10)
            server_sock.connect(self.target_addr)
            srv_tls = client_ctx.wrap_socket(server_sock, server_hostname=self.target_addr[0])
            print(f"  [TLS] Server connected: {srv_tls.version()}, cipher: {srv_tls.cipher()[0]}", flush=True)
            
            cl_tls.setblocking(False)
            srv_tls.setblocking(False)
            
            c_buf = b''; s_buf = b''
            modified_this_session = False
            
            while True:
                try:
                    r, _, _ = select.select([cl_tls, srv_tls], [], [], 30.0)
                except: break
                if not r: continue
                
                for sock in r:
                    is_client = (sock is cl_tls)
                    src = cl_tls if is_client else srv_tls
                    dst = srv_tls if is_client else cl_tls
                    direction = "CLIENT→SERVER" if is_client else "SERVER→CLIENT"
                    
                    try:
                        data = src.recv(65536)
                    except (ssl.SSLWantReadError, BlockingIOError):
                        continue
                    except:
                        print(f"  [*] Connection closed ({direction})")
                        return
                    
                    if not data:
                        print(f"  [*] Connection closed ({direction})")
                        return
                    
                    # Parse frames — accumulate into per-direction buffer
                    if is_client:
                        c_buf += data
                        buf = c_buf
                    else:
                        s_buf += data
                        buf = s_buf
                    frames = []
                    
                    while len(buf) >= 4:
                        total_len = struct.unpack(">I", buf[:4])[0]
                        if total_len > 1024*1024: buf = b''; break
                        if len(buf) < 4 + total_len: break
                        raw = buf[:4+total_len]; buf = buf[4+total_len:]
                        msg_type = struct.unpack(">I", raw[4:8])[0]
                        protobuf = raw[8:]
                        frames.append((msg_type, protobuf, raw))
                    
                    if is_client:
                        c_buf = buf
                    else:
                        s_buf = buf
                    
                    # Process each frame
                    for msg_type, protobuf, raw in frames:
                        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
                        parsed = pb_parse(protobuf)
                        
                        # Log
                        type_names = {0x00:'Heartbeat',0x01:'Pong',0x24:'Register',0x25:'RegisterResp',
                                      0x02:'FullRegister',0x0A:'Log',0x06:'Device',0x10:'ConnectReq',
                                      0x11:'ConnectReply'}
                        tname = type_names.get(msg_type, f'0x{msg_type:02x}')
                        print(f"  [{ts}] {direction} {tname}: {dict(list(parsed.items())[:3])}")
                        
                        # Check if this is a CLIENT→SERVER FATAL log — suppress it
                        skip_forward = False
                        if is_client and msg_type == 0x0A and not self.dry_run:
                            msg_content = str(parsed.get(2, ''))
                            if 'unmatched sn' in msg_content or 'from_file' in msg_content:
                                print(f"    >>> SUPPRESSED FATAL: 'unmatched sn' log hidden from server")
                                n_fatal_suppressed += 1
                                skip_forward = True  # Don't let server see this
                        
                        # Check if this is a RegisterResp with "not found"
                        forward_data = raw
                        
                        if not is_client and msg_type == 0x25 and not self.dry_run:
                            msg = parsed.get(3, '')
                            code = parsed.get(2, 0)
                            
                            if isinstance(msg, str) and 'not found' in msg.lower():
                                print(f"    >>> DETECTED 'router not found' — injecting success response!")
                                
                                # Try current success format
                                succ_name, succ_frame = SUCCESS_FRAMES[success_idx % len(SUCCESS_FRAMES)]
                                forward_data = succ_frame
                                print(f"    >>> Injected RegisterResp: {succ_name}")
                                print(f"    >>> Raw: {forward_data.hex()[:80]}")
                                modified_this_session = True
                                self.n_modified += 1
                                
                                # Also inject an activation follow-up message
                                act_name, act_frame = ACTIVATION_MESSAGES[activate_idx % len(ACTIVATION_MESSAGES)]
                                try:
                                    dst.sendall(forward_data)  # Send success first
                                    time.sleep(0.02)           # Small gap
                                    dst.sendall(act_frame)     # Send activation
                                    print(f"    >>> + Injected follow-up: {act_name}")
                                except:
                                    return
                                activate_idx += 1
                                success_idx += 1
                                continue  # Already forwarded both, skip normal forward
                            else:
                                print(f"    RESPONSE: code={code}, msg={msg}")
                                self.n_passed += 1
                        
                        # Skip forwarding suppressed messages
                        if skip_forward:
                            continue
                        
                        # Forward (possibly modified)
                        try:
                            dst.sendall(forward_data)
                        except:
                            return
                    
        except Exception as e:
            print(f"  [!] Error: {e}")
            import traceback; traceback.print_exc()
        finally:
            for s in [cl_tls, srv_tls, client_sock, server_sock]:
                try: s.close()
                except: pass
            print(f"  [*] Connection #{self.conn_id} closed")
            if n_fatal_suppressed:
                print(f"  [FILT] Suppressed {n_fatal_suppressed} FATAL 'unmatched sn' logs")
            if modified_this_session:
                print(f"  [MOD] Registration responses were MODIFIED this session!")
            print(f"  [STATS] Total modified: {self.n_modified}, passed: {self.n_passed}")

# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="UU Registration MITM with Response Modification")
    parser.add_argument("--listen", default="0.0.0.0:16000")
    parser.add_argument("--target", default="106.2.95.34:16000")
    parser.add_argument("--dry-run", action="store_true", help="Pass through without modification")
    args = parser.parse_args()
    
    lh, lp = args.listen.split(":")
    th, tp = args.target.split(":")
    
    mitm = ModMITM((lh, int(lp)), (th, int(tp)), args.dry_run)
    mitm.start()

if __name__ == "__main__":
    main()
