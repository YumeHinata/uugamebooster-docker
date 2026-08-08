#!/bin/sh
# natflushd.sh — FIFO protocol handler for uuplugin ↔ uuclearnat IPC
#
# Replaces the old uuclearnat shell script. Single process handles the
# /dev/natflushdev FIFO with proper binary protocol:
#
#   Message format (20 bytes, big-endian):
#     Bytes 0-3:  length (uint32, always 0x14=20)
#     Bytes 4-7:  type   (uint32: 0=READY, 1=ALIVE, 9=CLIENT_NOTIFY)
#     Bytes 8-11: IP     (uint32, network byte order)
#     Bytes 12-19: padding (zero)
#
# Uses SEPARATE file descriptors for read and write to avoid deadlock:
#   fd 3 = write-only  (opened with >)
#   fd 4 = read-only   (opened with <)
#
# Does NOT create iptables rules — uuplugin manages ALL rules itself.

FIFO=/dev/natflushdev
LOG=/tmp/natflushd.log
PIDFILE=/var/run/natflushd.pid

# ── Single instance guard ─────────────────────────────────────────────
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[$(date +%H:%M:%S)] $$ natflushd already running (pid=$OLD_PID), exiting" >> "$LOG"
        exit 0
    fi
fi
echo $$ > "$PIDFILE" 2>/dev/null

log() { echo "[$(date +%H:%M:%S)] $$ $1" >> "$LOG"; }

log "natflushd v2 starting (separate r/w fds)"

# ── Open FIFO: write fd first (prevents reader from blocking on open) ──
exec 3>"$FIFO" 2>/dev/null || { log "FATAL: cannot open $FIFO for writing"; exit 1; }
log "write fd 3 opened"

exec 4<"$FIFO" 2>/dev/null || { log "FATAL: cannot open $FIFO for reading"; exit 1; }
log "read fd 4 opened"

# ── Send READY (type=0) ──────────────────────────────────────────────
# Using printf with octal escapes for reliable binary output
printf '\x00\x00\x00\x14\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >&3
log "sent READY (type=0)"

# ── Helper: pack IP to 4 hex bytes ───────────────────────────────────
pack_ip() {
    # $1 = IP string "a.b.c.d" → output 4 raw bytes to stdout
    echo "$1" | awk -F. '{printf "%c%c%c%c", $1, $2, $3, $4}'
}

# ── Helper: send a 20B message ───────────────────────────────────────
send_msg() {
    # $1 = type (decimal), $2 = IP string (optional, default 0.0.0.0)
    _type=$1
    _ip="${2:-0.0.0.0}"
    _ip_bytes=$(pack_ip "$_ip")
    printf '\x00\x00\x00\x14' >&3
    printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
        $(( (_type >> 24) & 0xFF )) $(( (_type >> 16) & 0xFF )) \
        $(( (_type >> 8) & 0xFF ))  $(( _type & 0xFF )) )" >&3
    printf '%s' "$_ip_bytes" >&3
    printf '\x00\x00\x00\x00\x00\x00\x00\x00' >&3
}

# ── Main loop: read 20B messages, respond ────────────────────────────
COUNT=0
LAST_ALIVE=$(date +%s)

while true; do
    # Read exactly 20 bytes (blocking) as raw hex
    RAW=$(dd bs=20 count=1 <&4 2>/dev/null | od -A n -t x1 -v | tr -d ' \n')

    if [ -z "$RAW" ]; then
        log "FIFO read returned empty (EOF?), reopening in 3s..."
        exec 4<&- 2>/dev/null  # close old read fd
        sleep 3
        exec 4<"$FIFO" 2>/dev/null || { log "reopen read failed"; sleep 5; continue; }
        log "read fd 4 reopened"
        # No need to re-send READY — uuplugin still has its write fd open
        continue
    fi

    COUNT=$((COUNT + 1))

    # Parse 20B = 40 hex chars:
    #   chars 1-8   = len    (bytes 0-3)
    #   chars 9-16  = type   (bytes 4-7)
    #   chars 17-24 = IP     (bytes 8-11)
    #   chars 25-40 = padding

    LEN_HEX=$(echo "$RAW" | cut -c1-8)
    TYPE_HEX=$(echo "$RAW" | cut -c9-16)
    IP_HEX=$(echo "$RAW" | cut -c17-24)

    # Convert hex → decimal (handle leading zeros correctly)
    TYPE_DEC=$(printf "%d" "0x$TYPE_HEX" 2>/dev/null)

    # IP: 4 bytes hex → dotted decimal
    O1=$(printf "%d" "0x$(echo "$IP_HEX" | cut -c1-2)" 2>/dev/null)
    O2=$(printf "%d" "0x$(echo "$IP_HEX" | cut -c3-4)" 2>/dev/null)
    O3=$(printf "%d" "0x$(echo "$IP_HEX" | cut -c5-6)" 2>/dev/null)
    O4=$(printf "%d" "0x$(echo "$IP_HEX" | cut -c7-8)" 2>/dev/null)
    IP_STR="$O1.$O2.$O3.$O4"

    # Skip garbage: if type is > 1000, it's not a valid message
    if [ "$TYPE_DEC" -gt 1000 ] 2>/dev/null; then
        # Likely residual ASCII data. Log and skip without ACK.
        if [ $((COUNT % 20)) -eq 1 ]; then
            log "SKIP garbage #$COUNT type_hex=$TYPE_HEX ip_hex=$IP_HEX (residual buffer data)"
        fi
        continue
    fi

    # Type name
    case $TYPE_DEC in
        0) TNAME="READY" ;;
        1) TNAME="ALIVE" ;;
        9) TNAME="CLIENT_NOTIFY" ;;
        *) TNAME="UNKNOWN_$TYPE_DEC" ;;
    esac

    # Log (throttle ALIVE to every 10th)
    if [ "$TYPE_DEC" -ne 1 ] || [ $((COUNT % 10)) -eq 0 ]; then
        log "RX #$COUNT $TNAME ip=$IP_STR"
    fi

    # Handle CLIENT_NOTIFY (type=9): ACK with same type + same IP
    if [ "$TYPE_DEC" -eq 9 ] && [ "$IP_STR" != "0.0.0.0" ]; then
        send_msg 9 "$IP_STR"
        log "TX ACK type=9 ip=$IP_STR"
    fi

    # Send ALIVE heartbeat every 30s
    NOW=$(date +%s)
    if [ $((NOW - LAST_ALIVE)) -ge 30 ]; then
        send_msg 1 "0.0.0.0"
        LAST_ALIVE=$NOW
    fi

    # Periodic stats
    if [ $((COUNT % 100)) -eq 0 ]; then
        log "STATS: $COUNT messages processed, last type=$TNAME"
    fi
done
