#!/bin/sh

# ── network ───────────────────────────────────────────────────────────────
echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200
ip link add WAN1 type dummy 2>/dev/null
ip link set WAN1 up 2>/dev/null
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true

# ── env vars ──────────────────────────────────────────────────────────────
# All 20 UU_* strings referenced in binary — must be set to prevent NULL getenv
export UU_LAN_IP="${UU_LAN_IP:-192.168.0.1}"
export UU_LAN_NAME="${UU_LAN_NAME:-br-lan}"
export UU_WAN_IP="${UU_WAN_IP:-0.0.0.0}"
export UU_TUN_IP="${UU_TUN_IP:-10.0.0.1}"
export UU_TUN_NAME="${UU_TUN_NAME:-tun163}"
export UU_VENDOR="${UU_VENDOR:-openwrt}"
export UU_MODEL="${UU_MODEL:-x86_64}"
export UU_DEVICE_TYPE="${UU_DEVICE_TYPE:-router}"
# SN: auto-generate 20-char hex on first run if not provided
if [ -z "${UU_SN}" ]; then
    UU_SN=$(head -c 16 /dev/urandom | md5sum | head -c 20)
fi
export UU_SN
export UU_RANDOM="${UU_RANDOM:-default}"
export UU_PLUGIN_VESION="${UU_PLUGIN_VESION:-1.0.0}"
export UU_ROUTE_DEFAULT_TABLE="${UU_ROUTE_DEFAULT_TABLE:-main}"
export UU_ROUTE_FWMARK_TABLE="${UU_ROUTE_FWMARK_TABLE:-163}"
# Device vars: empty = auto-detect from real hardware
export UU_DEVICE_MAC="${UU_DEVICE_MAC:-}"
export UU_DEVICE_IP="${UU_DEVICE_IP:-}"
export UU_DEVICE_FWMARK="${UU_DEVICE_FWMARK:-}"
export UU_DEVICE_LINK_TYPE="${UU_DEVICE_LINK_TYPE:-}"
export UU_FIRMWARE_VERSION="${UU_FIRMWARE_VERSION:-1.0.0}"
export UU_N_PR_H="${UU_N_PR_H:-0}"
export HOME="${HOME:-/root}"
export USER="${USER:-root}"
export TZ="${TZ:-CST-8}"

# ── runtime directory ─────────────────────────────────────────────────────
RUNDIR="/tmp/uu"
mkdir -p "$RUNDIR" /var/run /etc/config /usr/sbin/uu

cp /opt/uu/bin/uuplugin         "$RUNDIR/"
cp /opt/uu/bin/xuplugin-guardian "$RUNDIR/"
cp /opt/uu/conf/uu.conf         "$RUNDIR/"
cp /usr/sbin/xtables-nft-multi  "$RUNDIR/" 2>/dev/null || true
chmod +x "$RUNDIR/uuplugin" "$RUNDIR/xuplugin-guardian"

# ── runtime files ─────────────────────────────────────────────────────────
echo "${UU_LAN_NAME:-br-lan}" > /var/run/landevname.txt
touch /tmp/.uu_whoami.txt
echo "CST-8" > /etc/TZ
cat > /etc/lsb-release << 'LSBEOF'
DISTRIB_ID="OpenWrt"
DISTRIB_RELEASE="21.02.0"
DISTRIB_TARGET="x86/64"
LSBEOF
touch /etc/config/dhcpd.leases
touch /etc/dnsmasq.conf
# Persist SN to disk so subsequent runs use the same identity
echo "${UU_SN}" > "$RUNDIR/.sn"
echo "${UU_SN}" > /usr/sbin/uu/.sn
cat > "$RUNDIR/uuplugin_monitor.config" << 'EOF'
router=openwrt
model=x86_64
EOF

# ── start ─────────────────────────────────────────────────────────────────
ulimit -HS -s 8192
ulimit -HS -n 1024
cd "$RUNDIR"
exec ./uuplugin ./uu.conf
