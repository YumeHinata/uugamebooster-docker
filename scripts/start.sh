#!/bin/sh

# ── network ───────────────────────────────────────────────────────────────
echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200
ip link add WAN1 type dummy 2>/dev/null
ip link set WAN1 up 2>/dev/null
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true

# ── env vars (all 20 UU_* strings found in binary) ────────────────────────
export UU_LAN_IP="${UU_LAN_IP:-192.168.0.1}"
export UU_LAN_NAME="${UU_LAN_NAME:-br-lan}"
export UU_WAN_IP="${UU_WAN_IP:-0.0.0.0}"
export UU_TUN_IP="${UU_TUN_IP:-10.0.0.1}"
export UU_TUN_NAME="${UU_TUN_NAME:-tun163}"
export UU_VENDOR="${UU_VENDOR:-openwrt}"
export UU_MODEL="${UU_MODEL:-x86_64}"
export UU_DEVICE_TYPE="${UU_DEVICE_TYPE:-router}"
export UU_SN="${UU_SN:-}"
export UU_RANDOM="${UU_RANDOM:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo default)}"
export UU_PLUGIN_VESION="${UU_PLUGIN_VESION:-1.0.0}"
export UU_ROUTE_DEFAULT_TABLE="${UU_ROUTE_DEFAULT_TABLE:-main}"
export UU_ROUTE_FWMARK_TABLE="${UU_ROUTE_FWMARK_TABLE:-163}"
export UU_DEVICE_MAC="${UU_DEVICE_MAC:-00:00:00:00:00:00}"
export UU_DEVICE_IP="${UU_DEVICE_IP:-127.0.0.1}"
export UU_DEVICE_FWMARK="${UU_DEVICE_FWMARK:-0}"
export UU_DEVICE_LINK_TYPE="${UU_DEVICE_LINK_TYPE:-ethernet}"
export UU_FIRMWARE_VERSION="${UU_FIRMWARE_VERSION:-1.0.0}"
export UU_N_PR_H="${UU_N_PR_H:-0}"

# ── running directory ─────────────────────────────────────────────────────
RUNDIR="/tmp/uu"
mkdir -p "$RUNDIR" /var/run /etc/config

cp /opt/uu/bin/uuplugin         "$RUNDIR/"
cp /opt/uu/bin/xuplugin-guardian "$RUNDIR/"
cp /opt/uu/conf/uu.conf         "$RUNDIR/"
chmod +x "$RUNDIR/uuplugin" "$RUNDIR/xuplugin-guardian"

# ── files binary reads (from .rodata strings) ─────────────────────────────
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

cat > "$RUNDIR/uuplugin_monitor.config" << 'EOF'
router=openwrt
model=x86_64
EOF

# ── start ─────────────────────────────────────────────────────────────────
ulimit -HS -s 8192
cd "$RUNDIR"
exec ./uuplugin ./uu.conf
