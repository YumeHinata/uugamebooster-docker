#!/bin/sh

# ── network setup ────────────────────────────────────────────────────────
echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200

ip link add WAN1 type dummy 2>/dev/null
ip link set WAN1 up 2>/dev/null

update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true

# ── running directory (matches official OpenWrt /tmp/uu) ─────────────────
RUNDIR="/tmp/uu"
mkdir -p "$RUNDIR" /var/run

cp /opt/uu/bin/uuplugin         "$RUNDIR/" 2>/dev/null
cp /opt/uu/bin/xuplugin-guardian "$RUNDIR/" 2>/dev/null
cp /opt/uu/conf/uu.conf         "$RUNDIR/" 2>/dev/null
chmod +x "$RUNDIR/uuplugin" "$RUNDIR/xuplugin-guardian"

# ── runtime files (binary reads these) ────────────────────────────────────
echo "${UU_LAN_NAME:-br-lan}" > /var/run/landevname.txt
touch /tmp/.uu_whoami.txt

cat > "$RUNDIR/uuplugin_monitor.config" << 'EOF'
router=openwrt
model=x86_64
EOF

# ── start under gdb to capture crash backtrace ────────────────────────────
ulimit -HS -s 8192
cd "$RUNDIR"

echo "=== gdb break __cxa_throw ==="
gdb -batch \
    -ex "set pagination off" \
    -ex "set confirm off" \
    -ex "set breakpoint pending on" \
    -ex "break __cxa_throw" \
    -ex "run" \
    -ex "bt 50" \
    -ex "info registers" \
    -ex "quit" \
    --args ./uuplugin ./uu.conf 2>&1
echo "=== gdb done ==="
