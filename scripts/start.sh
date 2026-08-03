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

exec /opt/uu/bin/uuplugin /opt/uu/conf/uu.conf
