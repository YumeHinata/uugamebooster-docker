#!/usr/bin/env python3
"""natflushd — FIFO passthrough monitor for uuplugin ↔ uuclearnat IPC.

NOT the real uuclearnat. This is a protocol observer that:
  1. Opens /dev/natflushdev (O_RDWR to prevent deadlock)
  2. Sends READY(0) + periodic ALIVE(1) — what uuplugin expects
  3. Logs EVERY message received from uuplugin with type + IP
  4. ACKs client notifications (type=9) — the bare minimum protocol

Does NOT create iptables rules — uuplugin handles ALL rule management itself.
The real /usr/bin/uuclearnat on OpenWrt is a conntrack learn/flush daemon.

FIFO message format (20 bytes):
  Bytes 0-3:  length (big-endian uint32, always 0x14=20)
  Bytes 4-7:  type   (0=READY, 1=ALIVE, 9=client notify, ...)
  Bytes 8-11: IP     (big-endian uint32, network byte order)
  Bytes 12-19: padding (zero)
"""

import os
import sys
import struct
import socket
import time
import select
import signal

FIFO_PATH = '/dev/natflushdev'
LOG = '/tmp/natflushd.log'
ALIVE_INTERVAL = 30

# ── Helpers ──────────────────────────────────────────────────────────────────

def log(msg: str):
    ts = time.strftime('%H:%M:%S')
    try:
        with open(LOG, 'a') as f:
            f.write(f'{ts} natflushd: {msg}\n')
    except OSError:
        pass

def ip_to_str(ip_int: int) -> str:
    if ip_int == 0:
        return '0.0.0.0'
    return socket.inet_ntoa(struct.pack('>I', ip_int))

def pack_msg(msg_type: int, ip_int: int = 0) -> bytes:
    """20-byte FIFO message: len(4) + type(4) + ip(4) + pad(8)."""
    return struct.pack('>IIIQ', 20, msg_type, ip_int, 0)

# ── Message type names ──────────────────────────────────────────────────────

TYPE_NAMES = {
    0: 'READY',
    1: 'ALIVE',
    2: 'TYPE_2',
    3: 'TYPE_3',
    4: 'TYPE_4',
    5: 'TYPE_5',
    6: 'TYPE_6',
    7: 'TYPE_7',
    8: 'TYPE_8',
    9: 'CLIENT_NOTIFY',
    10: 'TYPE_10',
}

def type_name(t: int) -> str:
    return TYPE_NAMES.get(t, f'TYPE_{t}')

# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    # Redirect stdout to log so background process doesn't hold terminal
    sys.stdout = open(LOG, 'a')
    sys.stderr = sys.stdout

    log('natflushd starting (FIFO monitor + minimal responder)')

    # Open FIFO with O_RDWR — prevents classic FIFO deadlock
    # (open-for-read blocks until writer; open-for-write blocks until reader)
    try:
        fd = os.open(FIFO_PATH, os.O_RDWR)
    except OSError as e:
        log(f'FATAL: cannot open {FIFO_PATH}: {e}')
        sys.exit(1)
    log(f'FIFO {FIFO_PATH} opened (fd={fd})')

    # Send READY (type=0)
    try:
        os.write(fd, pack_msg(0, 0))
        log('sent READY (type=0)')
    except OSError as e:
        log(f'WARN: write READY failed: {e}')

    last_alive = time.time()
    msg_count = 0
    unknown_types = set()

    while True:
        now = time.time()

        # ALIVE heartbeat
        if now - last_alive >= ALIVE_INTERVAL:
            try:
                os.write(fd, pack_msg(1, 0))
                log('sent ALIVE (type=1)')
            except OSError:
                pass
            last_alive = now

        # Read with 2-second timeout
        try:
            ready, _, _ = select.select([fd], [], [], 2.0)
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
            log(f'PARTIAL_READ: got {len(data)} bytes (expected 20): {data.hex()}')
            continue

        try:
            msg_len, msg_type, msg_ip, padding = struct.unpack('>IIIQ', data)
        except struct.error:
            log(f'UNPACK_FAIL: {data.hex()}')
            continue

        if msg_len != 20:
            log(f'BAD_LEN: {msg_len} (expected 20), type={msg_type}, ip={ip_to_str(msg_ip)}')
            continue

        msg_count += 1
        tname = type_name(msg_type)
        ip = ip_to_str(msg_ip)

        # Log unknown types once
        if msg_type not in TYPE_NAMES and msg_type not in unknown_types:
            unknown_types.add(msg_type)
            log(f'NEW_TYPE_DISCOVERED: type={msg_type} ip={ip} raw={data.hex()}')

        # Periodic summary every 50 messages
        if msg_count % 50 == 0:
            log(f'STATS: {msg_count} msgs received, unknown_types={sorted(unknown_types)}')

        # Handle known message types
        if msg_type == 9:  # CLIENT_NOTIFY
            log(f'RX CLIENT_NOTIFY ip={ip} (msg #{msg_count})')
            # ACK: echo back type=9 with same IP
            try:
                os.write(fd, pack_msg(9, msg_ip))
                log(f'TX ACK type=9 ip={ip}')
            except OSError:
                log(f'WARN: ACK write failed for ip={ip}')
        elif msg_type == 0:
            log(f'RX READY from uuplugin (msg #{msg_count})')
        elif msg_type == 1:
            pass  # ALIVE — silent, too noisy
        else:
            log(f'RX {tname} ip={ip} (msg #{msg_count})')

if __name__ == '__main__':
    main()
