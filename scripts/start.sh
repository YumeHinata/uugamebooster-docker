#!/bin/sh
# ============================================================================
# UU Game Booster - Docker Runtime (x86_64 native)
#
# Key strategy for full-feature activation:
#   1. UU_MODEL=h3c-nx30pro env var → overrides hardcoded model
#   2. DNS hijack: rglg.uu.netease.com → h3crglg.uu.163.com
#      (resolved dynamically at startup, not hardcoded IP)
#   3. h3c_info file provides factory identity for registration
#
# Only ONE domain needs hijacking:
#   rglg.uu.netease.com (primary registration endpoint)
# Others (devrglg, gw.router, log) don't affect feature delivery.
# ============================================================================

echo "========================================="
echo "UU Game Booster - x86_64 Docker Runtime"
echo "========================================="

# ── Environment Variables ──────────────────────────────────────────────────
# uuplugin (statically linked C++ binary) reads ALL of these via getenv().
# Any missing → std::string(nullptr) → SIGABRT "basic_string::_M_construct null not valid"
# These are the complete set extracted from binary strings.

# Standard env vars (may be absent in minimal containers)
export HOME="${HOME:-/root}"
export TZ="${TZ:-CST-8}"

# Device identity (user-configurable)
export UU_MODEL="${UU_MODEL:-h3c-nx30pro}"
export UU_VENDOR="${UU_VENDOR:-h3c}"
export UU_DEVICE_TYPE="${UU_DEVICE_TYPE:-router}"
export UU_FIRMWARE_VERSION="${UU_FIRMWARE_VERSION:-v14.3.0}"
export UU_SN="${UU_SN:-${FIXED_SN:-unknown}}"
export UU_PLUGIN_VESION="${UU_PLUGIN_VESION:-v14.3.0}"
export UU_RANDOM="${UU_RANDOM:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo 'default')}"

# Network interface info (populated at runtime by binary, but needs non-null defaults)
export UU_DEVICE_MAC="${UU_DEVICE_MAC:-00:00:00:00:00:00}"
export UU_DEVICE_IP="${UU_DEVICE_IP:-127.0.0.1}"
export UU_DEVICE_FWMARK="${UU_DEVICE_FWMARK:-0}"
export UU_DEVICE_LINK_TYPE="${UU_DEVICE_LINK_TYPE:-ethernet}"
export UU_LAN_IP="${UU_LAN_IP:-192.168.1.1}"
export UU_LAN_NAME="${UU_LAN_NAME:-br-lan}"
export UU_WAN_IP="${UU_WAN_IP:-0.0.0.0}"
export UU_TUN_IP="${UU_TUN_IP:-10.0.0.1}"
export UU_TUN_NAME="${UU_TUN_NAME:-tun163}"
export UU_ROUTE_DEFAULT_TABLE="${UU_ROUTE_DEFAULT_TABLE:-main}"
export UU_ROUTE_FWMARK_TABLE="${UU_ROUTE_FWMARK_TABLE:-163}"
export UU_N_PR_H="${UU_N_PR_H:-0}"

echo "[INFO] Identity: MODEL=$UU_MODEL VENDOR=$UU_VENDOR TYPE=$UU_DEVICE_TYPE"

# ── DNS Hijack: rglg.uu.netease.com → h3crglg.uu.163.com ────────────────────
# uuplugin hardcodes rglg.uu.netease.com as the registration server.
# We redirect to H3C's endpoint for full feature activation.
# IP is resolved dynamically at each container start — no stale IP risk.
H3C_HOST="h3crglg.uu.163.com"
H3C_PORT="16000"
NETEASE_HOST="rglg.uu.netease.com"

echo "[INFO] DNS hijack: $NETEASE_HOST → $H3C_HOST"
H3C_IP=$(getent hosts "$H3C_HOST" 2>/dev/null | awk '{print $1; exit}')
if [ -n "$H3C_IP" ]; then
    sed -i "/$NETEASE_HOST/d" /etc/hosts 2>/dev/null
    echo "$H3C_IP $NETEASE_HOST" >> /etc/hosts
    echo "[OK] /etc/hosts: $H3C_IP → $NETEASE_HOST"
else
    echo "[WARN] Cannot resolve $H3C_HOST — DNS hijack disabled"
    echo "[WARN] uuplugin will connect to real rglg.uu.netease.com (basic features only)"
fi

# ── iptables legacy mode ───────────────────────────────────────────────────
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null

# ── xtables module links (uuplugin hardcodes XTABLES_LIBDIR=/lib) ──────────
mkdir -p /lib
[ -L /lib/xtables ] || ln -sf /usr/lib/x86_64-linux-gnu/xtables /lib/xtables 2>/dev/null
for f in /usr/lib/x86_64-linux-gnu/xtables/libxt_*.so; do
    bn=$(basename "$f")
    [ -e "/lib/$bn" ] || ln -sf "xtables/$bn" "/lib/$bn" 2>/dev/null
done

# ── TUN device ─────────────────────────────────────────────────────────────
if [ ! -e /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null
    chmod 666 /dev/net/tun 2>/dev/null
fi
[ -e /dev/net/tun ] && echo "[OK] /dev/net/tun" || echo "[FATAL] /dev/net/tun missing!"

# ── WAN1 dummy interface (uuplugin requires this interface name) ───────────
ip link del WAN1 2>/dev/null
if ip link add WAN1 type dummy 2>/dev/null; then
    ip link set WAN1 up 2>/dev/null
    echo "[OK] WAN1 dummy created"
else
    echo "[WARN] WAN1 create failed (check NET_ADMIN)"
fi

# ── natflushdev FIFO (uuplugin ↔ uuclearnat IPC) ──────────────────────────
# uuplugin opens /dev/natflushdev; uuclearnat opens same path
NATFLUSH="/dev/natflushdev"
rm -f "$NATFLUSH" 2>/dev/null
mkfifo "$NATFLUSH" 2>/dev/null && chmod 666 "$NATFLUSH"
[ -p "$NATFLUSH" ] && echo "[OK] $NATFLUSH FIFO" || echo "[WARN] $NATFLUSH failed"

# ── OpenWrt paths (binary expects these absolute paths) ────────────────────
# uuplugin was compiled for OpenWrt x86_64; statically linked but uses hardcoded
# absolute paths for its runtime data (not relative to binary location).
mkdir -p /usr/sbin/uu /var/tmp/uu /tmp/uu
chmod 755 /usr/sbin/uu

# ── Device identity files ──────────────────────────────────────────────────
echo "CST-8" > /etc/TZ 2>/dev/null
echo "$UU_MODEL" > /var/model 2>/dev/null

# h3c_info — factory identity for H3C registration protocol
if [ ! -f /var/tmp/uu/h3c_info ]; then
    MAC=$(cat /sys/class/net/eth0/address 2>/dev/null || echo "00:00:00:00:00:00")
    SN="${FIXED_SN:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 16)}"
    printf 'manucode=%s\nproductname=%s\nmac=%s\nsn=%s\n' \
        "${UU_VENDOR}" "${UU_MODEL}" "$MAC" "$SN" > /var/tmp/uu/h3c_info
    echo "[INFO] h3c_info: productname=$UU_MODEL sn=$SN"
fi

# .sn — serial number cache (binary reads this AFTER creating it empty, crashes on null)
if [ ! -s /usr/sbin/uu/.sn ]; then
    SN="${FIXED_SN:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 16)}"
    echo "$SN" > /usr/sbin/uu/.sn
    echo "[INFO] /usr/sbin/uu/.sn written"
fi

# activate_status — uuplugin monitors this via inotify
echo "0" > /tmp/uu/activate_status 2>/dev/null

# .uu_whoami.txt — authentication handshake cache (binary creates if missing,
# but some code paths may fail if the file doesn't exist at all)
[ -f /tmp/.uu_whoami.txt ] || touch /tmp/.uu_whoami.txt 2>/dev/null

# ── Cleanup leftover rules from previous container runs ────────────────────
echo "[DIAG] Cleaning up leftover iptables/ip rules..."

# mangle INPUT (uuplugin client acceleration DROP rules)
iptables -t mangle -F INPUT 2>/dev/null
echo "  mangle INPUT flushed"

# mangle PREROUTING MARK (uuclearnat fwmark 0x163)
RULE_NUM=$(iptables -t mangle -L PREROUTING -n --line-numbers 2>/dev/null | grep -c "MARK set 0x163")
if [ "$RULE_NUM" -gt 0 ]; then
    iptables -t mangle -L PREROUTING -n --line-numbers 2>/dev/null | \
        grep "MARK set 0x163" | awk '{print $1}' | sort -rn | \
        while read N; do iptables -t mangle -D PREROUTING "$N" 2>/dev/null; done
    echo "  mangle PREROUTING: $RULE_NUM MARK rules removed"
else
    echo "  mangle PREROUTING: clean"
fi

# nat PREROUTING DNAT (uuclearnat DNS redirect to 8.8.8.8)
RULE_NUM=$(iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep -c "to:8.8.8.8")
if [ "$RULE_NUM" -gt 0 ]; then
    iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | \
        grep "to:8.8.8.8" | awk '{print $1}' | sort -rn | \
        while read N; do iptables -t nat -D PREROUTING "$N" 2>/dev/null; done
    echo "  nat PREROUTING: $RULE_NUM DNAT rules removed"
else
    echo "  nat PREROUTING: clean"
fi

# tun163 MASQUERADE + FORWARD (safe to delete, only ours)
iptables -t nat -D POSTROUTING -o tun163 -j MASQUERADE 2>/dev/null
iptables -t filter -D FORWARD -i tun163 -j ACCEPT 2>/dev/null
iptables -t filter -D FORWARD -o tun163 -j ACCEPT 2>/dev/null
echo "  tun163 rules cleaned"

# tun163 device
ip link del tun163 2>/dev/null

# ip rules (table 163, can accumulate hundreds of entries)
DELETED=0
echo "  cleaning ip rules (table 163)..."
while ip rule show 2>/dev/null | grep -q "lookup 163"; do
    PRIO=$(ip rule show 2>/dev/null | grep "lookup 163" | head -1 | awk -F: '{print $1}' | tr -d ' ')
    [ -n "$PRIO" ] && ip rule del prio "$PRIO" 2>/dev/null && DELETED=$((DELETED + 1)) || break
done
echo "  ip rules: $DELETED removed"

# ── Network tool verification ──────────────────────────────────────────────
iptables -w -L -n >/dev/null 2>&1 && echo "[OK] iptables works" || echo "[FAIL] iptables"
XTABLES_LIBDIR=/lib iptables -w -A INPUT -p tcp --dport 65534 -j ACCEPT >/dev/null 2>&1 && \
    { iptables -D INPUT -p tcp --dport 65534 -j ACCEPT 2>/dev/null; echo "[OK] XTABLES_LIBDIR=/lib compat"; } || \
    echo "[FAIL] XTABLES_LIBDIR=/lib"
ip link show >/dev/null 2>&1 && echo "[OK] ip works" || echo "[FAIL] ip"

# ── xtables-nft-multi (binary calls it from its own dir) ──────────────────
if [ ! -e /opt/uu/bin/xtables-nft-multi ] && [ -e /usr/sbin/xtables-nft-multi ]; then
    ln -sf /usr/sbin/xtables-nft-multi /opt/uu/bin/xtables-nft-multi
    echo "[OK] xtables-nft-multi symlinked"
fi

# ── Start uuplugin (x86_64 native, no QEMU!) ──────────────────────────────
UU_BIN="/opt/uu/bin/uuplugin"
echo "[INFO] Starting uuplugin (x86_64 native)..."
RESTART_COUNT=0

while true; do
    # Kill orphaned child processes from previous run
    for name in xuplugin-guardian uuclearnat; do
        ORPHANS=$(ps | grep "$name" | grep -v grep | awk '{print $1}')
        [ -n "$ORPHANS" ] && kill $ORPHANS 2>/dev/null
    done

    # Remove stale pid file (prevents "already running" false positive)
    rm -f /var/run/uuplugin.pid 2>/dev/null

    echo "[INFO] Starting uuplugin (attempt $((RESTART_COUNT + 1)))..."
    if [ "$STRACE_DEBUG" = "1" ]; then
        strace -f -o /tmp/strace_${RESTART_COUNT}.log "$UU_BIN" >/tmp/uuplugin_stdout.log 2>/tmp/uuplugin_stderr.log &
        UU_PID=$!
        echo "[DEBUG] strace PID=$UU_PID log=/tmp/strace_${RESTART_COUNT}.log"
    else
        "$UU_BIN" >/tmp/uuplugin_stdout.log 2>/tmp/uuplugin_stderr.log &
        UU_PID=$!
    fi
    wait $UU_PID
    REAL_RET=$?
    RESTART_COUNT=$((RESTART_COUNT + 1))

    if [ $REAL_RET -ge 128 ]; then
        SIG_NUM=$((REAL_RET - 128))
        echo "[WARN] uuplugin killed by signal $SIG_NUM (restarts=$RESTART_COUNT)"
    elif [ $REAL_RET -eq 0 ]; then
        echo "[INFO] uuplugin exited normally (restarts=$RESTART_COUNT)"
    else
        echo "[WARN] uuplugin exited code $REAL_RET (restarts=$RESTART_COUNT)"
    fi

    echo "[DIAG] Last stderr lines:"
    tail -5 /tmp/uuplugin_stderr.log 2>/dev/null

    sleep 10
done
