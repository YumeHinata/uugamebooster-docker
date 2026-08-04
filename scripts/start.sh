#!/bin/sh

# ── network setup ────────────────────────────────────────────────────────
echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200

ip link add WAN1 type dummy 2>/dev/null
ip link set WAN1 up 2>/dev/null

update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true

# ── lands devname (H3C init.d writes this, binary reads it) ──────────────
mkdir -p /var/run
echo "${UU_LAN_NAME:-br-lan}" > /var/run/landevname.txt

# ── running directory (matches official OpenWrt /tmp/uu) ─────────────────
RUNDIR="/tmp/uu"
mkdir -p "$RUNDIR"

cp /opt/uu/bin/uuplugin         "$RUNDIR/" 2>/dev/null
cp /opt/uu/bin/xuplugin-guardian "$RUNDIR/" 2>/dev/null
cp /opt/uu/conf/uu.conf         "$RUNDIR/" 2>/dev/null
chmod +x "$RUNDIR/uuplugin" "$RUNDIR/xuplugin-guardian"

# ── monitor config (official format, read by monitor/binary) ─────────────
cat > "$RUNDIR/uuplugin_monitor.config" << 'EOF'
router=openwrt
model=x86_64
EOF

# ── start (matches official start_acc + system_init) ─────────────────────
ulimit -HS -s 8192
cd "$RUNDIR"
exec ./uuplugin ./uu.conf
