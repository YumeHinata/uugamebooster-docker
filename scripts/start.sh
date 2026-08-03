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

# ── DNS: iStoreOS dnsmasq blocks uu.*.163.com domains → use public DNS ─────
# Container uses host networking, so it inherits host's /etc/resolv.conf
# which may be filtered by iStoreOS dnsmasq. Override with public DNS.
echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
echo "[OK] DNS set to 114.114.114.114 + 8.8.8.8 (bypass iStoreOS filter)"

# ── Environment Variables ──────────────────────────────────────────────────
# uuplugin (statically linked C++ binary) reads ALL of these via getenv().
# Any missing → std::string(nullptr) → SIGABRT "basic_string::_M_construct null not valid"
# These are the complete set extracted from binary strings.

# Standard env vars (may be absent in minimal containers)
export HOME="${HOME:-/root}"
export TZ="${TZ:-CST-8}"

# Device identity — UU_* env vars for H3C NX30Pro identity.
# .rodata patches REVERTED (UU_VENDOR, UU_MODEL, etc. intact).
# MITM (uu_mitm_mod.py) injects additional NX30Pro fields into Register message.

# Device type
export DEVICE_TYPE="${DEVICE_TYPE:-router}"

# H3C NX30Pro identity — exported as UU_* (getenv in .rodata is intact)
export UU_VENDOR="${UU_VENDOR:-h3c}"
export UU_MODEL="${UU_MODEL:-h3c-nx30pro}"
# UU_SN set below after generate_proc/sn_read/sn_file logic
# Version: single source of truth is UU_NX30PRO_FW_VERSION from docker-compose.
# NX30Pro firmware updates → change ONE number in docker-compose.yml
export UU_NX30PRO_FW_VERSION="${UU_NX30PRO_FW_VERSION:-v14.4.20}"
export UU_PLUGIN_VESION="${UU_PLUGIN_VESION:-$UU_NX30PRO_FW_VERSION}"
export UU_FIRMWARE_VERSION="${UU_FIRMWARE_VERSION:-1.0.0}"

# Network config
export UU_LAN_IP="${UU_LAN_IP:-192.168.0.1}"
export UU_LAN_NAME="${UU_LAN_NAME:-br-lan}"
export UU_WAN_IP="${UU_WAN_IP:-0.0.0.0}"

# Other binary-required vars
export DEVICE_MAC="${DEVICE_MAC:-00:00:00:00:00:00}"
export DEVICE_IP="${DEVICE_IP:-127.0.0.1}"
export DEVICE_FWMARK="${DEVICE_FWMARK:-0}"
export DEVICE_LINK_TYPE="${DEVICE_LINK_TYPE:-ethernet}"
export TUN_IP="${TUN_IP:-10.0.0.1}"
export TUN_NAME="${TUN_NAME:-tun163}"
export ROUTE_DEFAULT_TABLE="${ROUTE_DEFAULT_TABLE:-main}"
export ROUTE_FWMARK_TABLE="${ROUTE_FWMARK_TABLE:-163}"
export N_PR_H="${N_PR_H:-0}"
export RANDOM_UUID="${RANDOM_UUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo 'default')}"

echo "[INFO] Identity: UU_FIXED_SN=${UU_FIXED_SN:-<random>}, UU_* env vars set, MITM injects extra H3C fields"

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
    echo "[MITM] Redirecting registration traffic to ${UU_MITM_HOST}:16000"
    echo "[MITM] (gw.router, devrglg, log, etc. resolve normally for acceleration)"
    for DOMAIN in "$NETEASE_HOST" "$RGLG_163" "$H3C_HOST"; do
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
# OpenSSL cert path (binary hardcodes build-machine path for tunnel TLS)
mkdir -p /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/certs
[ -e /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/cert.pem ] || \
    ln -sf /etc/ssl/certs/ca-certificates.crt /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/cert.pem 2>/dev/null
# OpenWrt DHCP/dnsmasq paths (binary may stat/read these)
mkdir -p /etc/config /var/lib/misc /tmp/var/lib/misc
touch /etc/dnsmasq.conf /tmp/nmp_client_list /etc/config/dhcpd.leases 2>/dev/null
touch /var/lib/misc/dnsmasq.leases /tmp/var/lib/misc/dnsmasq.leases 2>/dev/null

# Kernel params — binary's child processes write to /proc/sys for tunnel setup
# Pre-set tcp_mtu_probing=1 so the write doesn't fail on read-only /proc/sys
if [ -w /proc/sys/net/ipv4/tcp_mtu_probing ]; then
    echo 1 > /proc/sys/net/ipv4/tcp_mtu_probing 2>/dev/null && echo "[OK] tcp_mtu_probing=1" || echo "[WARN] Cannot set tcp_mtu_probing"
else
    echo "[WARN] /proc/sys is read-only — binary tunnel setup may fail (need privileged:true)"
fi

# OpenSSL config — binary hardcodes build machine path for tunnel TLS init
OPENSSL_DIR="/home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl"
if [ ! -f "$OPENSSL_DIR/openssl.cnf" ]; then
    mkdir -p "$OPENSSL_DIR"
    cat > "$OPENSSL_DIR/openssl.cnf" << 'EOF'
openssl_conf = default_conf
[default_conf]
ssl_conf = ssl_sect
[ssl_sect]
system_default = system_default_sect
[system_default_sect]
CipherString = DEFAULT:@SECLEVEL=0
MinProtocol = TLSv1
EOF
    echo "[OK] OpenSSL config created at $OPENSSL_DIR"
fi
chmod 755 /usr/sbin/uu

# ── H3C factory info (real device identity from community port) ────────────
# /usr/uufactory/factoryinfo = H3C hardware factory partition (simulated)
# /var/tmp/uu/h3c_info        = copied by init.d script, read by uuplugin
#
# SN strategy: SINGLE SOURCE OF TRUTH — fetched from MITM HTTP endpoint.
# MITM (uu_mitm_mod.py) captures protobuf SN from binary's first Register
# and serves it via HTTP on port 16999. This script fetches it, ensuring
# file SN == protobuf SN == UU_SN — no mismatch, no scattered variables.
#
# Priority:
#   1. HTTP fetch from MITM (http://MITM_HOST:16999/sn) — fully automated
#   2. UU_FIXED_SN env var — manual override / first-run fallback
#   3. Random generate — last resort (triggers "unmatched sn", fix ASAP)
PERSIST_SN="/var/tmp/uu/uu_sn"

SN=""

# ── Step 1: try HTTP fetch from MITM ────────────────────────────────────
if [ -n "${UU_MITM_HOST}" ]; then
    # MITM SN HTTP endpoint: serves captured protobuf SN from mitm_sn.txt
    FETCHED_SN=$(curl -s --max-time 3 "http://${UU_MITM_HOST}:16999/sn" 2>/dev/null || true)
    if [ -n "${FETCHED_SN}" ] && [ "${#FETCHED_SN}" -ge 18 ]; then
        SN="${FETCHED_SN}"
        echo "[SN] AUTO-FETCHED from MITM (http://${UU_MITM_HOST}:16999/sn): $SN"
    else
        echo "[SN] MITM HTTP not available or SN not captured yet"
    fi
fi

# ── Step 2: fallback to UU_FIXED_SN env var ─────────────────────────────
if [ -z "${SN}" ] && [ -n "${UU_FIXED_SN}" ]; then
    SN="${UU_FIXED_SN}"
    echo "[SN] Using UU_FIXED_SN (fallback): $SN"
fi

# ── Step 3: fallback to persisted file ──────────────────────────────────
if [ -z "${SN}" ] && [ -f "$PERSIST_SN" ] && [ -s "$PERSIST_SN" ]; then
    CACHED=$(cat "$PERSIST_SN")
    if [ "${#CACHED}" -ge 18 ]; then
        SN="${CACHED}"
        echo "[SN] Using cached SN from $PERSIST_SN: $SN"
    fi
fi

# ── Step 4: last resort — generate random ───────────────────────────────
if [ -z "${SN}" ]; then
    SN=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | tr 'a-f' '0-5' | head -c 20)
    [ -z "$SN" ] && SN=$(head -c 10 /dev/urandom 2>/dev/null | od -An -tu8 | tr -d ' \n' | head -c 20)
    [ -z "$SN" ] && SN="00000000000000000001"
    echo "[SN] WARNING: Generated random SN: $SN (will NOT match protobuf!)"
    echo "[SN] WARNING: Start MITM first so it captures the real protobuf SN."
fi

# ── Persist the definitive SN ───────────────────────────────────────────
echo "$SN" > "$PERSIST_SN"
echo "[SN] DEFINITIVE SN = $SN → persisted to $PERSIST_SN"

# ── factoryinfo: always overwrite with current SN (single source of truth) ──
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
echo "[OK] /usr/uufactory/factoryinfo (SN=$SN MAC=$MAC)"
# Copy to h3c_info (binary reads from here for registration)
cp /usr/uufactory/factoryinfo /var/tmp/uu/h3c_info
echo "[INFO] h3c_info copied from factoryinfo"

# SN persistence: generated above, exported as UU_SN (binary needs getenv).
export UU_SN="${SN}"
echo "[INFO] SN=$SN exported as UU_SN (file/protobuf match, no 'unmatched sn' expected)"

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

# .sn — serial number cache (always overwrite with current definitive SN)
echo "$SN" > /usr/sbin/uu/.sn
echo "[INFO] /usr/sbin/uu/.sn overwritten (SN=$SN)"

# activate_status — uuplugin monitors this via inotify to trigger acceleration.
# Preserve existing value across restarts; default to 1 (force-activated).
if [ -f /tmp/uu/activate_status ] && [ "$(cat /tmp/uu/activate_status 2>/dev/null)" = "1" ]; then
    echo "[INFO] activate_status already 1, preserving"
else
    echo "1" > /tmp/uu/activate_status 2>/dev/null
    echo "[INFO] activate_status set to 1 (force-activated)"
fi

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

# ── Pre-create nftables tables to avoid SIGSEGV crash ─────────────────────
# Debian bullseye's nft v0.9.8 has a NULL dereference bug:
# `nft delete table XU_ACC_MAIN_*` on non-existent table → SIGSEGV.
# uuplugin does flush+delete on these 6 tables during initialization.
# Pre-creating them ensures delete succeeds even on first run.
echo "[DIAG] Pre-creating nftables tables (workaround for nft v0.9.8 bug)..."
for family in ip ip6; do
    for table in XU_ACC_MAIN_filter XU_ACC_MAIN_nat XU_ACC_MAIN_mangle; do
        nft add table $family $table 2>/dev/null || true
    done
done
echo "[OK] nftables tables pre-created (ip/ip6 × filter/nat/mangle)"

# ── Management proxy (bypass xu_tcp_server auth) ────────────────────────
# The x86 binary requires password authentication on ports 16363/14554.
# Real NX30Pro binary does NOT — it's a compile-time difference.
# We use iptables REDIRECT + Python proxy to intercept and forward connections.
# Phase 1: transparent forwarding with hex logging (for protocol analysis).
# Phase 2: modify auth responses to skip password prompt entirely.

echo "[PROXY] Setting up management port redirect..."

# Kill any leftover proxy from previous runs
pkill -f uu_mgmt_proxy.py 2>/dev/null || true
sleep 0.5

# Clean up previous redirect rules (if any)
iptables -t nat -D PREROUTING -p tcp --dport 16363 -j REDIRECT --to-port 16365 2>/dev/null || true
iptables -t nat -D PREROUTING -p tcp --dport 14554 -j REDIRECT --to-port 14555 2>/dev/null || true

# Phone → Router:16363 → REDIRECT → Proxy:16365 → Binary:16363
# Phone → Router:14554 → REDIRECT → Proxy:14555 → Binary:14554
iptables -t nat -A PREROUTING -p tcp --dport 16363 -j REDIRECT --to-port 16365
iptables -t nat -A PREROUTING -p tcp --dport 14554 -j REDIRECT --to-port 14555
echo "[PROXY] iptables REDIRECT: 16363→16365, 14554→14555"

# Start the proxy in background (it relays mobile app ↔ binary communication)
UU_LAN_IP="${UU_LAN_IP}" python3 /opt/uu/scripts/uu_mgmt_proxy.py > /tmp/uu_mgmt_proxy.log 2>&1 &
PROXY_PID=$!
echo "[PROXY] Started PID=$PROXY_PID (log: /tmp/uu_mgmt_proxy.log)"

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

# Remove stale pid file BEFORE first start (crashes leave lock behind)
rm -f /var/run/uuplugin.pid 2>/dev/null
echo "[OK] Stale pid file cleaned"

# ── Guardian crash debug: wrap xuplugin-guardian with strace ────────────
# xuplugin-guardian is the suspected crash culprit during acceleration.
# Wrap it so every invocation gets its own strace log.
GUARDIAN_REAL="/opt/uu/bin/xuplugin-guardian.real"
GUARDIAN_WRAPPER="/opt/uu/bin/xuplugin-guardian"
if [ ! -f "$GUARDIAN_REAL" ] && [ -f "$GUARDIAN_WRAPPER" ]; then
    mv "$GUARDIAN_WRAPPER" "$GUARDIAN_REAL"
    cat > "$GUARDIAN_WRAPPER" << 'WRAPEOF'
#!/bin/sh
GUARDIAN_STAMP=$(date +%s)
# -ff: one output file per process (fixes truncated logs)
# -s 4096: full string content
# Also capture stderr separately
exec strace -ff -s 4096 -o "/tmp/guardian_${GUARDIAN_STAMP}" \
    /opt/uu/bin/xuplugin-guardian.real "$@" \
    2>/tmp/guardian_stderr_${GUARDIAN_STAMP}.log
WRAPEOF
    chmod +x "$GUARDIAN_WRAPPER"
    echo "[DEBUG] xuplugin-guardian wrapped → /tmp/guardian_strace_*.log"
fi

RESTART_COUNT=0

while true; do
    # Kill orphaned child processes from previous run
    for name in xuplugin-guardian uuclearnat; do
        ORPHANS=$(ps | grep "$name" | grep -v grep | awk '{print $1}')
        [ -n "$ORPHANS" ] && kill $ORPHANS 2>/dev/null
    done

    # Restart uuclearnat if it died (acceleration NAT companion)
    if ! kill -0 $UUCLEARNAT_PID 2>/dev/null; then
        echo "[NAT] Starting uuclearnat (acceleration NAT)..."
        nohup /opt/uu/scripts/uuclearnat.sh > /dev/null 2>&1 &
        UUCLEARNAT_PID=$!
        echo "[NAT] uuclearnat PID=$UUCLEARNAT_PID"
    fi

    # Restart proxy if it died
    if ! kill -0 $PROXY_PID 2>/dev/null; then
        echo "[PROXY] Restarting management proxy..."
        UU_LAN_IP="${UU_LAN_IP}" python3 /opt/uu/scripts/uu_mgmt_proxy.py > /tmp/uu_mgmt_proxy.log 2>&1 &
        PROXY_PID=$!
        echo "[PROXY] Restarted PID=$PROXY_PID"
    fi

    # Remove stale pid file (prevents "already running" false positive)
    rm -f /var/run/uuplugin.pid 2>/dev/null

    echo "[INFO] Starting uuplugin (attempt $((RESTART_COUNT + 1)))..."
    if [ "$STRACE_DEBUG" = "1" ]; then
        STAMP=$(date +%s)
        strace -f -o "/tmp/strace_${STAMP}.log" "$UU_BIN" /opt/uu/conf/uu.conf >/tmp/uuplugin_stdout.log 2>/tmp/uuplugin_stderr.log &
        UU_PID=$!
        echo "[DEBUG] strace PID=$UU_PID log=/tmp/strace_${STAMP}.log"
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
