#!/bin/sh
# ============================================================================
# uuclearnat replacement for QEMU/Docker container
# uuplugin callback: sh -c "/bin/sh /usr/bin/uuclearnat > /dev/null 2>&1 &"
#
# Responsibilities (inferred from strace/pcap on real hardware):
#   1. Create tun163, bring it UP
#   2. Setup policy routing table 163 → default via tun163
#   3. Monitor mangle INPUT for client DROP rules (uuplugin signals which
#      LAN IPs are being accelerated)
#   4. For each client: add ip rule + mangle MARK + DNAT DNS → 8.8.8.8
#   5. Keep running (uuplugin polls for this process)
#
# NOTE: The real uuclearnat also establishes a VPN tunnel via tun163 and
# forwards game traffic through it.  Without UU's server-side infrastructure
# we cannot replicate that part — but this stub lets uuplugin proceed past
# the "network component init" phase so we can diagnose further.
# ============================================================================

TUN="tun163"
TABLE="163"
FWMARK="0x163"
LOG="/tmp/uuclearnat.log"
: > "$LOG"

log() { echo "[$(date +%H:%M:%S)] $1" >> "$LOG"; }

log "=== uuclearnat starting (pid $$) ==="

# ── 1. TUN device ──────────────────────────────────────────────────────────
ip link del "$TUN" 2>/dev/null
if ! ip tuntap add "$TUN" mode tun 2>/dev/null; then
    log "FATAL: cannot create $TUN — check NET_ADMIN + /dev/net/tun"
    exit 1
fi
ip link set "$TUN" up 2>/dev/null
log "TUN $TUN created and UP"

# ── 2. Policy routing table ───────────────────────────────────────────────
ip route flush table "$TABLE" 2>/dev/null
ip route add default dev "$TUN" table "$TABLE" 2>/dev/null
log "route table $TABLE: default dev $TUN"

# ── 3. Base firewall rules (idempotent via -C check) ──────────────────────
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
    CLIENTS=$(iptables -t mangle -L INPUT -n 2>/dev/null | awk '/tcp dpt:53/{print $4}' | sort -u)

    for IP in $CLIENTS; do
        # skip already processed
        case " $SEEN " in
            *" $IP "*) continue ;;
        esac
        SEEN="$SEEN $IP"
        log "new accelerated client: $IP"

        # --- Policy routing: from $IP → table $TABLE (only if not exists) ---
        if ! ip rule show | grep -qF "from $IP lookup $TABLE"; then
            ip rule add from "$IP" lookup "$TABLE" 2>/dev/null
            log "  ip rule: from $IP lookup $TABLE"
        fi

        # --- mangle MARK: tag all traffic from this client ---
        if ! iptables -t mangle -C PREROUTING -s "$IP" -j MARK --set-mark "$FWMARK" 2>/dev/null; then
            iptables -t mangle -I PREROUTING -s "$IP" -j MARK --set-mark "$FWMARK" 2>/dev/null
            log "  mangle MARK: -s $IP -j MARK --set-mark $FWMARK"
        fi

        # --- DNAT DNS UDP/53 → Google DNS (idempotent) ---
        if ! iptables -t nat -C PREROUTING -i br-lan -s "$IP" -p udp --dport 53 -j DNAT --to-destination 8.8.8.8 2>/dev/null; then
            iptables -t nat -I PREROUTING -i br-lan -s "$IP" -p udp --dport 53 -j DNAT --to-destination 8.8.8.8 2>/dev/null
            log "  DNAT: udp/53 from $IP → 8.8.8.8"
        fi
    done

    sleep 3
done
#!/bin/sh
# uuclearnat replacement for QEMU/Docker container
# Handles: TUN creation, policy routing, NAT/firewall rules
# Called by uuplugin via: sh -c "/bin/sh /usr/bin/uuclearnat > /dev/null 2>&1 &"

TUN="tun163"
TABLE="163"
FWMARK="0x163"
LOG="/tmp/uuclearnat.log"

log() { echo "[$(date +%H:%M:%S)] $1" >> $LOG; }

log "=== uuclearnat starting ==="

# ── 1. TUN device ──
ip link del $TUN 2>/dev/null
ip tuntap add $TUN mode tun 2>/dev/null
if [ $? -ne 0 ]; then
    log "FATAL: cannot create $TUN"
    exit 1
fi
ip link set $TUN up
log "$TUN created and UP"

# ── 2. Policy routing table ──
ip route flush table $TABLE 2>/dev/null
ip route add default dev $TUN table $TABLE 2>/dev/null
log "route table $TABLE: default dev $TUN"

# ── 3. Base firewall ──
iptables -t filter -C FORWARD -i $TUN -j ACCEPT 2>/dev/null || \
    iptables -t filter -I FORWARD -i $TUN -j ACCEPT 2>/dev/null
iptables -t filter -C FORWARD -o $TUN -j ACCEPT 2>/dev/null || \
    iptables -t filter -I FORWARD -o $TUN -j ACCEPT 2>/dev/null
iptables -t nat -C POSTROUTING -o $TUN -j MASQUERADE 2>/dev/null || \
    iptables -t nat -I POSTROUTING -o $TUN -j MASQUERADE 2>/dev/null
log "base firewall rules installed"

# ── 4. Monitor uuplugin client list and add routing/DNAT ──
# uuplugin marks accelerated clients with DROP rules in mangle INPUT (tcp dpt:53)
SEEN=""
while true; do
    for IP in $(iptables -t mangle -L INPUT -n 2>/dev/null | awk '/tcp dpt:53/{print $4}'); do
        case " $SEEN " in
            *" $IP "*) continue ;;
        esac
        SEEN="$SEEN $IP"
        log "client detected: $IP"

        # Add policy routing
        ip rule add from $IP fwmark $FWMARK lookup $TABLE 2>/dev/null

        # DNAT: redirect DNS to 8.8.8.8 (uuplugin does DROP on TCP/53, we handle UDP/53)
        iptables -t nat -C PREROUTING -i br-lan -s $IP -p udp --dport 53 -j DNAT --to-destination 8.8.8.8 2>/dev/null || \
            iptables -t nat -I PREROUTING -i br-lan -s $IP -p udp --dport 53 -j DNAT --to-destination 8.8.8.8 2>/dev/null
    done
    sleep 3
done
