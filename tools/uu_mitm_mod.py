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

def make_nx30pro_register_resp():
    """Exact NX30Pro RegisterResp captured from real aarch64 binary.
    Protocol: code=0 + "router not bound" → triggers FullRegister flow.
    Raw[46]: 0000002a000000250a10...10001a10726f75746572206e6f7420626f756e64
    """
    pb = b''
    pb += pb_str(1, "0000000000000000")      # field 1: router_id (echoed)
    pb += pb_int(2, 0)                        # field 2: code = 0 (not-bound, proceed)
    pb += pb_str(3, "router not bound")       # field 3: message
    return make_frame(0x25, pb)

def make_success_response():
    """Fallback: code=1, msg="router found" (legacy format)."""
    pb = b''
    pb += pb_int(2, 1)
    pb += pb_str(3, "router found")
    return make_frame(0x25, pb)

def make_success_response_v2():
    """Fallback: code=0 might mean success in their protocol."""
    pb = b''
    pb += pb_int(2, 0)
    pb += pb_str(3, "success")
    return make_frame(0x25, pb)

SUCCESS_FRAMES = [
    ("NX30Pro:code=0+not_bound", make_nx30pro_register_resp()),
    ("code=1+found", make_success_response()),
    ("code=0+success", make_success_response_v2()),
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
# Register message field injection: add H3C NX30Pro identity fields
# ═══════════════════════════════════════════════════════════════════════════

def fix_field2_binary_to_string(raw_pb):
    """
    x86 binary sends f2 as "h3c_\x00\x00\x00\x00\x00" (tag 0x12, len 0x07, 7 bytes).
    NX30Pro sends f2 as 3-byte string "h3c" (tag 0x12, len 0x03).
    Fix the raw protobuf bytes in-place.
    """
    # Pattern: \x12\x07 followed by "h3c_" (x86 binary format, 7-byte data)
    idx = raw_pb.find(b'\x12\x07h3c_')
    if idx >= 0:
        # Replace 9 bytes (tag+len1+7 data) → 5 bytes (tag+len3+3 data)
        before = raw_pb[:idx]
        after = raw_pb[idx + 9:]
        return before + pb_str(2, b'h3c') + after
    # Fallback: try old 8-byte pattern (just in case)
    idx = raw_pb.find(b'\x12\x08h3c')
    if idx >= 0:
        before = raw_pb[:idx]
        after = raw_pb[idx + 10:]
        return before + pb_str(2, b'h3c') + after
    return raw_pb  # no change needed


def fix_field4_vendor_binary_to_string(raw_pb):
    """
    x86 binary sends f4 vendor as "h3c_\x00\x00\x00\x00" (tag 0x22, len 0x07, 7 bytes)
    in DeviceInfo messages. NX30Pro sends f4 vendor as 3-byte string "h3c".
    Fix the raw protobuf bytes in-place.
    """
    # Pattern: \x22\x07 followed by "h3c_" (x86 binary format, 7-byte data)
    idx = raw_pb.find(b'\x22\x07h3c_')
    if idx >= 0:
        before = raw_pb[:idx]
        after = raw_pb[idx + 9:]  # tag(1) + len(1) + data(7) = 9 bytes
        return before + pb_str(4, b'h3c') + after
    return raw_pb  # no change needed


def enhance_register(original_pb, mac_override=None, sn_override=None):
    """
    Take the x86 binary's Register protobuf and inject NX30Pro-specific
    fields that were discovered from the real aarch64 binary:
    
    Real NX30Pro Register: {f1=rid, f2='h3c', f3=SN, f4='NX30Pro', f6='v14.4.20'}
    x86 Register:          {f1=rid, f2='h3c_'(7B), f3=SN, f4='NX30Pro', f6='v14.3.0'}
    
    Returns: (modified_pb_bytes, fields_added_list)
    """
    # Step 1: Fix f2 (binary 7B "h3c_" → string 3B "h3c")
    pb_data = fix_field2_binary_to_string(original_pb)
    
    # Step 2: Fix f6 version (x86 sends v14.3.0, NX30Pro uses v14.4.20)
    # Field 6 tag=0x32, old len=0x07, "v14.3.0" → new len=0x08, "v14.4.20"
    idx = pb_data.find(b'\x32\x07v14.3.0')
    if idx >= 0:
        pb_data = pb_data[:idx] + pb_str(6, 'v14.4.20') + pb_data[idx+9:]
    
    # Step 3: Override SN with real NX30Pro SN (server may check SN range)
    if sn_override:
        idx = pb_data.find(sn_override['old'].encode())
        if idx >= 0 and len(sn_override['old']) == len(sn_override['new']):
            pb_data = pb_data[:idx] + sn_override['new'].encode() + pb_data[idx+len(sn_override['old']):]
    
    parsed = pb_parse(pb_data)
    added = []
    existing_fields = set(parsed.keys())
    pb = bytearray(pb_data)
    
    # Step 4: Add f4 = product name (confirmed from real NX30Pro)
    if 4 not in existing_fields:
        pb += pb_str(4, "NX30Pro")
        added.append("f4:product=NX30Pro")
    elif parsed.get(4) != 'NX30Pro':
        added.append("f4:exists=%s" % parsed.get(4))
    
    # Step 5: Add f6 = firmware version (confirmed from real NX30Pro)
    if 6 not in existing_fields:
        pb += pb_str(6, "v14.4.20")
        added.append("f6:version=v14.4.20")
    
    return bytes(pb), added


def enhance_register_v2(original_pb, mac_override=None, sn_override=None):
    """Alternative: add f5(MAC) + f8(bootver) for testing if v1 is rejected."""
    pb_data = fix_field2_binary_to_string(original_pb)
    
    # Fix f6 version (same as v1)
    idx = pb_data.find(b'\x32\x07v14.3.0')
    if idx >= 0:
        pb_data = pb_data[:idx] + pb_str(6, 'v14.4.20') + pb_data[idx+9:]
    
    # SN override (same as v1)
    if sn_override:
        idx = pb_data.find(sn_override['old'].encode())
        if idx >= 0 and len(sn_override['old']) == len(sn_override['new']):
            pb_data = pb_data[:idx] + sn_override['new'].encode() + pb_data[idx+len(sn_override['old']):]
    
    parsed = pb_parse(pb_data)
    existing_fields = set(parsed.keys())
    pb = bytearray(pb_data)
    added = []
    
    # Same base fields as v1
    if 4 not in existing_fields:
        pb += pb_str(4, "NX30Pro")
        added.append("f4:product=NX30Pro")
    if 6 not in existing_fields:
        pb += pb_str(6, "v14.4.20")
        added.append("f6:version=v14.4.20")
    
    # Optional: try adding MAC + bootver in case server needs them
    if 5 not in existing_fields:
        mac = mac_override or "00:11:22:33:44:55"
        pb += pb_str(5, mac)
        added.append(f"f5:mac={mac}")
    if 8 not in existing_fields:
        pb += pb_int(8, 100)
        added.append("f8:bootver=100")
    
    return bytes(pb), added


# Rotate through different enhancement strategies
REGISTER_ENHANCERS = [
    ("v1_f4f6", enhance_register),
    ("v2_f4f6+f5f8", enhance_register_v2),
]

# Real NX30Pro SN captured from QEMU test (server may check H3C SN range)
NX30PRO_SN = "55347901036946359222"

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
        print(f"  Mode: {'DRY RUN (no modification)' if self.dry_run else 'NX30Pro Register injection + register-resp fix'}")
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
        # Allow older TLS versions + RSA ciphers NX30Pro binary uses
        server_ctx.minimum_version = ssl.TLSVersion.TLSv1
        server_ctx.set_ciphers('ALL:@SECLEVEL=0')
        
        client_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        client_ctx.check_hostname = False; client_ctx.verify_mode = ssl.CERT_NONE
        client_ctx.minimum_version = ssl.TLSVersion.TLSv1
        
        server_sock = None; cl_tls = None; srv_tls = None
        session_frames = []
        success_idx = 0  # Which Register enhancer to try (v1/v2)
        n_fatal_suppressed = 0
        modified_this_session = False
        
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
                                      0x11:'ConnectReply',0x03:'FullRegisterResp',0x04:'DeviceInfo',
                                      0x0e:'ScanTarget',0x3a:'DirectAddr',0x30:'ActivateResp'}
                        tname = type_names.get(msg_type, f'0x{msg_type:02x}')
                        # Show ALL fields for key messages, full raw hex for unidentified types
                        if tname in ('Register', 'RegisterResp', 'Log', 'FullRegister', 'DeviceInfo',
                                     'Device', 'ScanTarget', 'ConnectReq', 'FullRegisterResp',
                                     'DirectAddr', 'ActivateResp'):
                            print(f"  [{ts}] {direction} {tname}: {parsed}")
                            print(f"    Raw[{len(raw)}]: {raw.hex()}")
                        elif msg_type not in type_names:
                            # Unknown message type — dump everything
                            print(f"  [{ts}] {direction} {tname}: {parsed}")
                            print(f"    Raw[{len(raw)}]: {raw.hex()}")
                        else:
                            print(f"  [{ts}] {direction} {tname}: {dict(list(parsed.items())[:3])}")
                        
                        # Check if this is a CLIENT→SERVER FATAL log — suppress it
                        skip_forward = False
                        if is_client and msg_type == 0x0A and not self.dry_run:
                            msg_content = str(parsed.get(2, ''))
                            if 'unmatched sn' in msg_content or 'from_file' in msg_content:
                                print(f"    >>> SUPPRESSED FATAL: 'unmatched sn' log hidden from server")
                                n_fatal_suppressed += 1
                                skip_forward = True  # Don't let server see this
                            # Replace x86_64 architecture leak with aarch64 (H3C routers are ARM)
                            if 'Machine type x86_64' in msg_content or 'x86_64' in msg_content:
                                modified_log = protobuf.replace(b'x86_64', b'aarch64')
                                if modified_log != protobuf:
                                    forward_data = raw[:8] + modified_log
                                    new_total = 4 + len(modified_log)
                                    forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                    print(f"    >>> Log: x86_64 → aarch64 (architecture leak fixed)")
                        
                        # Check if this is a CLIENT→SERVER Register — inject H3C fields
                        forward_data = raw
                        
                        if is_client and msg_type == 0x24 and not self.dry_run:
                            enh_name, enh_func = REGISTER_ENHANCERS[success_idx % len(REGISTER_ENHANCERS)]
                            # Build SN override: replace random x86 SN with real NX30Pro SN
                            sn_override = None
                            current_sn = str(parsed.get(3, ''))
                            if current_sn and len(current_sn) == len(NX30PRO_SN):
                                sn_override = {'old': current_sn, 'new': NX30PRO_SN}
                            enhanced_pb, added_fields = enh_func(protobuf, sn_override=sn_override)
                            forward_data = raw[:8] + enhanced_pb  # keep header, replace PB
                            # Update total length in header
                            # Protocol: [4B total_remaining] [4B msg_type] [protobuf]
                            # total_remaining = 4 + len(protobuf)
                            new_total = 4 + len(enhanced_pb)
                            forward_data = struct.pack(">I", new_total) + forward_data[4:]
                            print(f"    >>> INJECTED Register fields [{enh_name}]: {added_fields}")
                            print(f"    >>> Enhanced Raw[{len(forward_data)}]: {forward_data.hex()}")
                            modified_this_session = True
                        
                        # FullRegister (type 0x02): strip to NX30Pro format (f1+f2+f3 only)
                        # x86 sends 11 fields incl. JWT/payload; real NX30Pro sends only 3.
                        if is_client and msg_type == 0x02 and not self.dry_run:
                            fixed_pb = fix_field2_binary_to_string(protobuf)
                            # Strip all extra fields: keep only f1(rid), f2(vendor), f3(SN)
                            parsed_fr = pb_parse(fixed_pb)
                            sn_fr = str(parsed_fr.get(3, ''))
                            sn = NX30PRO_SN if (sn_fr and len(sn_fr) == len(NX30PRO_SN)) else sn_fr
                            clean_pb = b''
                            clean_pb += pb_str(1, str(parsed_fr.get(1, '')))  # f1: rid
                            clean_pb += pb_str(2, 'h3c')                        # f2: vendor
                            clean_pb += pb_str(3, sn)                            # f3: SN (NX30Pro)
                            if clean_pb != fixed_pb:
                                forward_data = raw[:8] + clean_pb
                                new_total = 4 + len(clean_pb)
                                forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                print(f"    >>> FullRegister: stripped {len(parsed_fr)} fields → 3 (NX30Pro format), SN→{sn}")
                                print(f"    >>> Was[{len(fixed_pb)}B]: {fixed_pb.hex()[:80]}...")
                                print(f"    >>> Now[{len(clean_pb)}B]: {clean_pb.hex()}")
                                modified_this_session = True
                        
                        if not is_client and msg_type == 0x25 and not self.dry_run:
                            msg = parsed.get(3, '')
                            code = parsed.get(2, 0)
                            
                            if isinstance(msg, str) and 'not found' in msg.lower():
                                # Server doesn't recognize device → inject NX30Pro RegisterResp
                                # Real NX30Pro gets: code=0, "router not bound" → FullRegister → success
                                print(f"    >>> DETECTED 'router not found' — injecting NX30Pro RegisterResp!")
                                succ_name, succ_frame = SUCCESS_FRAMES[0]  # Always NX30Pro format
                                forward_data = succ_frame
                                print(f"    >>> Injected RegisterResp: {succ_name}")
                                print(f"    >>> Raw: {forward_data.hex()}")
                                modified_this_session = True
                                self.n_modified += 1
                                # Don't inject follow-ups — binary naturally sends FullRegister
                                # after receiving "router not bound" (same as real NX30Pro flow)
                            elif isinstance(msg, str) and 'not bound' in msg.lower():
                                # Correct NX30Pro response was received — binary will FullRegister
                                print(f"    >>> RegisterResp OK: code={code}, msg='{msg}' — expecting FullRegister")
                                self.n_passed += 1
                            else:
                                print(f"    RESPONSE: code={code}, msg={msg}")
                                self.n_passed += 1
                        
                        # ConnectReply (0x11): fix f2 type + f3 SN so server sees NX30Pro identity
                        if is_client and msg_type == 0x11 and not self.dry_run:
                            modified = fix_field2_binary_to_string(protobuf)
                            parsed_cr = pb_parse(modified)
                            sn_internal = str(parsed_cr.get(3, ''))
                            if sn_internal and len(sn_internal) == len(NX30PRO_SN) and sn_internal != NX30PRO_SN:
                                modified = modified.replace(sn_internal.encode(), NX30PRO_SN.encode())
                            if modified != protobuf:
                                forward_data = raw[:8] + modified
                                new_total = 4 + len(modified)
                                forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                print(f"    >>> ConnectReply: f2→h3c, f3={sn_internal}→{NX30PRO_SN}")
                                modified_this_session = True
                        
                        # DeviceInfo (0x04): fix f4 vendor + f5 SN so server sees NX30Pro identity
                        if is_client and msg_type == 0x04 and not self.dry_run:
                            modified = fix_field4_vendor_binary_to_string(protobuf)
                            parsed_di = pb_parse(modified)
                            sn_di = str(parsed_di.get(5, ''))
                            fixes = []
                            if modified != protobuf:
                                fixes.append("f4 vendor h3c_→h3c")
                            if sn_di and len(sn_di) == len(NX30PRO_SN) and sn_di != NX30PRO_SN:
                                modified = modified.replace(sn_di.encode(), NX30PRO_SN.encode())
                                fixes.append(f"f5 SN {sn_di}→{NX30PRO_SN}")
                            if fixes:
                                forward_data = raw[:8] + modified
                                new_total = 4 + len(modified)
                                forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                print(f"    >>> DeviceInfo: {', '.join(fixes)}")
                                modified_this_session = True
                        
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
                print(f"  [MOD] Registration messages were MODIFIED this session!")
            print(f"  [STATS] Total modified: {self.n_modified}, passed: {self.n_passed}")
            print(f"  [REF] Expected NX30Pro flow: Register(4F)→'not bound'→FullRegister(3F)→0x03→Heartbeat")

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
