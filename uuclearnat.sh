#!/bin/sh
# ============================================================================
# uuclearnat replacement for QEMU/Docker container
# uuplugin callback: sh -c "/bin/sh /usr/bin/uuclearnat > /dev/null 2>&1 &"
#
# IPC protocol: uuplugin ↔ uuclearnat via /dev/natflushdev (FIFO)
#   - QEMU_LD_PREFIX translates /dev/natflushdev → /arm-root/dev/natflushdev
#   - Since this script runs natively (x86_64), we access /arm-root/dev/natflushdev
#   - uuplugin writes commands, expects responses
#   - Real uuclearnat monitors /proc/net/nf_conntrack for NAT flows
#
# Responsibilities:
#   1. Open /dev/natflushdev FIFO for bidirectional IPC
#   2. Create tun163 + policy routing table 163
#   3. Monitor mangle INPUT for client DROP rules (uuplugin acceleration signal)
#   4. Monitor /proc/net/nf_conntrack for active game flows
#   5. Write client updates back to FIFO (when protocol is understood)
# ============================================================================

# QEMU translates /dev/natflushdev → /arm-root/dev/natflushdev
# Our native shell accesses it directly at /arm-root/dev/natflushdev
NATFLUSH="/arm-root/dev/natflushdev"
TUN="tun163"
TABLE="163"
FWMARK="0x163"
LOG="/tmp/uuclearnat.log"
RXLOG="/tmp/natflush_rx.log"
: > "$LOG"
: > "$RXLOG"

log() { echo "[$(date +%H:%M:%S)] $$ $1" >> "$LOG"; }
die() { log "FATAL: $1"; exit 1; }

log "=== uuclearnat starting (pid $$) ==="

# ── 0. FIFO setup ──────────────────────────────────────────────────────────
if [ ! -p "$NATFLUSH" ]; then
    log "creating FIFO $NATFLUSH"
    rm -f "$NATFLUSH"
    mkfifo "$NATFLUSH" 2>/dev/null || {
        # mkfifo might fail if dir doesn't exist
        mkdir -p "$(dirname "$NATFLUSH")"
        mkfifo "$NATFLUSH" || die "cannot create FIFO $NATFLUSH"
    }
fi
chmod 666 "$NATFLUSH" 2>/dev/null
log "FIFO $NATFLUSH ready"

# ── 0.1 Background reader: keeps read-end open so uuplugin writes don't block ──
#     Uses a perpetual cat loop (cat exits on EOF when writer closes, restart)
(
    while true; do
        cat "$NATFLUSH" 2>/dev/null >> "$RXLOG"
        log "FIFO reader: cat exited, restarting in 1s..."
        sleep 1
    done
) &
READER_PID=$!
log "FIFO reader PID=$READER_PID"

# ── 0.2 Background writer: keeps write-end open so uuplugin reads don't EOF ──
#     Opens FIFO for writing and sleeps (holds FD open indefinitely)
(
    exec 3>"$NATFLUSH" 2>/dev/null || { log "cannot open FIFO for writing"; exit 1; }
    # Write a hello/ready signal — uuplugin may expect an initial handshake
    echo "READY" >&3 2>/dev/null
    log "FIFO writer: sent READY, holding fd open"
    # Hold the write FD open forever (so uuplugin's reads block, not EOF)
    while true; do
        sleep 60
        # Periodically write keep-alive (harmless if uuplugin doesn't expect it)
        echo "ALIVE" >&3 2>/dev/null
    done
) &
WRITER_PID=$!
log "FIFO writer PID=$WRITER_PID"

# Give reader/writer a moment to open the FIFO before uuplugin tries
sleep 1

# ── 1. TUN device ──────────────────────────────────────────────────────────
ip link del "$TUN" 2>/dev/null
if ! ip tuntap add "$TUN" mode tun 2>/dev/null; then
    log "FATAL: cannot create $TUN — check NET_ADMIN + /dev/net/tun"
    # Don't exit — FIFO processes are still needed
else
    ip link set "$TUN" up 2>/dev/null
    log "TUN $TUN created and UP"
fi

# ── 2. Policy routing table ───────────────────────────────────────────────
ip route flush table "$TABLE" 2>/dev/null
ip route add default dev "$TUN" table "$TABLE" 2>/dev/null
log "route table $TABLE: default dev $TUN"

# ── 3. Base firewall rules ────────────────────────────────────────────────
{ iptables -t filter -C FORWARD -i "$TUN" -j ACCEPT 2>/dev/null; } || \
    iptables -t filter -I FORWARD -i "$TUN" -j ACCEPT 2>/dev/null
{ iptables -t filter -C FORWARD -o "$TUN" -j ACCEPT 2>/dev/null; } || \
    iptables -t filter -I FORWARD -o "$TUN" -j ACCEPT 2>/dev/null
{ iptables -t nat    -C POSTROUTING -o "$TUN" -j MASQUERADE 2>/dev/null; } || \
    iptables -t nat    -I POSTROUTING -o "$TUN" -j MASQUERADE 2>/dev/null
log "base firewall rules installed"

# ── 4. Client monitoring loop ─────────────────────────────────────────────
# uuplugin creates DROP rules on mangle INPUT (tcp dpt:53) for each
# accelerated client IP.  We use that as our "client list" signal.
SEEN=""
log "entering monitor loop..."

while true; do
    # ── 4a. Check mangle INPUT for new accelerated clients ──
    CLIENTS=$(iptables -t mangle -L INPUT -n 2>/dev/null | awk '/tcp dpt:53/{print $4}' | sort -u)

    for IP in $CLIENTS; do
        case " $SEEN " in
            *" $IP "*) continue ;;
        esac
        SEEN="$SEEN $IP"
        log "new accelerated client: $IP"

        # Policy routing: from $IP → table $TABLE
        if ! ip rule show | grep -qF "from $IP lookup $TABLE"; then
            ip rule add from "$IP" lookup "$TABLE" 2>/dev/null
            log "  ip rule: from $IP lookup $TABLE"
        fi

        # mangle MARK
        if ! iptables -t mangle -C PREROUTING -s "$IP" -j MARK --set-mark "$FWMARK" 2>/dev/null; then
            iptables -t mangle -I PREROUTING -s "$IP" -j MARK --set-mark "$FWMARK" 2>/dev/null
            log "  mangle MARK: -s $IP -j MARK --set-mark $FWMARK"
        fi

        # DNAT DNS → Google
        if ! iptables -t nat -C PREROUTING -i br-lan -s "$IP" -p udp --dport 53 -j DNAT --to-destination 8.8.8.8 2>/dev/null; then
            iptables -t nat -I PREROUTING -i br-lan -s "$IP" -p udp --dport 53 -j DNAT --to-destination 8.8.8.8 2>/dev/null
            log "  DNAT: udp/53 from $IP → 8.8.8.8"
        fi
    done

    # ── 4b. Monitor /proc/net/nf_conntrack for active game flows ──
    if [ -r /proc/net/nf_conntrack ]; then
        CONNTRACK_FILE="/proc/net/nf_conntrack"
    elif [ -r /proc/net/ip_conntrack ]; then
        CONNTRACK_FILE="/proc/net/ip_conntrack"
    else
        CONNTRACK_FILE=""
    fi
    if [ -n "$CONNTRACK_FILE" ]; then
        ACTIVE_COUNT=$(grep -c "ESTABLISHED\|SYN_SENT" "$CONNTRACK_FILE" 2>/dev/null || echo 0)
        if [ "$ACTIVE_COUNT" -gt 0 ] 2>/dev/null; then
            # Log active flows for debugging (every 5 cycles ≈ 15s)
            if [ $(( $(date +%s) % 15 )) -lt 3 ]; then
                log "conntrack active flows: $ACTIVE_COUNT"
                grep "ESTABLISHED\|SYN_SENT" "$CONNTRACK_FILE" 2>/dev/null | head -5 | while read -r flow; do
                    log "  flow: $flow"
                done
            fi
        fi
    fi

    sleep 3
done
