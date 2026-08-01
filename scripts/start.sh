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
# UU_SN set to null placeholder early — binary crashes if getenv("UU_SN") returns NULL.
# Will be updated to real SN after generation. from_file=0 is a known limitation.
export UU_SN=""
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

# ── Hostname override (binary reads hostname as OS identifier!) ──────────────
# Docker host networking may leak host's HOSTNAME (e.g. iStoreOS).
# Force to NX30Pro so server sees us as a real H3C device.
if [ "$(hostname)" != "NX30Pro" ]; then
    hostname NX30Pro 2>/dev/null || true
    echo "[OK] hostname set to NX30Pro"
fi
export HOSTNAME="${HOSTNAME:-NX30Pro}"

# ── DNS Hijack: Both registration domains → h3crglg.uu.163.com ────────────
# Binary resolves rglg.uu.163.com (primary) and sometimes rglg.uu.netease.com.
# Both must be hijacked to H3C endpoint for full feature activation.
#
# If UU_MITM_HOST is set, ALL UU registration hostnames are redirected
# to the MITM proxy (used for traffic analysis / response modification).
H3C_HOST="h3crglg.uu.163.com"
H3C_PORT="16000"
NETEASE_HOST="rglg.uu.netease.com"
RGLG_163="rglg.uu.163.com"

if [ -n "${UU_MITM_HOST}" ]; then
    echo "[MITM] Redirecting ALL UU traffic to ${UU_MITM_HOST}:16000"
    for DOMAIN in "$NETEASE_HOST" "$RGLG_163" "$H3C_HOST" \
        "devrglg.uu.163.com" "gw.router.uu.163.com" \
        "router.uu.163.com" "uurouter.gdl.netease.com" \
        "log.uu.163.com"; do
        sed -i "/$DOMAIN/d" /etc/hosts 2>/dev/null
        echo "${UU_MITM_HOST} $DOMAIN" >> /etc/hosts
    done
    echo "[MITM] /etc/hosts updated with ${UU_MITM_HOST}"
elif [ "${SKIP_DNS_HIJACK}" = "1" ]; then
    echo "[INFO] SKIP_DNS_HIJACK=1 — DNS hijack skipped, using existing /etc/hosts"
else
    echo "[INFO] DNS hijack: $NETEASE_HOST + $RGLG_163 → $H3C_HOST"
    H3C_IP=$(getent hosts "$H3C_HOST" 2>/dev/null | awk '{print $1; exit}')
    if [ -n "$H3C_IP" ]; then
        for DOMAIN in "$NETEASE_HOST" "$RGLG_163"; do
            sed -i "/$DOMAIN/d" /etc/hosts 2>/dev/null
            echo "$H3C_IP $DOMAIN" >> /etc/hosts
        done
        echo "[OK] /etc/hosts: $H3C_IP → $NETEASE_HOST + $RGLG_163"
    else
        echo "[WARN] Cannot resolve $H3C_HOST — DNS hijack disabled"
        echo "[WARN] uuplugin will connect to real registration servers (basic features only)"
    fi
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

# ── SSH password (binary's internal SSH server hardcodes root/admin) ────────
# Binary listens on 192.168.0.1:16363 + 192.168.0.1:14554 for mobile app binding.
# Authenticates against /etc/shadow; must match hardcoded password "admin".
if grep -q '^root:\*:' /etc/shadow 2>/dev/null; then
    openssl passwd -6 admin | sed 's|.*|root:&:20647:0:99999:7:::|' > /tmp/newshadow
    grep -v '^root:' /etc/shadow >> /tmp/newshadow
    cat /tmp/newshadow > /etc/shadow
    rm -f /tmp/newshadow
    echo "[OK] root password set for SSH binding"
else
    echo "[OK] root password already configured"
fi

# ── OpenWrt paths (binary expects these absolute paths) ────────────────────
# uuplugin was compiled for OpenWrt x86_64; statically linked but uses hardcoded
# absolute paths for its runtime data (not relative to binary location).
mkdir -p /usr/sbin/uu /var/tmp/uu /tmp/uu /var/tmp/plugmnt/uu /usr/uufactory
chmod 755 /usr/sbin/uu

# ── H3C factory info (real device identity from community port) ────────────
# /usr/uufactory/factoryinfo = H3C hardware factory partition (simulated)
# /var/tmp/uu/h3c_info        = copied by init.d script, read by uuplugin
#
# SN strategy: generate once, persist inside container.
# First run → random SN → saved to /var/tmp/uu/uu_sn
# uuplugin restarts reuse same SN; container rebuild resets.
PERSIST_SN="/var/tmp/uu/uu_sn"

if [ -f "$PERSIST_SN" ] && [ -s "$PERSIST_SN" ]; then
    SN=$(cat "$PERSIST_SN")
    echo "[INFO] Reusing persisted SN: $SN"
else
    # Generate random 20-digit SN on first run (matching NX30Pro manucode format)
    SN=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | tr 'a-f' '0-5' | head -c 20)
    # Fallback: /dev/urandom
    [ -z "$SN" ] && SN=$(head -c 10 /dev/urandom 2>/dev/null | od -An -tu8 | tr -d ' \n' | head -c 20)
    [ -z "$SN" ] && SN="00000000000000000001"
    echo "$SN" > "$PERSIST_SN"
    echo "[INFO] Generated new SN: $SN → persisted to $PERSIST_SN"
fi

if [ ! -f /usr/uufactory/factoryinfo ]; then
    # Get real host MAC (critical: server may reject all-zeros MAC)
    REAL_MAC=$(cat /sys/class/net/br-lan/address 2>/dev/null || \
               cat /sys/class/net/eth0/address 2>/dev/null || \
               cat /sys/class/net/eth1/address 2>/dev/null || \
               echo "")
    MAC="${REAL_MAC:-${UU_DEVICE_MAC:-00:00:00:00:00:00}}"
    cat > /usr/uufactory/factoryinfo << FACTORYEOF
productname=NX30Pro
ethaddr=$MAC
hardversion=VER.A
bootversion=100
manucode=$SN
FACTORYEOF
    echo "[OK] /usr/uufactory/factoryinfo created (SN=$SN MAC=$MAC)"
fi
# Copy to h3c_info (binary reads from here for registration)
cp /usr/uufactory/factoryinfo /var/tmp/uu/h3c_info
echo "[INFO] h3c_info copied from factoryinfo"

# Export UU_SN for internal use (binary patched: "UU_SN" → "XX_SN" in .rodata,
# so getenv("XX_SN") returns NULL → falls through to file path → from_file=1).
# CORRECTED: previous Dockerfile patch at offset 4095722 was off by 0x1000=4096 bytes,
# patching random .rodata instead of the actual "UU_SN" string at offset 4091626.
export UU_SN="$SN"
echo "[INFO] UU_SN=$SN (binary reads XX_SN @ correct offset→NULL→file path→from_file=1)"

# /var/run/landevname.txt — H3C init.d writes bridge name here
# Binary reads this to determine which interface to scan for LAN devices!
# Without this, device discovery may not work at all.
echo "br-lan" > /var/run/landevname.txt 2>/dev/null
echo "[OK] /var/run/landevname.txt = br-lan"

# ── Device identity files ──────────────────────────────────────────────────
echo "CST-8" > /etc/TZ 2>/dev/null
echo "$UU_MODEL" > /var/model 2>/dev/null

# /etc/lsb-release — OS detection (binary reads this; without it, falls back to "openwrt" hardcoded default,
# ignoring UU_MODEL env var entirely)
if [ ! -f /etc/lsb-release ]; then
    cat > /etc/lsb-release << 'LSBEOF'
DISTRIB_ID="OpenWrt"
DISTRIB_RELEASE="21.02.0"
DISTRIB_REVISION="r16495-bf0c965af0"
DISTRIB_TARGET="x86/64"
DISTRIB_ARCH="x86_64"
DISTRIB_DESCRIPTION="OpenWrt 21.02.0"
LSBEOF
    echo "[OK] /etc/lsb-release created"
else
    echo "[OK] /etc/lsb-release exists"
fi

# h3c_info already created above from factoryinfo

# .sn — serial number cache (binary reads this AFTER creating it empty, crashes on null)
if [ ! -s /usr/sbin/uu/.sn ]; then
    echo "$SN" > /usr/sbin/uu/.sn
    echo "[INFO] /usr/sbin/uu/.sn written (SN=$SN)"
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
        strace -f -o /tmp/strace_${RESTART_COUNT}.log "$UU_BIN" /opt/uu/conf/uu.conf >/tmp/uuplugin_stdout.log 2>/tmp/uuplugin_stderr.log &
        UU_PID=$!
        echo "[DEBUG] strace PID=$UU_PID log=/tmp/strace_${RESTART_COUNT}.log"
    else
        "$UU_BIN" /opt/uu/conf/uu.conf >/tmp/uuplugin_stdout.log 2>/tmp/uuplugin_stderr.log &
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
