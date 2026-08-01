#!/usr/bin/env python3
"""
UU Game Booster — Registration Protocol Simulator

Usage:
  # MITM mode: sit between container and server, log/modify traffic
  python uu_registry_sim.py mitm --listen 0.0.0.0:16000 --target 106.2.95.34:16000

  # Replay mode: replay captured registration to test SN
  python uu_registry_sim.py replay --sn 12345678900987654321 --target 106.2.95.34:16000

  # Probe mode: test a list of SNs
  python uu_registry_sim.py probe --target 106.2.95.34:16000
"""

import socket
import struct
import ssl
import sys
import argparse
import time
import json
import threading
from datetime import datetime

# ═══════════════════════════════════════════════════════════════════════════
# Protocol constants (reverse-engineered from MITM capture)
# ═══════════════════════════════════════════════════════════════════════════

H3C_SERVER = "106.2.95.34"
H3C_PORT = 16000

# Message types (4-byte big-endian)
MSG_REGISTER = 0x00000024   # Initial registration → response with router found/not found
MSG_REGISTER_RESP = 0x00000025
MSG_FULL_REG = 0x00000002   # Full registration with geo-location
MSG_LOG = 0x0000000A        # Log message
MSG_HEARTBEAT = 0x00000000  # Hello world heartbeat

# Registration fields (from protobuf analysis)
# Message type 0x24: fields = {1: rid, 2: model, 3: sn, 4: product, 5: version}
# Response 0x25:     fields = {1: rid, 2: status, 3: error_msg}

PROTO_VARINT = 0
PROTO_LEN_DELIM = 2


def pb_varint(val):
    """Encode protobuf varint."""
    result = []
    while val > 0x7F:
        result.append((val & 0x7F) | 0x80)
        val >>= 7
    result.append(val & 0x7F)
    return bytes(result)


def pb_field_wire(wire_type, field_num):
    """Encode protobuf field header (field_number << 3 | wire_type)."""
    return pb_varint((field_num << 3) | wire_type)


def pb_string(field_num, s):
    """Encode a protobuf string field."""
    data = s.encode() if isinstance(s, str) else s
    return pb_field_wire(PROTO_LEN_DELIM, field_num) + pb_varint(len(data)) + data


def pb_int32(field_num, val):
    """Encode a protobuf int32 field."""
    return pb_field_wire(PROTO_VARINT, field_num) + pb_varint(val)


def make_frame(msg_type, protobuf_data):
    """Wrap protobuf data in frame: [total_len:4][msg_type:4][protobuf]"""
    total_len = 4 + len(protobuf_data)  # includes msg_type field
    return struct.pack(">I", total_len) + struct.pack(">I", msg_type) + protobuf_data


def read_frame(sock):
    """Read a complete frame from socket."""
    # Read 4-byte total length
    header = b""
    while len(header) < 4:
        chunk = sock.recv(4 - len(header))
        if not chunk:
            return None, None, None
        header += chunk
    total_len = struct.unpack(">I", header)[0]

    # Read remaining data
    data = b""
    while len(data) < total_len:
        chunk = sock.recv(total_len - len(data))
        if not chunk:
            return None, None, None
        data += chunk

    msg_type = struct.unpack(">I", data[:4])[0]
    protobuf = data[4:]
    return total_len, msg_type, protobuf


def parse_registration(protobuf):
    """Parse registration protobuf into readable dict."""
    result = {}
    pos = 0
    while pos < len(protobuf):
        if pos >= len(protobuf):
            break
        # Read varint field header
        val = 0
        shift = 0
        while pos < len(protobuf):
            b = protobuf[pos]
            pos += 1
            val |= (b & 0x7F) << shift
            shift += 7
            if not (b & 0x80):
                break

        field_num = val >> 3
        wire_type = val & 0x07

        if wire_type == PROTO_VARINT:
            # Read varint value
            val = 0
            shift = 0
            while pos < len(protobuf):
                b = protobuf[pos]
                pos += 1
                val |= (b & 0x7F) << shift
                shift += 7
                if not (b & 0x80):
                    break
            result[field_num] = val

        elif wire_type == PROTO_LEN_DELIM:
            # Read length varint
            length = 0
            shift = 0
            while pos < len(protobuf):
                b = protobuf[pos]
                pos += 1
                length |= (b & 0x7F) << shift
                shift += 7
                if not (b & 0x80):
                    break
            # Read data
            data = protobuf[pos:pos + length]
            pos += length
            # Try as text
            try:
                result[field_num] = data.decode('utf-8', errors='replace')
            except:
                result[field_num] = data.hex()
        else:
            break

    return result


def build_register_msg(rid="0000000000000000", model="h3cnx30", sn="12345678900987654321",
                        product="NX30Pro", version="v14.3.0"):
    """Build TYPE 0x24 registration protobuf."""
    pb = b""
    pb += pb_string(1, rid)
    pb += pb_string(2, model)
    pb += pb_string(3, sn)
    pb += pb_string(4, product)
    pb += pb_string(5, version)
    return make_frame(MSG_REGISTER, pb)


def build_heartbeat(rid="0000000000000007", msg="Hello world", model="h3cnx30", sn="12345678900987654321"):
    """Build heartbeat message."""
    pb = b""
    pb += pb_string(1, rid)
    pb += pb_string(2, msg)
    pb += pb_string(3, model)
    pb += pb_string(4, sn)
    return make_frame(MSG_HEARTBEAT, pb)


# ═══════════════════════════════════════════════════════════════════════════
# MITM Proxy
# ═══════════════════════════════════════════════════════════════════════════

class MITMProxy:
    def __init__(self, listen_addr, target_addr):
        self.listen_host, self.listen_port = listen_addr.split(":")
        self.listen_port = int(self.listen_port)
        self.target_host, self.target_port = target_addr.split(":")
        self.target_port = int(self.target_port)
        self.conn_count = 0

    def start(self):
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((self.listen_host, self.listen_port))
        server.listen(5)
        print(f"[MITM] Listening on {self.listen_host}:{self.listen_port}")
        print(f"[MITM] Forwarding to {self.target_host}:{self.target_port}")

        while True:
            client, addr = server.accept()
            self.conn_count += 1
            print(f"\n{'='*70}")
            print(f"[+] [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Connection #{self.conn_count} from {addr[0]}:{addr[1]}")
            threading.Thread(target=self.handle, args=(client,), daemon=True).start()

    def handle(self, client):
        try:
            # Connect to real server
            server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server.settimeout(10)
            server.connect((self.target_host, self.target_port))
            print(f"[*] Connected to real server {self.target_host}:{self.target_port}")

            # TLS wrapping (both directions)
            # Client side: our container → MITM (MITM acts as server for client)
            try:
                client_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                client_ctx.check_hostname = False
                client_ctx.verify_mode = ssl.CERT_NONE
                # Use a self-signed cert
                client_ctx.load_cert_chain(
                    certfile="d:/code03/uugamebooster-docker/tools/mitm_cert.pem",
                    keyfile="d:/code03/uugamebooster-docker/tools/mitm_key.pem"
                )
                client_tls = client_ctx.wrap_socket(client, server_side=True)
                print("[*] Client TLS established")
            except Exception as e:
                print(f"[!] Client TLS setup failed: {e}")
                # Fallback: plain TCP
                client_tls = client
                print("[*] Fallback to plain TCP")

            # Server side: MITM → real server
            try:
                server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
                server_ctx.check_hostname = False
                server_ctx.verify_mode = ssl.CERT_NONE
                server_tls = server_ctx.wrap_socket(server, server_hostname=self.target_host)
                print("[*] Server TLS established")
            except Exception as e:
                print(f"[!] Server TLS failed: {e}")
                server_tls = server
                print("[*] Server fallback to plain TCP")

            self.relay(client_tls, server_tls)

        except Exception as e:
            print(f"[!] Error: {e}")
        finally:
            try:
                client.close()
            except:
                pass

    def relay(self, client, server):
        """Bidirectional relay with logging."""
        import select as sel

        client_buf = b""
        server_buf = b""
        c_to_s_total = 0
        s_to_c_total = 0

        while True:
            try:
                r, _, _ = sel.select([client, server], [], [], 5.0)
            except:
                break

            if not r:
                # Timeout — check if still alive
                continue

            for sock in r:
                try:
                    data = sock.recv(65536)
                except (ssl.SSLWantReadError, ssl.SSLWantWriteError, BlockingIOError):
                    continue
                except Exception:
                    return

                if not data:
                    print("[*] Connection closed")
                    return

                if sock is client:
                    # Forward to server
                    server.sendall(data)
                    c_to_s_total += len(data)

                    # Try to parse
                    if len(data) >= 4:
                        total_len = struct.unpack(">I", data[:4])[0]
                        msg_type = struct.unpack(">I", data[4:8])[0]
                        protobuf = data[8:4 + total_len]

                        print(f"\n  [{datetime.now().strftime('%H:%M:%S.%f')[:-3]}] CLIENT → SERVER  [{len(data)} bytes, total C→S: {c_to_s_total}]")
                        self.dump_hex(data[:min(len(data), 100)])
                        self.parse_msg(msg_type, protobuf)

                elif sock is server:
                    # Forward to client
                    client.sendall(data)
                    s_to_c_total += len(data)

                    if len(data) >= 4:
                        total_len = struct.unpack(">I", data[:4])[0]
                        msg_type = struct.unpack(">I", data[4:8])[0]
                        protobuf = data[8:4 + total_len]

                        print(f"\n  [{datetime.now().strftime('%H:%M:%S.%f')[:-3]}] SERVER → CLIENT  [{len(data)} bytes, total S→C: {s_to_c_total}]")
                        self.dump_hex(data[:min(len(data), 100)])
                        self.parse_response(msg_type, protobuf)

    def dump_hex(self, data):
        """Pretty hex dump."""
        for i in range(0, len(data), 32):
            chunk = data[i:i+32]
            hex_part = " ".join(f"{b:02x}" for b in chunk)
            text_part = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
            print(f"  {i:04x}: {hex_part:<96s} |{text_part}|")

    def parse_msg(self, msg_type, protobuf):
        """Parse and display client message."""
        parsed = parse_registration(protobuf)
        type_names = {
            0x24: "REGISTER",
            0x02: "FULL_REGISTER",
            0x0A: "LOG",
            0x00: "HEARTBEAT",
        }
        name = type_names.get(msg_type, f"UNKNOWN(0x{msg_type:02x})")
        print(f"    [MSG] type={name} fields={parsed}")

        # Show text fields
        for k, v in parsed.items():
            if isinstance(v, str) and len(v) < 200:
                print(f"    [TEXT field {k}] {v}")

    def parse_response(self, msg_type, protobuf):
        """Parse and display server response."""
        parsed = parse_registration(protobuf)
        type_names = {
            0x25: "REGISTER_RESP",
            0x01: "PONG",
        }
        name = type_names.get(msg_type, f"UNKNOWN(0x{msg_type:02x})")
        print(f"    [RESP] type={name} fields={parsed}")

        # Check for important messages
        for k, v in parsed.items():
            if isinstance(v, str):
                if "not found" in v.lower():
                    print(f"    ⚠️  ROUTER NOT FOUND!")
                elif "success" in v.lower():
                    print(f"    ✅ SUCCESS!")
                print(f"    [TEXT] {v}")


# ═══════════════════════════════════════════════════════════════════════════
# Replay / Probe Mode
# ═══════════════════════════════════════════════════════════════════════════

def try_register(target_host, target_port, sn, model="h3cnx30", timeout=10):
    """Connect to server and try registration with given SN."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((target_host, target_port))

        # Wrap with TLS (server uses ECDSA cert, we skip verification)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        tls = ctx.wrap_socket(sock, server_hostname=target_host)

        # Send registration
        frame = build_register_msg(sn=sn, model=model)
        tls.sendall(frame)

        # Read response
        _, msg_type, protobuf = read_frame(tls)
        if protobuf is None:
            tls.close()
            return "NO_RESPONSE"

        parsed = parse_registration(protobuf)
        tls.close()

        # Check result
        for _, v in parsed.items():
            if isinstance(v, str) and v:
                return v

        return str(parsed)
    except Exception as e:
        return f"ERROR: {e}"


def probe_sns(target, sns=None):
    """Test a list of SNs."""
    if ":" in target:
        host, port = target.split(":")
        port = int(port)
    else:
        host = target
        port = H3C_PORT

    if sns is None:
        sns = [
            "12345678900987654321",  # NX30Pro reference
            "00000000000000000000",  # all zeros
            "11111111111111111111",  # all ones
        ]

    # Also generate some random ones
    import random
    for _ in range(5):
        sns.append("".join(str(random.randint(0, 9)) for _ in range(20)))

    print(f"Probing {len(sns)} SNs against {host}:{port}...")
    print()

    for sn in sns:
        print(f"[SN: {sn}] ", end="", flush=True)
        result = try_register(host, port, sn)
        print(result)


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def generate_cert():
    """Generate self-signed cert for MITM."""
    cert_path = "d:/code03/uugamebooster-docker/tools/mitm_cert.pem"
    key_path = "d:/code03/uugamebooster-docker/tools/mitm_key.pem"

    import os
    if os.path.exists(cert_path) and os.path.exists(key_path):
        return

    print("[*] Generating self-signed MITM certificate...")
    from subprocess import run
    run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", key_path, "-out", cert_path,
        "-days", "365", "-subj", "/CN=MITM"
    ], check=True, capture_output=True)
    print("[OK] Certificate generated")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="UU Registry Protocol Simulator")
    sub = parser.add_subparsers(dest="mode")

    mitm_p = sub.add_parser("mitm", help="MITM proxy mode")
    mitm_p.add_argument("--listen", default="0.0.0.0:16000")
    mitm_p.add_argument("--target", default=f"{H3C_SERVER}:{H3C_PORT}")

    replay_p = sub.add_parser("replay", help="Replay single registration")
    replay_p.add_argument("--sn", required=True)
    replay_p.add_argument("--model", default="h3cnx30")
    replay_p.add_argument("--target", default=f"{H3C_SERVER}:{H3C_PORT}")

    probe_p = sub.add_parser("probe", help="Probe multiple SNs")
    probe_p.add_argument("--target", default=f"{H3C_SERVER}:{H3C_PORT}")

    args = parser.parse_args()

    if args.mode == "mitm":
        generate_cert()
        host, port = args.target.split(":")
        MITMProxy(args.listen, args.target).start()

    elif args.mode == "replay":
        host, port = args.target.split(":")
        result = try_register(host, int(port), args.sn, args.model)
        print(f"Result: {result}")

    elif args.mode == "probe":
        probe_sns(args.target)

    else:
        parser.print_help()
