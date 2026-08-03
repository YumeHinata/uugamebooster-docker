#!/bin/sh
# ── Minimal start.sh: place 3 binaries at correct paths, start uuplugin ──
# uuplugin spawns xuplugin-guardian + /bin/uuclearnat internally.

echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# TUN device
mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200

# WAN1 dummy (binary hardcodes this interface)
ip link add WAN1 type dummy 2>/dev/null
ip link set WAN1 up 2>/dev/null

# iptables legacy mode
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null

export UU_LAN_IP="${UU_LAN_IP:-192.168.0.1}"
export UU_LAN_NAME="${UU_LAN_NAME:-br-lan}"
# These are set by OpenWrt init on real devices; binary getenv(NULL) → SIGABRT
export UU_WAN_IP="${UU_WAN_IP:-0.0.0.0}"
export UU_TUN_IP="${UU_TUN_IP:-10.0.0.1}"
export UU_TUN_NAME="${UU_TUN_NAME:-tun163}"
export UU_VENDOR="${UU_VENDOR:-openwrt}"
export UU_MODEL="${UU_MODEL:-openwrt-x86_64}"
export UU_DEVICE_TYPE="${UU_DEVICE_TYPE:-router}"
export UU_SN="${UU_SN:-}"
export UU_PLUGIN_VESION="${UU_PLUGIN_VESION:-1.0.0}"
export UU_ROUTE_DEFAULT_TABLE="${UU_ROUTE_DEFAULT_TABLE:-main}"
export UU_ROUTE_FWMARK_TABLE="${UU_ROUTE_FWMARK_TABLE:-163}"
export UU_DEVICE_MAC="${UU_DEVICE_MAC:-00:00:00:00:00:00}"
export UU_DEVICE_IP="${UU_DEVICE_IP:-127.0.0.1}"
export UU_DEVICE_FWMARK="${UU_DEVICE_FWMARK:-0}"
export UU_DEVICE_LINK_TYPE="${UU_DEVICE_LINK_TYPE:-ethernet}"
export UU_FIRMWARE_VERSION="${UU_FIRMWARE_VERSION:-1.0.0}"
export UU_N_PR_H="${UU_N_PR_H:-0}"
export HOME="${HOME:-/root}"
export HOSTNAME="${HOSTNAME:-$(hostname)}"

# strace to catch the exact crash point
strace -f -o /tmp/strace.log /opt/uu/bin/uuplugin /opt/uu/conf/uu.conf &
UU_PID=$!
wait $UU_PID
RET=$?
echo "uuplugin exited code=$RET, last strace lines:"
tail -30 /tmp/strace.log
