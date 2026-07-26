#!/bin/sh
echo "=================================="
echo "UU Plugin Docker Runtime"
echo "=================================="

# ── QEMU 环境 ──
# -L 参数确保 QEMU 对子进程 exec 也使用正确的动态链接器路径
export QEMU_LD_PREFIX=/arm-root
export LD_LIBRARY_PATH=/lib:/usr/lib
# QEMU 调试日志（设置 QEMU_DEBUG=1 开启，日志写入 /tmp/qemu.log）
if [ "${QEMU_DEBUG}" = "1" ]; then
    export QEMU_LOG_FILENAME=/tmp/qemu.log
    export QEMU_LOG=exec,cpu_reset
    export QEMU_STRACE=1
    echo "[DIAG] QEMU debug logging enabled -> /tmp/qemu.log"
fi
cd /arm-root

# ── 动态链接器检查 ──
echo "[DIAG] Dynamic linker state:"
ls -la /arm-root/lib/ld-musl-aarch64.so.1 2>&1 | sed 's/^/  /'
ls -la /arm-root/lib/libc.so 2>&1 | sed 's/^/  /'
# 强制重建符号链接（无论当前状态如何）
ln -sf libc.so /arm-root/lib/ld-musl-aarch64.so.1
echo "  After fix: $(ls -la /arm-root/lib/ld-musl-aarch64.so.1 2>&1)"

# ── 验证 ARM 二进制可执行性（显示完整错误） ──
echo "[DIAG] Testing ARM binary execution..."
echo "  qemu binary: $(ls -la /usr/bin/qemu-aarch64-static 2>&1)"
echo "  busybox ELF header:"
head -c 20 /arm-root/bin/busybox | od -A x -t x1z 2>&1 | head -2 | sed 's/^/    /'
BUSYBOX_ERR=$(/usr/bin/qemu-aarch64-static -L /arm-root /arm-root/bin/busybox true 2>&1)
BUSYBOX_RET=$?
echo "  busybox test: exit=$BUSYBOX_RET output='$BUSYBOX_ERR'"
if [ $BUSYBOX_RET -eq 0 ]; then
    echo "  [OK] busybox (ARM) runs"
else
    echo "  [FAIL] busybox (ARM) cannot execute!"
    echo "  Trying without -L:"
    /usr/bin/qemu-aarch64-static /arm-root/bin/busybox true 2>&1 | sed 's/^/    /'
    echo "  Trying with QEMU_LD_PREFIX only:"
    QEMU_LD_PREFIX=/arm-root /usr/bin/qemu-aarch64-static /arm-root/bin/busybox true 2>&1 | sed 's/^/    /'
fi

# ── iptables legacy 切换 ──
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null

# ── TUN 设备检查（加速核心依赖） ──
if [ ! -e /dev/net/tun ]; then
    echo "[WARN] /dev/net/tun not found, trying to create..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200 2>/dev/null
    chmod 666 /dev/net/tun 2>/dev/null
fi
if [ -e /dev/net/tun ]; then
    echo "[OK] /dev/net/tun available"
else
    echo "[FATAL] /dev/net/tun unavailable! Acceleration will fail."
    echo "        Run with: --device /dev/net/tun --cap-add NET_ADMIN"
fi

# ── 网络工具链检查 ──
echo "[DIAG] Tool chain check:"
for tool in /arm-root/usr/sbin/iptables /arm-root/sbin/ip /arm-root/usr/sbin/ipset /arm-root/usr/sbin/nft; do
    if [ -x "$tool" ]; then
        echo "  [OK] $tool"
    else
        echo "  [MISS] $tool"
    fi
done
iptables -w -L -n >/dev/null 2>&1 && echo "  [OK] iptables works" || echo "  [FAIL] iptables (need NET_ADMIN?)"
ip link show >/dev/null 2>&1 && echo "  [OK] ip works" || echo "  [FAIL] ip"

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
echo "[INFO] Starting uuplugin (with -L /arm-root for child exec)..."
/usr/bin/qemu-aarch64-static -L /arm-root ./uuplugin
RET=$?
echo "[ERROR] uuplugin exited with code $RET"
echo "[DEBUG] Keeping container alive for inspection (Ctrl+C to stop)..."
echo "  Check: docker exec -it <container> /bin/sh"
# 保持容器运行以便调试
while true; do sleep 3600; done
