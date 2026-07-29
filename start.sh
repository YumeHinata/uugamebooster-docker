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

# ── 运行时加固（防止 overlay/restart 导致关键文件丢失） ──
chmod +x /arm-root/bin/busybox 2>/dev/null
[ -L /arm-root/bin/sh ] || ln -sf /bin/sh /arm-root/bin/sh 2>/dev/null
mkdir -p /lib 2>/dev/null
[ -L /lib/xtables ] || ln -sf /usr/lib/x86_64-linux-gnu/xtables /lib/xtables 2>/dev/null

# ── 动态链接器修复 ──
echo "[DIAG] Dynamic linker state:"
ls -la /arm-root/lib/ld-musl-aarch64.so.1 2>&1 | sed 's/^/  /'
ls -la /arm-root/lib/libc.so 2>&1 | sed 's/^/  /'
# 1) 确保 libc.so 有执行权限（QEMU 加载 PIE 二进制时需 mmap PROT_EXEC 解释器）
chmod +x /arm-root/lib/libc.so
# 2) 用实际副本替代符号链接（避免 QEMU 解析 symlink 的潜在问题）
rm -f /arm-root/lib/ld-musl-aarch64.so.1
cp /arm-root/lib/libc.so /arm-root/lib/ld-musl-aarch64.so.1
chmod +x /arm-root/lib/ld-musl-aarch64.so.1
echo "  After fix: $(ls -la /arm-root/lib/ld-musl-aarch64.so.1 2>&1)"

# ── 验证 ARM 二进制可执行性 ──
echo "[DIAG] Testing ARM binary execution..."
BUSYBOX_ERR=$(/usr/bin/qemu-aarch64-static -L /arm-root /arm-root/bin/busybox echo hello 2>&1)
BUSYBOX_RET=$?
echo "  busybox test: exit=$BUSYBOX_RET output='$BUSYBOX_ERR'"
if [ $BUSYBOX_RET -eq 0 ]; then
    echo "  [OK] busybox (ARM) runs"
else
    echo "  [FAIL] busybox: $BUSYBOX_ERR"
fi
GUARDIAN_ERR=$(/usr/bin/qemu-aarch64-static -L /arm-root ./xuplugin-guardian.real 2>&1 | head -1)
echo "  guardian test: '$GUARDIAN_ERR'"

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

# ── WAN1 虚拟接口（uuplugin 硬编码检查此接口名） ──
# iStoreOS 使用 pppoe-wan/eth0 等非标准名称，需创建 dummy 别名
if ! ip link show WAN1 >/dev/null 2>&1; then
    echo "[DIAG] Creating WAN1 dummy interface (uuplugin requires it)"
    ip link add WAN1 type dummy 2>/dev/null && \
        echo "  [OK] WAN1 dummy created" || \
        echo "  [WARN] WAN1 create failed (check NET_ADMIN)"
fi
if ip link show WAN1 >/dev/null 2>&1; then
    ip link set WAN1 up 2>/dev/null
    echo "[OK] WAN1 UP"
else
    echo "[WARN] WAN1 missing — uuplugin may fail init!"
fi

# ── natflushdev FIFO（uuplugin ↔ uuclearnat IPC 通道） ──
# QEMU_LD_PREFIX 将 /dev/natflushdev 映射到 /arm-root/dev/natflushdev
# uuclearnat.sh 也是原生 x86_64，同样访问 /arm-root/dev/natflushdev
NATFLUSH="/arm-root/dev/natflushdev"
if [ ! -p "$NATFLUSH" ]; then
    echo "[DIAG] Creating FIFO $NATFLUSH"
    rm -f "$NATFLUSH" 2>/dev/null
    mkdir -p "$(dirname "$NATFLUSH")"
    mkfifo "$NATFLUSH" 2>/dev/null || echo "[WARN] mkfifo $NATFLUSH failed"
    chmod 666 "$NATFLUSH" 2>/dev/null
fi
if [ -p "$NATFLUSH" ]; then
    echo "[OK] $NATFLUSH FIFO ready"
else
    echo "[WARN] $NATFLUSH FIFO not available (uuplugin may hang!)"
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
    if [ -n "${FIXED_SN}" ]; then
        SN="${FIXED_SN}"
        echo "[INFO] Using fixed SN from FIXED_SN env: $SN"
    else
        SN=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 16)
        echo "[INFO] Generated random SN (set FIXED_SN env to persist across rebuilds)"
    fi
    printf 'manucode=R3600\nproductname=R3600\nmac=%s\nsn=%s\n' "$MAC" "$SN" > /var/tmp/uu/h3c_info
    echo "[INFO] h3c_info created (MAC=$MAC, SN=$SN)"
fi

# ── factoryinfo（H3C 路由器工厂信息，uuplugin 初始化必需） ──
# QEMU_LD_PREFIX 将 /proc/manufactory/factoryinfo 映射到此路径
mkdir -p /arm-root/proc/manufactory
if [ ! -f /arm-root/proc/manufactory/factoryinfo ]; then
    MAC=$(cat /sys/class/net/eth0/address 2>/dev/null | head -1 || echo "00:e0:b4:1b:6d:b8")
    printf 'manucode=R3600\nproductname=R3600\nmac=%s\nsn=%s\nwan_if=WAN1\nwan_mtu=1492\npath_mtu=1492\nrsv=0\n' \
        "$MAC" "${FIXED_SN:-DEADBEEFCAFE0001}" > /arm-root/proc/manufactory/factoryinfo
    echo "[INFO] factoryinfo created"
fi

# ── activate_status（uuplugin 用 inotify 监控此文件的激活状态） ──
# QEMU_LD_PREFIX 将 /tmp/uu/activate_status 映射到此路径
if [ ! -f /arm-root/tmp/uu/activate_status ]; then
    echo "0" > /arm-root/tmp/uu/activate_status
    echo "[INFO] activate_status initialized"
fi

# ── 清理旧容器遗留的 iptables/ip rules（host networking 下不随容器删除） ──
echo "[DIAG] Cleaning up leftover rules from previous container runs..."
# 清理 mangle INPUT DROP（uuplugin 的客户端加速标记）
iptables -t mangle -F INPUT 2>/dev/null
echo "  mangle INPUT flushed"
# 清理 mangle PREROUTING MARK（uuclearnat 添加的，只删 fwmark 0x163 的）
RULE_NUM=$(iptables -t mangle -L PREROUTING -n --line-numbers 2>/dev/null | grep -c "MARK set 0x163")
if [ "$RULE_NUM" -gt 0 ]; then
    iptables -t mangle -L PREROUTING -n --line-numbers 2>/dev/null | \
        grep "MARK set 0x163" | awk '{print $1}' | sort -rn | \
        while read N; do iptables -t mangle -D PREROUTING "$N" 2>/dev/null; done
    echo "  mangle PREROUTING: $RULE_NUM MARK rules removed"
else
    echo "  mangle PREROUTING: no leftover MARK rules"
fi
# 清理 nat PREROUTING DNAT（uuclearnat 添加的 DNS 重定向到 8.8.8.8）
RULE_NUM=$(iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep -c "to:8.8.8.8")
if [ "$RULE_NUM" -gt 0 ]; then
    iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | \
        grep "to:8.8.8.8" | awk '{print $1}' | sort -rn | \
        while read N; do iptables -t nat -D PREROUTING "$N" 2>/dev/null; done
    echo "  nat PREROUTING: $RULE_NUM DNAT rules removed"
else
    echo "  nat PREROUTING: no leftover DNAT rules"
fi
# 只清理 tun163 相关的 POSTROUTING MASQUERADE（不碰宿主机的规则！）
iptables -t nat -D POSTROUTING -o tun163 -j MASQUERADE 2>/dev/null && \
    echo "  nat POSTROUTING: tun163 MASQUERADE removed" || \
    echo "  nat POSTROUTING: no tun163 rules (host rules preserved)"
# 只清理 tun163 相关的 FORWARD ACCEPT（不碰宿主机的规则！）
iptables -t filter -D FORWARD -i tun163 -j ACCEPT 2>/dev/null
DEL_COUNT=0
iptables -t filter -D FORWARD -o tun163 -j ACCEPT 2>/dev/null && DEL_COUNT=$((DEL_COUNT+1))
[ "$DEL_COUNT" -gt 0 ] && echo "  filter FORWARD: $DEL_COUNT tun163 rules removed" || \
    echo "  filter FORWARD: no tun163 rules (host rules preserved)"
# 清理旧的 tun163 设备
ip link del tun163 2>/dev/null && echo "  tun163 device removed" || echo "  tun163: no leftover device"
# 清理旧的 WAN1 dummy（上次运行残留，将在启动时重新创建）
ip link del WAN1 2>/dev/null
# 清理旧的 ip rules（table 163 相关，可能有上千条）
DELETED=0
echo "  cleaning ip rules (this may take a moment)..."
while ip rule show 2>/dev/null | grep -q "lookup 163"; do
    LINE=$(ip rule show 2>/dev/null | grep "lookup 163" | head -1)
    PRIO=$(echo "$LINE" | awk -F: '{print $1}' | tr -d ' ')
    if [ -n "$PRIO" ]; then
        ip rule del prio "$PRIO" 2>/dev/null
        DELETED=$((DELETED + 1))
    else
        break
    fi
done
echo "  ip rules cleaned: $DELETED entries removed"

# ── 启动 ──
echo "[INFO] Starting uuplugin (with -L /arm-root for child exec)..."
if [ "${QEMU_DEBUG}" = "1" ]; then
    # 调试模式：stderr + strace 进程追踪
    QEMU_STRACE=1 /usr/bin/qemu-aarch64-static -L /arm-root ./uuplugin \
        2>/tmp/uuplugin_stderr.log &
    UU_PID=$!
    sleep 3
    strace -e trace=clone,fork,vfork,execve,execveat -f -p $UU_PID \
        -o /tmp/uuplugin_proc_trace.log &
    STRACE_PID=$!
    echo "[DIAG] uuplugin PID=$UU_PID, strace PID=$STRACE_PID"
    echo "[DIAG] stderr → /tmp/uuplugin_stderr.log"
    echo "[DIAG] proc trace → /tmp/uuplugin_proc_trace.log"
    echo ""
    echo "=== Now trigger acceleration from phone, wait 30s, then: ==="
    echo "docker exec UUgamebooster cat /tmp/uuplugin_stderr.log"
    echo "docker exec UUgamebooster grep -a execve /tmp/uuplugin_proc_trace.log | tail -20"
    echo ""
    wait $UU_PID 2>/dev/null
    RET=$?
    echo "[ERROR] uuplugin exited with code $RET"
    kill $STRACE_PID 2>/dev/null
    echo "=== stderr log ==="
    tail -30 /tmp/uuplugin_stderr.log 2>/dev/null
    while true; do sleep 3600; done
else
    # 正常模式：带自动重启的主循环
    RESTART_COUNT=0
    while true; do
        # 清理上次遗留的 guardian 进程（uuplugin 被杀后 guardian 成为孤儿）
        OLD_GUARDIANS=$(ps | grep "xuplugin-guardian" | grep -v grep | awk '{print $1}')
        if [ -n "$OLD_GUARDIANS" ]; then
            echo "[CLEANUP] Killing orphaned guardians: $OLD_GUARDIANS"
            kill $OLD_GUARDIANS 2>/dev/null
            sleep 1
        fi
        # 清理上次遗留的 uuclearnat 进程
        OLD_LEARNAT=$(ps | grep "uuclearnat" | grep -v grep | grep -v "$$" | awk '{print $1}')
        if [ -n "$OLD_LEARNAT" ]; then
            echo "[CLEANUP] Killing orphaned uuclearnat processes: $OLD_LEARNAT"
            kill $OLD_LEARNAT 2>/dev/null
            sleep 1
        fi
        # 清理旧的 pid 文件（否则 uuplugin 误判已有实例在运行 → exit(255)）
        rm -f /var/run/uuplugin.pid 2>/dev/null
        echo "[INFO] Starting uuplugin (attempt $((RESTART_COUNT + 1)))..."
        # 用 background + wait 捕获真实退出码（pipeline 的 $? 只反映 tee）
        /usr/bin/qemu-aarch64-static -L /arm-root ./uuplugin \
            >/tmp/uuplugin_stdout.log 2>/tmp/uuplugin_stderr.log &
        UU_PID=$!
        wait $UU_PID
        REAL_RET=$?
        RESTART_COUNT=$((RESTART_COUNT + 1))
        # 判断是信号还是正常退出
        if [ $REAL_RET -ge 128 ]; then
            SIG_NUM=$((REAL_RET - 128))
            echo "[WARN] uuplugin killed by signal $SIG_NUM (exit=$REAL_RET, restarts=$RESTART_COUNT)"
        elif [ $REAL_RET -eq 0 ]; then
            echo "[INFO] uuplugin exited normally (restarts=$RESTART_COUNT)"
        else
            echo "[WARN] uuplugin exited with code $REAL_RET (restarts=$RESTART_COUNT)"
        fi
        # 打印 stderr 的最后几行帮助诊断
        echo "[DIAG] Last stderr lines:"
        tail -5 /tmp/uuplugin_stderr.log 2>/dev/null
        if [ $REAL_RET -eq 0 ]; then
            echo "[INFO] Normal exit, restarting in 5s..."
        else
            echo "[WARN] Crash detected, restarting in 10s..."
        fi
        sleep 10
    done
fi
