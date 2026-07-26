#!/bin/sh
echo "=================================="
echo "UU Plugin Docker Runtime"
echo "=================================="

# ── QEMU 环境（仅影响动态库加载，不影响 openat 等文件 syscall） ──
export QEMU_LD_PREFIX=/arm-root
export LD_LIBRARY_PATH=/lib:/usr/lib
cd /arm-root

# ── 动态链接器检查 ──
[ -s /arm-root/lib/ld-musl-aarch64.so.1 ] || ln -sf libc.so /arm-root/lib/ld-musl-aarch64.so.1

# ── iptables legacy 切换 ──
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null

# ── 设备标识文件（绑定必需，创建在容器真实路径） ──
echo "CST-8" > /etc/TZ
echo "R3600" > /var/model
mkdir -p /var/tmp/uu /tmp/uu
if [ ! -f /var/tmp/uu/h3c_info ]; then
    MAC=$(cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address 2>/dev/null || echo "00:00:00:00:00:00")
    SN=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 16)
    printf 'manucode=R3600\nproductname=R3600\nmac=%s\nsn=%s\n' "$MAC" "$SN" > /var/tmp/uu/h3c_info
    echo "[INFO] h3c_info created (MAC=$MAC, SN=$SN)"
fi

# ── 启动 ──
echo "[INFO] Starting uuplugin..."
exec /usr/bin/qemu-aarch64-static ./uuplugin
