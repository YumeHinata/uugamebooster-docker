#!/usr/bin/env python3
"""
UU Game Booster — Full Protocol Analyzer + MITM

Captures, parses, and analyzes the complete registration/binding protocol
between the UU plugin container and H3C servers.

Usage:
  # Generate MITM certificate first (one time):
  python uu_analyzer.py gencert

  # Run MITM (capture all traffic):
  python uu_analyzer.py mitm --listen 0.0.0.0:16000 --target <server_ip>:16000

  # Replay captured session with modified parameters:
  python uu_analyzer.py replay --session capture.json --sn NEWSN --model h3cnx30

  # Probe server with different registration parameters:
  python uu_analyzer.py probe --target <server_ip>:16000
"""

import socket
import ssl
import struct
import json
import os
import sys
import time
import threading
import argparse
import select
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════
SCRIPT_DIR = Path(__file__).parent
CERT_FILE = SCRIPT_DIR / "mitm_cert.pem"
KEY_FILE = SCRIPT_DIR / "mitm_key.pem"
CAPTURE_DIR = SCRIPT_DIR / "captures"

# Known H3C servers (from strace analysis)
KNOWN_SERVERS = {
    "106.2.95.34": "Primary registration",
    "106.2.59.231": "Secondary",
    "59.111.45.61": "CDN/API",
    "42.186.111.127": "h3crglg.uu.163.com",
}

# Protobuf message type names (from binary analysis)
MSG_TYPES = {
    0x00: "Heartbeat/Ping",
    0x01: "Pong/Echo",
    0x02: "FullRegister",
    0x03: "Acc(Account)",
    0x04: "Time",
    0x05: "Echo",
    0x06: "Device",
    0x07: "Connect",
    0x08: "AccAgain",
    0x09: "BoundUser",
    0x0A: "Log",
    0x0B: "Uninstall",
    0x0C: "CaptivePortal",
    0x0D: "DeviceList",
    0x0E: "BindCodeRequest",
    0x0F: "BindCodeReply",
    0x10: "ConnectRequest",
    0x11: "ConnectReply",
    0x12: "Disconnect",
    0x13: "DisconnectReply",
    0x14: "CheckBound",
    0x15: "CheckBoundReply",
    0x16: "FenceModeLatency",
    0x17: "FenceModeCtrl",
    0x18: "GTSinglePlayerStart",
    0x19: "GTSinglePlayerStop",
    0x1A: "Online",
    0x1B: "OnlineReply",
    0x1C: "ServerPing",
    0x1D: "ServerPingReply",
    0x1E: "CodeBoundEvent",
    0x1F: "GTClickOffline",
    0x20: "RemoteLinkConfig",
    0x21: "RouterGatewayHijack",
    0x22: "GamingServerLatency",
    0x23: "LatencyStat",
    0x24: "Register",
    0x25: "RegisterResp",
    0x26: "CheckUpgrade",
    0x27: "Upgrade",
    0x28: "LogCtrl",
    0x29: "MacList",
    0x2A: "UserMessage",
    0x2B: "StartRtmp",
    0x2C: "StartRtmpReply",
    0x2D: "StopRtmp",
    0x2E: "StopRtmpReply",
    0x2F: "StopAcc",
    0x30: "StopAccReply",
    0x31: "Wol",
    0x32: "WolReply",
}

# ═══════════════════════════════════════════════════════════════════════════
# Protobuf Parser
# ═══════════════════════════════════════════════════════════════════════════

def pb_read_varint(data, pos):
    """Read a protobuf varint starting at pos, return (value, new_pos)."""
    value = 0
    shift = 0
    while pos < len(data):
        b = data[pos]
        pos += 1
        value |= (b & 0x7F) << shift
        shift += 7
        if not (b & 0x80):
            break
    return value, pos

def pb_parse(data, max_depth=5):
    """Parse protobuf data into a readable dict. Returns parsed data."""
    result = {}
    pos = 0
    while pos < len(data):
        if pos >= len(data):
            break
        try:
            field_header, pos = pb_read_varint(data, pos)
        except:
            break
        
        field_num = field_header >> 3
        wire_type = field_header & 0x07
        
        if wire_type == 0:  # Varint
            val, pos = pb_read_varint(data, pos)
            result[field_num] = val
        
        elif wire_type == 2:  # Length-delimited
            length, pos = pb_read_varint(data, pos)
            if pos + length > len(data):
                break
            raw = data[pos:pos + length]
            pos += length
            
            # Try to decode as string
            try:
                text = raw.decode('utf-8')
                if all(32 <= ord(c) < 127 or c in '\n\r\t' for c in text):
                    result[field_num] = text
                    continue
            except:
                pass
            
            # Try as nested message
            try:
                nested = pb_parse(raw, max_depth - 1)
                if nested:
                    result[field_num] = nested
                    continue
            except:
                pass
            
            # Fallback: hex
            result[field_num] = f"<{len(raw)} bytes: {raw[:32].hex()}>"
    
    return result

def pb_encode_field(field_num, wire_type, value):
    """Encode a protobuf field."""
    header = b''
    v = (field_num << 3) | wire_type
    while v > 0x7F:
        header += bytes([(v & 0x7F) | 0x80])
        v >>= 7
    header += bytes([v & 0x7F])
    
    if wire_type == 0:  # Varint
        body = b''
        while value > 0x7F:
            body += bytes([(value & 0x7F) | 0x80])
            value >>= 7
        body += bytes([value & 0x7F])
        return header + body
    
    elif wire_type == 2:  # Length-delimited
        if isinstance(value, str):
            value = value.encode('utf-8')
        elif isinstance(value, dict):
            value = pb_encode_dict(value)
        length = len(value)
        len_bytes = b''
        while length > 0x7F:
            len_bytes += bytes([(length & 0x7F) | 0x80])
            length >>= 7
        len_bytes += bytes([length & 0x7F])
        return header + len_bytes + value
    
    return header

def pb_encode_dict(data):
    """Encode a dict as protobuf."""
    result = b''
    for field_num, value in sorted(data.items()):
        if isinstance(value, int):
            result += pb_encode_field(field_num, 0, value)
        elif isinstance(value, (str, bytes)):
            result += pb_encode_field(field_num, 2, value)
        elif isinstance(value, dict):
            result += pb_encode_field(field_num, 2, value)
    return result

# ═══════════════════════════════════════════════════════════════════════════
# Frame Parser
# ═══════════════════════════════════════════════════════════════════════════

class UUFrame:
    """Represents a single UU protocol frame."""
    def __init__(self, total_len, msg_type, protobuf, raw=None):
        self.total_len = total_len
        self.msg_type = msg_type
        self.protobuf = protobuf
        self.raw = raw
        self.parsed = None
    
    @property
    def type_name(self):
        return MSG_TYPES.get(self.msg_type, f"Unknown(0x{self.msg_type:02x})")
    
    def parse(self):
        if self.parsed is None and self.protobuf:
            self.parsed = pb_parse(self.protobuf)
        return self.parsed
    
    def __repr__(self):
        parsed = self.parse()
        ts = self.type_name
        return f"UUFrame(type={ts}, len={self.total_len}, fields={parsed})"

def read_frame(sock):
    """Read a complete UU frame from socket. Returns UUFrame or None."""
    try:
        # Read 4-byte header
        header = b''
        while len(header) < 4:
            chunk = sock.recv(4 - len(header))
            if not chunk:
                return None
            header += chunk
        
        total_len = struct.unpack(">I", header)[0]
        if total_len > 1024 * 1024:  # sanity check
            return None
        
        # Read body
        body = b''
        while len(body) < total_len:
            chunk = sock.recv(total_len - len(body))
            if not chunk:
                return None
            body += chunk
        
        msg_type = struct.unpack(">I", body[:4])[0]
        protobuf = body[4:]
        
        return UUFrame(total_len, msg_type, protobuf, raw=header + body)
    except:
        return None

def make_frame(msg_type, protobuf_data):
    """Create a raw frame for sending."""
    total_len = 4 + len(protobuf_data)
    header = struct.pack(">I", total_len) + struct.pack(">I", msg_type)
    return header + protobuf_data

# ═══════════════════════════════════════════════════════════════════════════
# Session Capture
# ═══════════════════════════════════════════════════════════════════════════

class SessionCapture:
    """Records a full bidirectional session."""
    def __init__(self):
        self.messages = []  # list of {direction, ts, frame}
        self.start_time = datetime.now()
        self.meta = {}
    
    def record(self, direction, frame):
        self.messages.append({
            "direction": direction,
            "timestamp": datetime.now().isoformat(),
            "frame_type": frame.msg_type,
            "frame_name": frame.type_name,
            "total_len": frame.total_len,
            "protobuf_hex": frame.protobuf.hex() if frame.protobuf else "",
            "parsed": frame.parse(),
        })
    
    def save(self, filepath):
        with open(filepath, 'w') as f:
            json.dump({
                "meta": self.meta,
                "messages": self.messages,
            }, f, indent=2, ensure_ascii=False)
    
    @classmethod
    def load(cls, filepath):
        with open(filepath) as f:
            data = json.load(f)
        cap = cls()
        cap.messages = data["messages"]
        cap.meta = data.get("meta", {})
        return cap

# ═══════════════════════════════════════════════════════════════════════════
# MITM Proxy
# ═══════════════════════════════════════════════════════════════════════════

COLORS = {
    'C2S': '\033[92m',  # green: client→server
    'S2C': '\033[93m',  # yellow: server→client
    'INFO': '\033[96m',  # cyan
    'ERR': '\033[91m',   # red
    'RESET': '\033[0m',
}

def hexdump(data, indent=4, max_len=256):
    """Pretty hex dump."""
    prefix = " " * indent
    lines = []
    data = data[:max_len]
    for i in range(0, len(data), 32):
        chunk = data[i:i+32]
        hex_part = ' '.join(f'{b:02x}' for b in chunk)
        ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
        lines.append(f"{prefix}{i:04x}: {hex_part:<96s} |{ascii_part}|")
    if len(data) >= max_len:
        lines.append(f"{prefix}... (truncated)")
    return '\n'.join(lines)

class UUMITM:
    def __init__(self, listen_host, listen_port, target_host, target_port, 
                 modify=False, capture=True):
        self.listen_addr = (listen_host, listen_port)
        self.target_addr = (target_host, target_port)
        self.modify = modify
        self.do_capture = capture
        self.conn_id = 0
        self.captures = []
        
    def start(self):
        self.server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.server_ctx.load_cert_chain(str(CERT_FILE), str(KEY_FILE))
        self.server_ctx.verify_mode = ssl.CERT_NONE
        self.server_ctx.check_hostname = False
        
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(self.listen_addr)
        sock.listen(10)
        
        print(f"{COLORS['INFO']}[MITM] Listening on {self.listen_addr[0]}:{self.listen_addr[1]}{COLORS['RESET']}")
        print(f"{COLORS['INFO']}[MITM] Upstream: {self.target_addr[0]}:{self.target_addr[1]}{COLORS['RESET']}")
        print(f"{COLORS['INFO']}[MITM] Capture: {self.do_capture}, Modify: {self.modify}{COLORS['RESET']}")
        print()
        
        while True:
            try:
                client, addr = sock.accept()
                self.conn_id += 1
                print(f"\n{COLORS['INFO']}{'═'*70}{COLORS['RESET']}")
                print(f"{COLORS['INFO']}[+] Connection #{self.conn_id} from {addr[0]}:{addr[1]}{COLORS['RESET']}")
                t = threading.Thread(target=self.handle, args=(client, addr), daemon=True)
                t.start()
            except KeyboardInterrupt:
                print("\n[MITM] Shutting down...")
                break
    
    def handle(self, client_sock, client_addr):
        session = SessionCapture()
        server_sock = None
        client_tls = None
        server_tls = None
        
        try:
            # Step 1: TLS with client
            client_tls = self.server_ctx.wrap_socket(client_sock, server_side=True)
            print(f"  {COLORS['INFO']}[TLS] Client: {client_tls.version()}/{client_tls.cipher()[0]}{COLORS['RESET']}")
            
            # Step 2: Connect to real server
            server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server_sock.settimeout(10)
            server_sock.connect(self.target_addr)
            
            client_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            client_ctx.check_hostname = False
            client_ctx.verify_mode = ssl.CERT_NONE
            server_tls = client_ctx.wrap_socket(server_sock)
            print(f"  {COLORS['INFO']}[TLS] Server: {server_tls.version()}/{server_tls.cipher()[0]}{COLORS['RESET']}")
            print(f"  {COLORS['INFO']}[*] Relay active...{COLORS['RESET']}")
            
            # Step 3: Bidirectional relay
            client_tls.setblocking(False)
            server_tls.setblocking(False)
            
            c_buf = b''
            s_buf = b''
            
            while True:
                try:
                    r, _, _ = select.select([client_tls, server_tls], [], [], 30.0)
                except:
                    break
                
                if not r:
                    continue
                
                for sock in r:
                    if sock is client_tls:
                        done = self._relay(client_tls, server_tls, c_buf, 
                                          "CLIENT→SERVER", session, "C2S")
                        if not done:
                            return
                    elif sock is server_tls:
                        done = self._relay(server_tls, client_tls, s_buf,
                                          "SERVER→CLIENT", session, "S2C")
                        if not done:
                            return
        
        except Exception as e:
            print(f"  {COLORS['ERR']}[!] Error: {e}{COLORS['RESET']}")
            import traceback
            traceback.print_exc()
        finally:
            for s in [client_tls, server_tls, client_sock, server_sock]:
                try: s.close()
                except: pass
            
            # Save capture
            if self.do_capture and session.messages:
                CAPTURE_DIR.mkdir(exist_ok=True)
                fname = f"capture_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{self.conn_id}.json"
                fpath = CAPTURE_DIR / fname
                session.save(str(fpath))
                print(f"  {COLORS['INFO']}[*] Session saved: {fpath}{COLORS['RESET']}")
            
            print(f"  {COLORS['INFO']}[*] Connection #{self.conn_id} closed{COLORS['RESET']}")
    
    def _relay(self, src, dst, buf, label, session, dir_key):
        """Relay data from src to dst, return True if ok, False if closed."""
        try:
            data = src.recv(65536)
        except (ssl.SSLWantReadError, BlockingIOError):
            return True
        except:
            return False
        
        if not data:
            return False
        
        # Buffer and parse frames
        buf += data
        frames = []
        while len(buf) >= 4:
            total_len = struct.unpack(">I", buf[:4])[0]
            if total_len > 1024 * 1024:
                buf = b''
                break
            frame_end = 4 + total_len
            if len(buf) < frame_end:
                break
            raw_frame = buf[:frame_end]
            buf = buf[frame_end:]
            
            msg_type = struct.unpack(">I", raw_frame[4:8])[0]
            protobuf = raw_frame[8:]
            frame = UUFrame(total_len, msg_type, protobuf, raw=raw_frame)
            frames.append(frame)
        
        # Log and forward
        for frame in frames:
            color = COLORS['C2S'] if dir_key == 'C2S' else COLORS['S2C']
            ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
            
            print(f"\n  {color}[{ts}] {label}  [{frame.total_len} bytes]{COLORS['RESET']}")
            print(hexdump(frame.raw, indent=4))
            
            parsed = frame.parse()
            if parsed:
                # Pretty print specific known fields
                for fn, fv in parsed.items():
                    if isinstance(fv, str) and len(fv) < 200:
                        print(f"    field {fn}: \"{fv}\"")
                    elif isinstance(fv, int):
                        print(f"    field {fn}: {fv}")
                    elif isinstance(fv, dict):
                        for k, v in fv.items():
                            if isinstance(v, str) and len(v) < 100:
                                print(f"    field {fn}.{k}: \"{v}\"")
            
            print(f"    {COLORS['INFO']}[MSG] {frame.type_name}{COLORS['RESET']}")
            
            # Check for important messages
            for fn, fv in parsed.items():
                if isinstance(fv, str):
                    if 'not found' in fv.lower():
                        print(f"    {COLORS['ERR']}⚠️  ROUTER NOT FOUND!{COLORS['RESET']}")
                    elif 'found' in fv.lower() and 'not' not in fv.lower():
                        print(f"    {COLORS['INFO']}✅ DEVICE FOUND!{COLORS['RESET']}")
                    elif 'success' in fv.lower():
                        print(f"    {COLORS['INFO']}✅ SUCCESS!{COLORS['RESET']}")
                    elif 'error' in fv.lower():
                        print(f"    {COLORS['ERR']}❌ ERROR: {fv}{COLORS['RESET']}")
            
            # Record in session
            session.record(dir_key, frame)
        
        # Forward original data to destination
        try:
            dst.sendall(data)
        except:
            return False
        
        return True

# ═══════════════════════════════════════════════════════════════════════════
# Replay / Probe Mode
# ═══════════════════════════════════════════════════════════════════════════

def probe_server(target_host, target_port, sn_list=None, model="h3cnx30", 
                 product="NX30Pro", version="v14.3.0"):
    """Probe server with different SNs and registration parameters."""
    if sn_list is None:
        sn_list = [
            # Reference NX30Pro SN from factoryinfo
            "12345678900987654321",
            # Our generated SN
            "60996409814941919277",
            # All zeros
            "00000000000000000000",
            # Various formats
            "H3CNX30PRO000000001",
            "NX30PRO000000000001",
        ]
    
    print(f"Probing {target_host}:{target_port} with {len(sn_list)} SNs...")
    print()
    
    for sn in sn_list:
        print(f"[SN: {sn}] ", end="", flush=True)
        try:
            sock = socket.socket()
            sock.settimeout(10)
            sock.connect((target_host, target_port))
            
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            tls = ctx.wrap_socket(sock)
            
            # Build registration message (type 0x24)
            pb = pb_encode_dict({
                1: "0000000000000000",   # rid
                2: model,                 # model
                3: sn,                    # SN
                4: product,               # product name
                5: version,               # version
            })
            frame = make_frame(0x24, pb)
            tls.sendall(frame)
            
            # Read response
            resp = read_frame(tls)
            if resp:
                parsed = resp.parse()
                # Extract status message
                status = None
                for k, v in parsed.items():
                    if isinstance(v, str) and v:
                        status = v
                        break
                print(f"→ {resp.type_name}: {status or parsed}")
            else:
                print("→ NO RESPONSE (timeout)")
            
            tls.close()
        except Exception as e:
            print(f"→ ERROR: {e}")
        
        time.sleep(1)

# ═══════════════════════════════════════════════════════════════════════════
# Cert Generation
# ═══════════════════════════════════════════════════════════════════════════

def generate_cert():
    """Generate self-signed cert for MITM."""
    if CERT_FILE.exists() and KEY_FILE.exists() and KEY_FILE.stat().st_size > 0:
        print(f"[*] Certificate already exists: {CERT_FILE}")
        return
    
    print("[*] Generating self-signed MITM certificate...")
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.backends import default_backend
    import datetime
    
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048, backend=default_backend())
    
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "CN"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "MITM Proxy"),
        x509.NameAttribute(NameOID.COMMON_NAME, "rglg.uu.163.com"),
    ])
    
    cert = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer
    ).public_key(
        key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.datetime.utcnow()
    ).not_valid_after(
        datetime.datetime.utcnow() + datetime.timedelta(days=3650)
    ).add_extension(
        x509.SubjectAlternativeName([
            x509.DNSName("rglg.uu.163.com"),
            x509.DNSName("rglg.uu.netease.com"),
            x509.DNSName("*.uu.163.com"),
        ]),
        critical=False,
    ).sign(key, hashes.SHA256(), default_backend())
    
    with open(KEY_FILE, "wb") as f:
        f.write(key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        ))
    
    with open(CERT_FILE, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    
    print(f"[OK] Certificate saved: {CERT_FILE}")

# ═══════════════════════════════════════════════════════════════════════════
# Session Analyzer
# ═══════════════════════════════════════════════════════════════════════════

def analyze_capture(filepath):
    """Analyze a saved session capture."""
    cap = SessionCapture.load(filepath)
    
    print(f"\n{'='*70}")
    print(f"  Session Analysis: {filepath}")
    print(f"{'='*70}")
    print(f"  Messages: {len(cap.messages)}")
    
    # Count message types
    type_counts = {}
    for msg in cap.messages:
        name = msg['frame_name']
        type_counts[name] = type_counts.get(name, 0) + 1
    
    print(f"\n  Message type distribution:")
    for name, count in sorted(type_counts.items(), key=lambda x: -x[1]):
        print(f"    {name}: {count}")
    
    # Show first few messages
    print(f"\n  Message sequence:")
    for i, msg in enumerate(cap.messages[:20]):
        direction = msg['direction']
        name = msg['frame_name']
        parsed = msg.get('parsed', {})
        # Extract key fields
        key_fields = {}
        for k, v in parsed.items():
            if isinstance(v, str) and len(v) < 100:
                key_fields[k] = v
            elif isinstance(v, dict):
                for sk, sv in v.items():
                    if isinstance(sv, str) and len(sv) < 50:
                        key_fields[f"{k}.{sk}"] = sv
        
        print(f"    [{i}] {direction} {name}: {key_fields}")

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="UU Protocol Analyzer + MITM")
    sub = parser.add_subparsers(dest="mode")
    
    # gencert
    sub.add_parser("gencert", help="Generate MITM certificate")
    
    # mitm
    mitm_p = sub.add_parser("mitm", help="MITM proxy mode")
    mitm_p.add_argument("--listen", default="0.0.0.0:16000")
    mitm_p.add_argument("--target", required=True)
    mitm_p.add_argument("--modify", action="store_true", help="Enable message modification (not yet)")
    mitm_p.add_argument("--no-capture", action="store_true")
    
    # probe
    probe_p = sub.add_parser("probe", help="Probe server with test registrations")
    probe_p.add_argument("--target", required=True)
    probe_p.add_argument("--sn", help="Single SN to test")
    probe_p.add_argument("--model", default="h3cnx30")
    probe_p.add_argument("--product", default="NX30Pro")
    
    # replay
    replay_p = sub.add_parser("replay", help="Replay a captured session")
    replay_p.add_argument("--session", required=True)
    replay_p.add_argument("--target", required=True)
    
    # analyze
    analyze_p = sub.add_parser("analyze", help="Analyze a capture file")
    analyze_p.add_argument("--session", required=True)
    
    args = parser.parse_args()
    
    if args.mode == "gencert":
        generate_cert()
    
    elif args.mode == "mitm":
        generate_cert()
        listen_host, listen_port = args.listen.split(":")
        target_host, target_port = args.target.split(":")
        mitm = UUMITM(listen_host, int(listen_port), target_host, int(target_port),
                      modify=args.modify, capture=not args.no_capture)
        mitm.start()
    
    elif args.mode == "probe":
        host, port = args.target.split(":")
        sn_list = [args.sn] if args.sn else None
        probe_server(host, int(port), sn_list, args.model, args.product)
    
    elif args.mode == "replay":
        # Load session, replay with modifications
        host, port = args.target.split(":")
        cap = SessionCapture.load(args.session)
        print(f"Loaded session: {len(cap.messages)} messages")
        print("Replay not yet implemented")
    
    elif args.mode == "analyze":
        analyze_capture(args.session)
    
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
