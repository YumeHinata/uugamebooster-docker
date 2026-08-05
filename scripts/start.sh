#!/bin/sh
# start.sh — mirrors uuplugin_monitor.sh startup flow
#   init_param → download_url_init → system_init → start_acc

# ── network ───────────────────────────────────────────────────────────────
echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200
# Create br-lan bridge (binary binds LAN discovery here; SN = its MAC)
ip link add br-lan type bridge 2>/dev/null
ip link set br-lan up
ip addr add "${UU_LAN_IP:-192.168.0.1}/24" dev br-lan 2>/dev/null || true
ip link add WAN1 type dummy 2>/dev/null
ip link set WAN1 up 2>/dev/null
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true

# ── system_init ────────────────────────────────────────────────────────────
ulimit -HS -s 8192
ulimit -HS -n 1024

# ── init_param: read router/model from uuplugin_monitor.config ─────────────
RUNDIR="/tmp/uu"
mkdir -p "$RUNDIR" /var/run /etc/config
cp /opt/uu/bin/uuplugin              "$RUNDIR/"
cp /opt/uu/bin/xuplugin-guardian     "$RUNDIR/"
cp /opt/uu/bin/xtables-nft-multi     "$RUNDIR/"
cp /opt/uu/bin/uuplugin_monitor.sh   "$RUNDIR/"
cp /opt/uu/conf/uu.conf              "$RUNDIR/"
cat > "$RUNDIR/uuplugin_monitor.config" << 'EOF'
router=openwrt
model=x86_64
EOF
chmod +x "$RUNDIR/uuplugin" "$RUNDIR/xuplugin-guardian" \
    "$RUNDIR/xtables-nft-multi" "$RUNDIR/uuplugin_monitor.sh"

# ── download_url_init: SN = MAC of LAN bridge ───────────────────────────
UU_SN=$(ip addr show "${UU_LAN_NAME:-br-lan}" 2>/dev/null | grep "link/ether" | awk '{print $2}' | head -1)
[ -z "$UU_SN" ] && UU_SN=$(ip addr show eth0 2>/dev/null | grep "link/ether" | awk '{print $2}' | head -1)
[ -z "$UU_SN" ] && UU_SN=$(head -c 16 /dev/urandom | md5sum | head -c 20)
echo "$UU_SN" > "$RUNDIR/.sn"
mkdir -p /usr/sbin/uu
echo "$UU_SN" > /usr/sbin/uu/.sn

# ── env: all 20 UU_* strings in binary must be set (prevents NULL getenv) ──
export UU_LAN_IP="${UU_LAN_IP:-192.168.0.1}"
export UU_LAN_NAME="${UU_LAN_NAME:-br-lan}"
export UU_WAN_IP="0.0.0.0"
export UU_TUN_IP="10.0.0.1"
export UU_TUN_NAME="tun163"
export UU_VENDOR="openwrt"
export UU_MODEL="x86_64"
export UU_DEVICE_TYPE="router"
export UU_SN="$UU_SN"
export UU_RANDOM="default"
export UU_PLUGIN_VESION="1.0.0"
export UU_ROUTE_DEFAULT_TABLE="main"
export UU_ROUTE_FWMARK_TABLE="163"
export UU_DEVICE_MAC=""
export UU_DEVICE_IP=""
export UU_DEVICE_FWMARK=""
export UU_DEVICE_LINK_TYPE=""
export UU_FIRMWARE_VERSION="1.0.0"
export UU_N_PR_H="0"
export HOME="/root"
export USER="root"
export TZ="CST-8"

# ── runtime files binary expects ──────────────────────────────────────────
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

# ── start_acc ──────────────────────────────────────────────────────────────
cd "$RUNDIR"
exec ./uuplugin ./uu.conf
