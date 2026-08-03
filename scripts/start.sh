#!/bin/sh
# ============================================================================
# UU Game Booster - Docker Runtime (x86_64 native)
#
# Feature flags (set in docker-compose.yml):
#   UU_FEATURE_BINARY_PATCH=1   L1: patch binary .rodata (openwrt → h3c-nx30pro)
#   UU_FEATURE_DNS_HIJACK=1     L2: DNS hijack to h3crglg.uu.163.com
#   UU_FEATURE_IDENTITY=1       L3: H3C env vars + SN + factoryinfo
#   UU_FEATURE_MGMT_PROXY=1     L4: management port proxy (16363/14554)
#   UU_MITM_HOST=...            L5: MITM proxy (set Windows IP)
#
# Test plan: docs/plan-clean-version.md
# ============================================================================

echo "========================================="
echo "UU Game Booster - x86_64 Docker Runtime"
echo "========================================="

# ── DNS: public resolvers (bypass iStoreOS dnsmasq filter) ────────────────
echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
echo "[OK] DNS set to 114.114.114.114 + 8.8.8.8"

# ═══════════════════════════════════════════════════════════════════════════
# L1: Runtime binary patches
# ═══════════════════════════════════════════════════════════════════════════

if [ "${UU_FEATURE_BINARY_PATCH}" = "1" ]; then
    echo "[L1] Applying binary patches (openwrt → h3c-nx30pro)..."
    printf 'h3c_' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4089051 conv=notrunc 2>/dev/null
    dd if=/dev/zero of=/opt/uu/bin/uuplugin bs=1 count=3 seek=4089055 conv=notrunc 2>/dev/null
    printf 'NX30Pro' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4106351 conv=notrunc 2>/dev/null
    printf 'h3c-nx30pro' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091231 conv=notrunc 2>/dev/null
    dd if=/dev/zero of=/opt/uu/bin/uuplugin bs=1 count=2 seek=4091243 conv=notrunc 2>/dev/null
    echo "[OK] uuplugin patched: model→h3c_+h3c-nx30pro"
else
    echo "[L0] Using original unpatched binary (openwrt identity)"
fi

# ═══════════════════════════════════════════════════════════════════════════
# L3: H3C Identity (env vars, SN, factoryinfo, hostname, activate_status)
# ═══════════════════════════════════════════════════════════════════════════

if [ "${UU_FEATURE_IDENTITY}" = "1" ]; then
    echo "[L3] Setting up H3C identity..."

    # ── Hostname ──────────────────────────────────────────────────────────
    if [ "$(hostname)" != "NX30Pro" ]; then
        hostname NX30Pro 2>/dev/null || true
    fi
    export HOSTNAME="NX30Pro"

    # ── Device identity env vars ──────────────────────────────────────────
    export UU_VENDOR="${UU_VENDOR:-h3c}"
    export UU_MODEL="${UU_MODEL:-h3c-nx30pro}"
    export UU_DEVICE_TYPE="${UU_DEVICE_TYPE:-router}"
    UU_NX30PRO_FW_VERSION="${UU_NX30PRO_FW_VERSION:-v14.4.20}"
    export UU_NX30PRO_FW_VERSION
    export UU_PLUGIN_VESION="${UU_PLUGIN_VESION:-$UU_NX30PRO_FW_VERSION}"
    export UU_FIRMWARE_VERSION="${UU_FIRMWARE_VERSION:-1.0.0}"

    # ── Network config ───────────────────────────────────────────────────
    export UU_WAN_IP="${UU_WAN_IP:-0.0.0.0}"
    export UU_TUN_IP="${UU_TUN_IP:-10.0.0.1}"
    export UU_TUN_NAME="${UU_TUN_NAME:-tun163}"
    export UU_ROUTE_DEFAULT_TABLE="${UU_ROUTE_DEFAULT_TABLE:-main}"
    export UU_ROUTE_FWMARK_TABLE="${UU_ROUTE_FWMARK_TABLE:-163}"
    export UU_N_PR_H="${UU_N_PR_H:-0}"
    export UU_DEVICE_MAC="${UU_DEVICE_MAC:-00:00:00:00:00:00}"
    export UU_DEVICE_IP="${UU_DEVICE_IP:-127.0.0.1}"
    export UU_DEVICE_FWMARK="${UU_DEVICE_FWMARK:-0}"
    export UU_DEVICE_LINK_TYPE="${UU_DEVICE_LINK_TYPE:-ethernet}"
    export UU_RANDOM="${UU_RANDOM:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo 'default')}"

    # ── SN strategy ─────────────────────────────────────────────────────
    PERSIST_SN="/var/tmp/uu/uu_sn"
    SN=""

    # Step 1: HTTP fetch from MITM (if available)
    if [ -n "${UU_MITM_HOST}" ]; then
        FETCHED_SN=$(curl -s --max-time 3 "http://${UU_MITM_HOST}:16999/sn" 2>/dev/null || true)
        if [ -n "${FETCHED_SN}" ] && [ "${#FETCHED_SN}" -ge 18 ]; then
            SN="${FETCHED_SN}"
            echo "[SN] AUTO-FETCHED from MITM: $SN"
        fi
    fi

    # Step 2: UU_FIXED_SN env var (fallback)
    if [ -z "${SN}" ] && [ -n "${UU_FIXED_SN}" ]; then
        SN="${UU_FIXED_SN}"
        echo "[SN] Using UU_FIXED_SN: $SN"
    fi

    # Step 3: Persisted file (fallback)
    if [ -z "${SN}" ] && [ -f "$PERSIST_SN" ] && [ -s "$PERSIST_SN" ]; then
        CACHED=$(cat "$PERSIST_SN")
        if [ "${#CACHED}" -ge 18 ]; then
            SN="${CACHED}"
            echo "[SN] Using cached SN: $SN"
        fi
    fi

    # Step 4: Random generate (last resort)
    if [ -z "${SN}" ]; then
        SN=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | tr 'a-f' '0-5' | head -c 20)
        [ -z "$SN" ] && SN="00000000000000000001"
        echo "[SN] WARNING: Generated random SN: $SN"
    fi

    echo "$SN" > "$PERSIST_SN"
    export UU_SN="${SN}"
    echo "[SN] DEFINITIVE SN = $SN"

    # ── factoryinfo / h3c_info ───────────────────────────────────────────
    REAL_MAC=$(cat /sys/class/net/br-lan/address 2>/dev/null || \
               cat /sys/class/net/eth0/address 2>/dev/null || echo "")
    MAC="${REAL_MAC:-00:00:00:00:00:00}"
    cat > /usr/uufactory/factoryinfo << FACTORYEOF
productname=NX30Pro
ethaddr=$MAC
hardversion=VER.A
bootversion=100
manucode=$SN
FACTORYEOF
    cp /usr/uufactory/factoryinfo /var/tmp/uu/h3c_info
    echo "[OK] factoryinfo + h3c_info created"

    # ── .sn file ─────────────────────────────────────────────────────────
    echo "$SN" > /usr/sbin/uu/.sn

    # ── activate_status (force-activated) ────────────────────────────────
    if [ -f /tmp/uu/activate_status ] && [ "$(cat /tmp/uu/activate_status 2>/dev/null)" = "1" ]; then
        echo "[INFO] activate_status already 1"
    else
        echo "1" > /tmp/uu/activate_status 2>/dev/null
        echo "[OK] activate_status set to 1"
    fi

    echo "[INFO] H3C identity: UU_MODEL=$UU_MODEL, UU_VENDOR=$UU_VENDOR, SN=$SN"
else
    echo "[L0] Identity: using binary defaults (no H3C override)"
    # Still need some minimal env vars the binary might read
    export UU_LAN_IP="${UU_LAN_IP:-192.168.0.1}"
    export UU_LAN_NAME="${UU_LAN_NAME:-br-lan}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# L2/L5: DNS hijack
# ═══════════════════════════════════════════════════════════════════════════

H3C_HOST="h3crglg.uu.163.com"
NETEASE_HOST="rglg.uu.netease.com"
RGLG_163="rglg.uu.163.com"

if [ -n "${UU_MITM_HOST}" ]; then
    # L5: MITM mode — ALL registration traffic → MITM
    echo "[L5] MITM: redirecting registration to ${UU_MITM_HOST}:16000"
    for DOMAIN in "$NETEASE_HOST" "$RGLG_163" "$H3C_HOST"; do
        sed -i "/$DOMAIN/d" /etc/hosts 2>/dev/null
        echo "${UU_MITM_HOST} $DOMAIN" >> /etc/hosts
    done
elif [ "${UU_FEATURE_DNS_HIJACK}" = "1" ]; then
    # L2: DNS hijack to H3C endpoint
    echo "[L2] DNS hijack: $NETEASE_HOST + $RGLG_163 → $H3C_HOST"
    H3C_IP=$(getent hosts "$H3C_HOST" 2>/dev/null | awk '{print $1; exit}')
    if [ -n "$H3C_IP" ]; then
        for DOMAIN in "$NETEASE_HOST" "$RGLG_163"; do
            sed -i "/$DOMAIN/d" /etc/hosts 2>/dev/null
            echo "$H3C_IP $DOMAIN" >> /etc/hosts
        done
        echo "[OK] /etc/hosts: $H3C_IP → $NETEASE_HOST + $RGLG_163"
    else
        echo "[WARN] Cannot resolve $H3C_HOST — DNS hijack disabled"
    fi
else
    echo "[L0] DNS: no hijack, using real DNS resolution"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Infrastructure (always needed)
# ═══════════════════════════════════════════════════════════════════════════

# ── iptables legacy mode ─────────────────────────────────────────────────
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null

# ── xtables module links ─────────────────────────────────────────────────
mkdir -p /lib
[ -L /lib/xtables ] || ln -sf /usr/lib/x86_64-linux-gnu/xtables /lib/xtables 2>/dev/null
for f in /usr/lib/x86_64-linux-gnu/xtables/libxt_*.so; do
    bn=$(basename "$f")
    [ -e "/lib/$bn" ] || ln -sf "xtables/$bn" "/lib/$bn" 2>/dev/null
done

# ── TUN device ───────────────────────────────────────────────────────────
if [ ! -e /dev/net/tun ]; then
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null
    chmod 666 /dev/net/tun 2>/dev/null
fi
[ -e /dev/net/tun ] && echo "[OK] /dev/net/tun" || echo "[FATAL] /dev/net/tun missing!"

# ── WAN1 dummy interface ─────────────────────────────────────────────────
ip link del WAN1 2>/dev/null
if ip link add WAN1 type dummy 2>/dev/null; then
    ip link set WAN1 up 2>/dev/null
    echo "[OK] WAN1 dummy created"
else
    echo "[WARN] WAN1 create failed"
fi

# ── natflushdev FIFO ─────────────────────────────────────────────────────
NATFLUSH="/dev/natflushdev"
rm -f "$NATFLUSH" 2>/dev/null
mkfifo "$NATFLUSH" 2>/dev/null && chmod 666 "$NATFLUSH"
[ -p "$NATFLUSH" ] && echo "[OK] $NATFLUSH FIFO" || echo "[WARN] $NATFLUSH failed"

# ── SSH password (binary hardcodes root/admin) ───────────────────────────
if grep -q '^root:\*:' /etc/shadow 2>/dev/null; then
    openssl passwd -6 admin | sed 's|.*|root:&:20647:0:99999:7:::|' > /tmp/newshadow
    grep -v '^root:' /etc/shadow >> /tmp/newshadow
    cat /tmp/newshadow > /etc/shadow
    rm -f /tmp/newshadow
    echo "[OK] root password set for SSH binding"
else
    echo "[OK] root password already configured"
fi

# ── OpenWrt paths ────────────────────────────────────────────────────────
mkdir -p /usr/sbin/uu /var/tmp/uu /tmp/uu /var/tmp/plugmnt/uu /usr/uufactory

# OpenSSL cert path
mkdir -p /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/certs
[ -e /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/cert.pem ] || \
    ln -sf /etc/ssl/certs/ca-certificates.crt /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/cert.pem 2>/dev/null

# OpenSSL config
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
    echo "[OK] OpenSSL config created"
fi

# DHCP/dnsmasq paths
mkdir -p /etc/config /var/lib/misc /tmp/var/lib/misc
touch /etc/dnsmasq.conf /tmp/nmp_client_list /etc/config/dhcpd.leases 2>/dev/null
touch /var/lib/misc/dnsmasq.leases /tmp/var/lib/misc/dnsmasq.leases 2>/dev/null

# tcp_mtu_probing
if [ -w /proc/sys/net/ipv4/tcp_mtu_probing ]; then
    echo 1 > /proc/sys/net/ipv4/tcp_mtu_probing 2>/dev/null && echo "[OK] tcp_mtu_probing=1" || echo "[WARN] tcp_mtu_probing failed"
else
    echo "[WARN] /proc/sys read-only — need privileged:true"
fi

# ── /etc/lsb-release ────────────────────────────────────────────────────
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
fi

# ── landevname.txt ───────────────────────────────────────────────────────
echo "br-lan" > /var/run/landevname.txt 2>/dev/null
echo "[OK] /var/run/landevname.txt = br-lan"

# ── .uu_whoami.txt ───────────────────────────────────────────────────────
[ -f /tmp/.uu_whoami.txt ] || touch /tmp/.uu_whoami.txt 2>/dev/null

# ── /etc/TZ ──────────────────────────────────────────────────────────────
echo "CST-8" > /etc/TZ 2>/dev/null

# ── Cleanup leftover rules ───────────────────────────────────────────────
echo "[DIAG] Cleaning up leftover iptables/ip rules..."
iptables -t mangle -F INPUT 2>/dev/null
iptables -t nat -D POSTROUTING -o tun163 -j MASQUERADE 2>/dev/null
iptables -t filter -D FORWARD -i tun163 -j ACCEPT 2>/dev/null
iptables -t filter -D FORWARD -o tun163 -j ACCEPT 2>/dev/null
ip link del tun163 2>/dev/null
DELETED=0
while ip rule show 2>/dev/null | grep -q "lookup 163"; do
    PRIO=$(ip rule show 2>/dev/null | grep "lookup 163" | head -1 | awk -F: '{print $1}' | tr -d ' ')
    [ -n "$PRIO" ] && ip rule del prio "$PRIO" 2>/dev/null && DELETED=$((DELETED + 1)) || break
done
echo "  ip rules: $DELETED removed"

# ── nftables pre-create (workaround Debian bullseye bug) ─────────────────
echo "[DIAG] Pre-creating nftables tables..."
for family in ip ip6; do
    for table in XU_ACC_MAIN_filter XU_ACC_MAIN_nat XU_ACC_MAIN_mangle; do
        nft add table $family $table 2>/dev/null || true
    done
done
echo "[OK] nftables tables pre-created"

# ═══════════════════════════════════════════════════════════════════════════
# L4: Management proxy
# ═══════════════════════════════════════════════════════════════════════════

if [ "${UU_FEATURE_MGMT_PROXY}" = "1" ]; then
    echo "[L4] Setting up management port proxy..."

    pkill -f uu_mgmt_proxy.py 2>/dev/null || true
    sleep 0.5

    iptables -t nat -D PREROUTING -p tcp --dport 16363 -j REDIRECT --to-port 16365 2>/dev/null || true
    iptables -t nat -D PREROUTING -p tcp --dport 14554 -j REDIRECT --to-port 14555 2>/dev/null || true

    iptables -t nat -A PREROUTING -p tcp --dport 16363 -j REDIRECT --to-port 16365
    iptables -t nat -A PREROUTING -p tcp --dport 14554 -j REDIRECT --to-port 14555
    echo "[PROXY] iptables REDIRECT: 16363→16365, 14554→14555"

    UU_LAN_IP="${UU_LAN_IP}" python3 /opt/uu/scripts/uu_mgmt_proxy.py > /tmp/uu_mgmt_proxy.log 2>&1 &
    PROXY_PID=$!
    echo "[PROXY] Started PID=$PROXY_PID"
else
    PROXY_PID=""
    echo "[L0] Management proxy disabled"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Network tool verification
# ═══════════════════════════════════════════════════════════════════════════

iptables -w -L -n >/dev/null 2>&1 && echo "[OK] iptables works" || echo "[FAIL] iptables"
XTABLES_LIBDIR=/lib iptables -w -A INPUT -p tcp --dport 65534 -j ACCEPT >/dev/null 2>&1 && \
    { iptables -D INPUT -p tcp --dport 65534 -j ACCEPT 2>/dev/null; echo "[OK] XTABLES_LIBDIR=/lib compat"; } || \
    echo "[FAIL] XTABLES_LIBDIR=/lib"
ip link show >/dev/null 2>&1 && echo "[OK] ip works" || echo "[FAIL] ip"

# ── xtables-nft-multi symlink ────────────────────────────────────────────
if [ ! -e /opt/uu/bin/xtables-nft-multi ] && [ -e /usr/sbin/xtables-nft-multi ]; then
    ln -sf /usr/sbin/xtables-nft-multi /opt/uu/bin/xtables-nft-multi
    echo "[OK] xtables-nft-multi symlinked"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Start uuplugin loop
# ═══════════════════════════════════════════════════════════════════════════

UU_BIN="/opt/uu/bin/uuplugin"
echo "[INFO] Starting uuplugin (x86_64 native)..."

rm -f /var/run/uuplugin.pid 2>/dev/null
echo "[OK] Stale pid file cleaned"

RESTART_COUNT=0
UUCLEARNAT_PID=""

while true; do
    # Kill orphaned child processes
    for name in xuplugin-guardian uuclearnat; do
        ORPHANS=$(ps | grep "$name" | grep -v grep | awk '{print $1}')
        [ -n "$ORPHANS" ] && kill $ORPHANS 2>/dev/null
    done

    # Restart uuclearnat if needed
    if ! kill -0 $UUCLEARNAT_PID 2>/dev/null; then
        echo "[NAT] Starting uuclearnat..."
        nohup /opt/uu/scripts/uuclearnat.sh > /dev/null 2>&1 &
        UUCLEARNAT_PID=$!
        echo "[NAT] uuclearnat PID=$UUCLEARNAT_PID"
    fi

    # Restart proxy if needed
    if [ "${UU_FEATURE_MGMT_PROXY}" = "1" ] && ! kill -0 $PROXY_PID 2>/dev/null; then
        echo "[PROXY] Restarting management proxy..."
        UU_LAN_IP="${UU_LAN_IP}" python3 /opt/uu/scripts/uu_mgmt_proxy.py > /tmp/uu_mgmt_proxy.log 2>&1 &
        PROXY_PID=$!
        echo "[PROXY] Restarted PID=$PROXY_PID"
    fi

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
