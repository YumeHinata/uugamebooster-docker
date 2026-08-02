#!/usr/bin/env python3
"""
uu_mgmt_proxy.py — Local TCP proxy for uuplugin management ports

Problem: x86 uuplugin binary uses a custom TCP protocol (not standard SSH)
for mobile app binding on ports 16363/14554. The binary requires password
authentication, but the real H3C NX30Pro binary does NOT. This proxy
intercepts the auth handshake and either:

  Phase 1 (now): TRANSPARENT FORWARDING with hex dump logging
  Phase 2 (future): Modify auth responses to bypass password check

Architecture:
  Phone → Router:16363 → [iptables REDIRECT] → Proxy:16365 → Binary:16363
  Phone → Router:14554 → [iptables REDIRECT] → Proxy:14555 → Binary:14554

iptables rules (added by start.sh):
  iptables -t nat -A PREROUTING -p tcp --dport 16363 -j REDIRECT --to-port 16365
  iptables -t nat -A PREROUTING -p tcp --dport 14554 -j REDIRECT --to-port 14555
"""

import socket
import select
import threading
import time
import sys
import os

# ── Configuration ──────────────────────────────────────────────────────────
# The real binary binds to these ports on the router's LAN IP (e.g. 192.168.0.1)
# After REDIRECT, external connections arrive at our listen ports
# Our proxy then connects BACK to the real binary on its original ports

BINARY_HOST = os.environ.get('UU_LAN_IP', '192.168.1.1')
# Fallback: also try 127.0.0.1 if binary binds to INADDR_ANY
BINARY_HOSTS = [BINARY_HOST, '127.0.0.1']

PROXY_RULES = [
    # (label, listen_port, binary_port)
    ('MGMT',  16365, 16363),
    ('ACCEL', 14555, 14554),
]

# ── Hex dump helper ─────────────────────────────────────────────────────────
def hexdump(data, max_bytes=256):
    """Return hex + ASCII representation of binary data"""
    d = data[:max_bytes]
    hex_str = ' '.join(f'{b:02x}' for b in d)
    ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in d)
    suffix = f' ...(+{len(data)-max_bytes}B)' if len(data) > max_bytes else ''
    return f'({len(data)}B) {hex_str} |{ascii_str}|{suffix}'


# ── Bidirectional relay ────────────────────────────────────────────────────
def relay(client_sock, target_sock, client_addr, label):
    """Forward data bidirectionally between client and target, logging hex."""
    sockets = [client_sock, target_sock]
    client_closed = False
    target_closed = False

    try:
        while not (client_closed and target_closed):
            try:
                readable, _, exceptional = select.select(
                    [s for s in sockets if s is not None],
                    [],
                    [s for s in sockets if s is not None],
                    30.0
                )
            except (select.error, ValueError, OSError):
                break

            if exceptional:
                break

            for sock in readable:
                try:
                    data = sock.recv(65536)
                except (ConnectionResetError, BrokenPipeError, OSError):
                    data = None

                if not data:
                    # One side closed
                    if sock is client_sock:
                        client_closed = True
                        sockets[0] = None
                        if target_sock:
                            try:
                                target_sock.shutdown(socket.SHUT_WR)
                            except OSError:
                                pass
                    else:
                        target_closed = True
                        sockets[1] = None
                        if client_sock:
                            try:
                                client_sock.shutdown(socket.SHUT_WR)
                            except OSError:
                                pass
                    continue

                # Forward and log
                if sock is client_sock:
                    direction = 'C→S'
                    target_sock.sendall(data)
                else:
                    direction = 'S→C'
                    client_sock.sendall(data)

                # Log first few packets of each direction
                print(f'[{label}] {direction} {hexdump(data)}', flush=True)

    finally:
        for s in [client_sock, target_sock]:
            if s:
                try:
                    s.close()
                except OSError:
                    pass
    print(f'[{label}] Connection closed: {client_addr}', flush=True)


# ── Connection handler ──────────────────────────────────────────────────────
def connect_to_binary(label, binary_port):
    """Try to connect to binary on multiple possible addresses."""
    for host in BINARY_HOSTS:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3.0)
        try:
            sock.connect((host, binary_port))
            print(f'[{label}] Connected to binary at {host}:{binary_port}', flush=True)
            return sock
        except (ConnectionRefusedError, OSError, socket.timeout) as e:
            sock.close()
            print(f'[{label}] Binary not at {host}:{binary_port}: {e}', flush=True)
    return None


def handle_client(client_sock, client_addr, label, listen_port, binary_port):
    """Accept client connection and relay to binary."""
    target_sock = connect_to_binary(label, binary_port)
    if target_sock is None:
        print(f'[{label}] Cannot reach binary on any address, closing {client_addr}',
              flush=True)
        client_sock.close()
        return

    client_sock.setblocking(False)
    target_sock.setblocking(False)

    print(f'[{label}] Bridge: {client_addr} ↔ binary:{binary_port}', flush=True)
    relay(client_sock, target_sock, client_addr, label)


# ── TCP server (one per port pair) ──────────────────────────────────────────
def run_proxy(label, listen_port, binary_port):
    """Accept connections on listen_port, forward to binary_port."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    # Allow address reuse for faster restart
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)

    try:
        server.bind(('0.0.0.0', listen_port))
    except OSError as e:
        print(f'[{label}] FATAL: Cannot bind 0.0.0.0:{listen_port}: {e}', flush=True)
        return

    server.listen(32)
    print(f'[{label}] Listening 0.0.0.0:{listen_port} → {BINARY_HOST}:{binary_port}',
          flush=True)

    while True:
        try:
            client_sock, client_addr = server.accept()
            print(f'[{label}] New client: {client_addr}', flush=True)
            t = threading.Thread(
                target=handle_client,
                args=(client_sock, client_addr, label, listen_port, binary_port),
                daemon=True
            )
            t.start()
        except OSError:
            break


# ── Main ────────────────────────────────────────────────────────────────────
def main():
    print('=' * 60, flush=True)
    print('uu_mgmt_proxy — Local TCP proxy for uuplugin management ports',
          flush=True)
    print(f'Binary at {BINARY_HOST} (override with UU_LAN_IP env var)',
          flush=True)
    print('=' * 60, flush=True)

    threads = []
    for label, listen_port, binary_port in PROXY_RULES:
        t = threading.Thread(
            target=run_proxy,
            args=(label, listen_port, binary_port),
            daemon=True
        )
        t.start()
        threads.append(t)

    print('[PROXY] All listeners started. Waiting for connections...', flush=True)

    try:
        while True:
            time.sleep(5)
            alive = sum(1 for t in threads if t.is_alive())
            if alive == 0:
                print('[PROXY] All listeners died. Exiting.', flush=True)
                break
    except KeyboardInterrupt:
        print('[PROXY] Shutting down...', flush=True)


if __name__ == '__main__':
    main()
