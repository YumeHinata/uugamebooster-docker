#!/usr/bin/env python3
"""Event-driven uuclearnat — reads FIFO messages from uuplugin and responds immediately.

FIFO protocol: 20-byte binary messages
  Bytes 0-3:  total length (big-endian uint32, always 20)
  Bytes 4-7:  message type  (0=READY, 1=ALIVE, 9=client notification)
  Bytes 8-11: client IP     (big-endian uint32, network byte order)
  Bytes 12-19: padding

Replaces the polling-based bash implementation that had a race condition
(2s poll vs uuplugin's ~1s timeout).
"""

import os
import sys
import struct
import socket
import subprocess
import time
import select

FIFO_PATH = '/dev/natflushdev'
LOG_FILE = '/tmp/uuclearnat.log'
LAN_IF = 'br-lan'
TUN_IF = 'tun163'
TABLE_ID = 163
MARK_VAL = '0x163/0x163'
DNS_SERVER = '8.8.8.8'

# ── Helpers ──────────────────────────────────────────────────────────────────

def log(msg: str):
    ts = time.strftime('%H:%M:%S')
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f'{ts} uuclearnat: {msg}\n')
    except OSError:
        pass

def run(cmd: list, check: bool = False) -> subprocess.CompletedProcess:
    """Run a command, capture output, never raise on non-zero return."""
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except (subprocess.TimeoutExpired, OSError):
        return subprocess.CompletedProcess(cmd, -1, '', '')

def rule_exists(table: str, chain: str, rule_spec: list) -> bool:
    """Check if an iptables rule already exists (-C check)."""
    result = run(['iptables', '-w', '-t', table, '-C', chain] + rule_spec)
    return result.returncode == 0

def ip_to_str(ip_int: int) -> str:
    return socket.inet_ntoa(struct.pack('>I', ip_int))

def str_to_ip(ip_str: str) -> int:
    return struct.unpack('>I', socket.inet_aton(ip_str))[0]

# ── Rule management ──────────────────────────────────────────────────────────

def setup_rules_for_client(ip: str):
    """Create all acceleration rules for a game client."""
    created = []

    # 1) ip rule: from <IP> lookup 163
    result = run(['ip', 'rule', 'show'])
    if f'from {ip} lookup {TABLE_ID}' not in result.stdout:
        run(['ip', 'rule', 'add', 'from', ip, 'lookup', str(TABLE_ID)])
        created.append(f'ip rule add from {ip} lookup {TABLE_ID}')

    # 2) mangle PREROUTING MARK
    if not rule_exists('mangle', 'PREROUTING', ['-s', ip, '-j', 'MARK', '--set-mark', MARK_VAL]):
        run(['iptables', '-w', '-t', 'mangle', '-I', 'PREROUTING',
             '-s', ip, '-j', 'MARK', '--set-mark', MARK_VAL])
        created.append(f'mangle MARK {ip}')

    # 3) nat PREROUTING DNS DNAT
    if not rule_exists('nat', 'PREROUTING',
                       ['-i', LAN_IF, '-s', ip, '-p', 'udp', '--dport', '53',
                        '-j', 'DNAT', '--to-destination', DNS_SERVER]):
        run(['iptables', '-w', '-t', 'nat', '-I', 'PREROUTING',
             '-i', LAN_IF, '-s', ip, '-p', 'udp', '--dport', '53',
             '-j', 'DNAT', '--to-destination', DNS_SERVER])
        created.append(f'DNS DNAT {ip}')

    # 4) nat POSTROUTING MASQUERADE (one-time, not per-client)
    if not rule_exists('nat', 'POSTROUTING', ['-o', TUN_IF, '-j', 'MASQUERADE']):
        run(['iptables', '-w', '-t', 'nat', '-I', 'POSTROUTING',
             '-o', TUN_IF, '-j', 'MASQUERADE'])
        created.append(f'MASQUERADE {TUN_IF}')

    # 5) filter FORWARD tun163 (one-time)
    for dir_flag in ['-i', '-o']:
        if not rule_exists('filter', 'FORWARD', [dir_flag, TUN_IF, '-j', 'ACCEPT']):
            run(['iptables', '-w', '-t', 'filter', '-I', 'FORWARD',
                 dir_flag, TUN_IF, '-j', 'ACCEPT'])
            created.append(f'FORWARD {dir_flag} {TUN_IF} ACCEPT')

    for c in created:
        log(c)

    return len(created) > 0

def cleanup_client(ip: str):
    """Remove rules for a departed client."""
    run(['ip', 'rule', 'del', 'from', ip, 'lookup', str(TABLE_ID)])
    run(['iptables', '-w', '-t', 'mangle', '-D', 'PREROUTING',
         '-s', ip, '-j', 'MARK', '--set-mark', MARK_VAL])
    run(['iptables', '-w', '-t', 'nat', '-D', 'PREROUTING',
         '-i', LAN_IF, '-s', ip, '-p', 'udp', '--dport', '53',
         '-j', 'DNAT', '--to-destination', DNS_SERVER])
    log(f'cleanup client {ip}')

# ── FIFO message handling ────────────────────────────────────────────────────

def pack_msg(msg_type: int, ip_int: int = 0) -> bytes:
    """Pack a 20-byte FIFO message: 4B len + 4B type + 4B IP + 8B padding."""
    return struct.pack('>IIIQ', 20, msg_type, ip_int, 0)

def handle_message(msg_type: int, ip_int: int, w_fd: int, known_clients: set):
    """Process a received FIFO message."""
    ip_str = ip_to_str(ip_int) if ip_int else '0.0.0.0'

    if msg_type == 9:  # Client notification from uuplugin
        if ip_str != '0.0.0.0' and ip_str not in known_clients:
            log(f'client {ip_str} (type=9 from FIFO)')
            setup_rules_for_client(ip_str)
            known_clients.add(ip_str)
            # Send ACK: type=9 with same IP
            try:
                os.write(w_fd, pack_msg(9, ip_int))
                log(f'ACK sent for {ip_str}')
            except OSError:
                pass
        elif ip_str in known_clients:
            # Re-ACK for already-known client (uuplugin might be retrying)
            try:
                os.write(w_fd, pack_msg(9, ip_int))
            except OSError:
                pass
    elif msg_type == 0:
        log(f'FIFO READY from uuplugin (type=0)')
    elif msg_type == 1:
        pass  # ALIVE heartbeat - silent
    else:
        log(f'unknown msg type={msg_type} ip={ip_str}')

# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    log('event-driven uuclearnat starting')

    # Open FIFO with O_RDWR to prevent blocking (both ends in one fd)
    # This avoids the classic FIFO deadlock where open-for-read blocks
    # waiting for a writer, and open-for-write blocks waiting for a reader.
    try:
        fd = os.open(FIFO_PATH, os.O_RDWR)
    except OSError as e:
        log(f'FATAL: cannot open {FIFO_PATH}: {e}')
        sys.exit(1)

    # Send READY signal to uuplugin
    try:
        os.write(fd, pack_msg(0))  # type=0 READY
        log('sent READY')
    except OSError:
        pass

    known_clients: set = set()
    last_alive = time.time()

    while True:
        now = time.time()

        # ALIVE heartbeat every 30 seconds
        if now - last_alive >= 30:
            try:
                os.write(fd, pack_msg(1))  # type=1 ALIVE
            except OSError:
                pass
            last_alive = now

        # Read from FIFO with 1-second timeout
        try:
            ready, _, _ = select.select([fd], [], [], 1.0)
        except (select.error, ValueError, OSError):
            time.sleep(1)
            continue

        if not ready:
            continue

        try:
            data = os.read(fd, 20)
        except OSError:
            time.sleep(0.5)
            continue

        if len(data) < 20:
            # Partial read — likely EOF or pipe broken
            continue

        try:
            msg_len, msg_type, msg_ip, _ = struct.unpack('>IIIQ', data)
        except struct.error:
            continue

        if msg_len != 20:
            continue

        handle_message(msg_type, msg_ip, fd, known_clients)

if __name__ == '__main__':
    main()
