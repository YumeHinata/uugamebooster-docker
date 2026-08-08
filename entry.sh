#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
# QEMU NX30Pro uuplugin — 生产级启动脚本 (Plan A: 保留 guardian)
# ═══════════════════════════════════════════════════════════════════
# 运行 NX30Pro aarch64 uuplugin + guardian（QEMU user-mode）
# 直连 H3C 注册服，无 MITM 中间层
#
# 可剥离层级：
#   UU_STRACE=1    strace 调试模式（默认关闭）
#   UU_DEBUG=1     详细日志输出

set -e

UU_STRACE="${UU_STRACE:-0}"
UU_DEBUG="${UU_DEBUG:-0}"

RUNDIR="/tmp/uu"
UU_BIN="/opt/uu/bin/uuplugin"
UU_CONF="/opt/uu/conf/uu.conf"
GUARDIAN_BIN="/opt/uu/bin/xuplugin-guardian"

echo "============================================"
echo "  QEMU NX30Pro uuplugin (Production)"
echo "  Binary:   $UU_BIN"
echo "  Config:   $UU_CONF"
echo "  Guardian: $GUARDIAN_BIN (Plan A: native fork+exec)"
echo "  Sysroot:  /arm-root"
echo "============================================"

# ═══════════════════════════════════════════════════════════════════
# L0 — 基线运行环境（始终启用）
# ═══════════════════════════════════════════════════════════════════

# ── 清理残留规则（解决切换/重启后 iptables/DNS 残留） ──
echo "[L0] Cleaning up stale rules from previous runs..."
# MITM 残留: DNAT 16000 (旧测试环境)
while xtables-nft-multi -t nat -D OUTPUT -p tcp --dport 16000 -j DNAT --to-destination 127.0.0.1:16000 2>/dev/null; do :; done
while xtables-nft-multi -t nat -D OUTPUT -p tcp --dport 16000 -m mark ! --mark 0x1 -j DNAT --to-destination 127.0.0.1:16000 2>/dev/null; do :; done
while xtables-nft-multi -t nat -D OUTPUT -p tcp --dport 443 -d 127.0.0.1 -j DNAT --to-destination 127.0.0.1:16000 2>/dev/null; do :; done
# L3 残留: REDIRECT 16363→16365, 14554→14555
while xtables-nft-multi -t nat -D PREROUTING -p tcp --dport 16363 -j REDIRECT --to-port 16365 2>/dev/null; do :; done
while xtables-nft-multi -t nat -D PREROUTING -p tcp --dport 14554 -j REDIRECT --to-port 14555 2>/dev/null; do :; done
# DNS hijack 残留
sed -i '/rglg.uu.163.com/d; /h3crglg.uu.163.com/d' /etc/hosts 2>/dev/null || true
# 二进制自身残留: DROP 规则
xtables-nft-multi -D INPUT -p tcp -s 127.0.0.1 -d 127.0.0.1 -j DROP 2>/dev/null || true
# ip rule 残留
ip rule del fwmark 0x162 lookup 354 2>/dev/null || true
while ip rule del fwmark 0x163 lookup 163 2>/dev/null; do :; done
while ip rule del fwmark 0x164 lookup 163 priority 32760 2>/dev/null; do :; done
while ip rule del fwmark 0x164 lookup 163 priority 100 2>/dev/null; do :; done
ip route flush table 179 2>/dev/null || true
ip rule del from 0/0 lookup 179 2>/dev/null || true
# pid 文件残留（容器重启时 uuplugin 检测到此文件会拒绝启动）
rm -f /run/uuplugin.pid /run/xuplugin-guardian.pid 2>/dev/null || true
echo "[L0] Stale rules cleaned"

# ── 网桥 + TUN ──
ip link add br-lan type bridge 2>/dev/null || true
ip link set br-lan up 2>/dev/null || true

mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200

# ── natflushd: FIFO IPC daemon (replaces old uuclearnat) ──
# uuplugin fork+exec's /usr/bin/uuclearnat → runs natflushd.sh
# Responsibilities:
#   1. /dev/natflushdev FIFO bidirectional protocol (20B binary messages)
#   2. Send READY(0) on startup, ALIVE(1) heartbeat every 30s
#   3. Receive CLIENT_NOTIFY(9) → ACK back to uuplugin
#   Does NOT create iptables rules — uuplugin handles ALL rule management
rm -f /dev/natflushdev 2>/dev/null
mkfifo /dev/natflushdev 2>/dev/null || true
chmod 666 /dev/natflushdev 2>/dev/null || true

# natflushd runs as the single FIFO handler (no competing readers/writers)
/tmp/natflushd.sh &
echo "[L0] natflushd started (FIFO IPC handler, binary protocol)"

# ── MITM: TLS proxy for monitoring uuplugin ↔ UU server (protobuf frames) ──
# H3C control channel: uuplugin → 106.2.95.34:16000
# DNAT all port 16000 traffic → MITM on 127.0.0.1:16000 (except MITM's own, mark 0x1)
if [ -x /tmp/uu_mitm_monitor.py ] && command -v python3 >/dev/null 2>&1; then
    # DNS hijack: force registration domain to localhost
    grep -q 'rglg.uu.163.com' /etc/hosts 2>/dev/null || \
        echo '127.0.0.1 rglg.uu.163.com' >> /etc/hosts
    # DNAT: redirect outgoing 16000 → MITM (skip MITM's own traffic with mark 0x1)
    iptables -t nat -C OUTPUT -p tcp --dport 16000 -m mark ! --mark 0x1 -j DNAT --to-destination 127.0.0.1:16000 2>/dev/null || \
        iptables -t nat -A OUTPUT -p tcp --dport 16000 -m mark ! --mark 0x1 -j DNAT --to-destination 127.0.0.1:16000 2>/dev/null
    python3 /tmp/uu_mitm_monitor.py >> /tmp/mitm_monitor.log 2>&1 &
    echo "[L0] MITM monitor started (port 16000 → protobuf logging to /tmp/mitm_monitor.log)"
else
    echo "[L0] MITM monitor SKIPPED (python3 or uu_mitm_monitor.py not available)"
fi

# ── iptables 自锁修复守护 ──
# 二进制会 -I INPUT X DROP 127.0.0.1 自己的 IPC 端口
# 仅当 lo ACCEPT 缺失时才介入
(
    # 守护进程：每隔60s检查 lo ACCEPT 规则是否被 uuplugin 意外清除
    while true; do
        sleep 60
        if ! xtables-legacy-multi -C INPUT -i lo -j ACCEPT 2>/dev/null; then
            xtables-legacy-multi -I INPUT 1 -i lo -j ACCEPT 2>/dev/null
            [ "$UU_DEBUG" = "1" ] && echo "[L0] iptables: re-added lo ACCEPT"
        fi
    done
) &
echo "[L0] iptables self-lock fix daemon started (check-only, 60s interval)"

# ── iptables 基线（OpenWrt 标准） ──
xtables-nft-multi -A INPUT -i lo -j ACCEPT 2>/dev/null || true
xtables-nft-multi -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

# ── conntrack wrapper: 兜底修复 musl 静态链接兼容性 ──
if command -v conntrack >/dev/null 2>&1 && [ ! -f /usr/sbin/conntrack.real ]; then
    CONNTRACK_REAL=$(command -v conntrack)
    mv "$CONNTRACK_REAL" /usr/sbin/conntrack.real
fi
cat > /usr/sbin/conntrack << 'CTEOF'
#!/bin/sh
echo "$(date '+%H:%M:%S') conntrack $*" >> /tmp/conntrack_wrapper.log
/usr/sbin/conntrack.real "$@"
RC=$?
echo "  -> exit=$RC" >> /tmp/conntrack_wrapper.log
exit $RC
CTEOF
chmod +x /usr/sbin/conntrack
echo "[L0] conntrack wrapper installed"

# ── nft wrapper: 日志所有 nft 调用 + SIGSEGV 检测 ──
# Dockerfile 已从 bookworm 安装新版 nft (v1.0.6+) 替代 bullseye 的 v0.9.8（kernel 6.6 上 SIGSEGV）
echo "[L0] nft: $(nft --version 2>&1)"
if [ ! -f /usr/sbin/nft.real ]; then
    mv /usr/sbin/nft /usr/sbin/nft.real
fi
cat > /usr/sbin/nft << 'NFTEOF'
#!/bin/sh
echo "$(date '+%H:%M:%S') nft-wrap[$$] args=$*" >> /tmp/nft_wrap.log
/usr/sbin/nft.real "$@"
RC=$?
if [ $RC -eq 139 ]; then
    echo "  -> SIGSEGV!" >> /tmp/nft_wrap.log
elif [ $RC -ne 0 ]; then
    echo "  -> exit=$RC" >> /tmp/nft_wrap.log
fi
exit $RC
NFTEOF
chmod +x /usr/sbin/nft
echo "[L0] nft wrapper installed (logging to /tmp/nft_wrap.log)"

# ── xtables-legacy-multi wrapper: uuplugin 可能直接调用此二进制（绕过 iptables symlink）──
# 把真实二进制移走，在原地放 wrapper，拦截所有对 xtables-legacy-multi 的调用
if [ ! -f /usr/sbin/xtables-legacy-multi.real ]; then
    mv /usr/sbin/xtables-legacy-multi /usr/sbin/xtables-legacy-multi.real
fi
cat > /usr/sbin/xtables-legacy-multi << 'XTMEOF'
#!/bin/sh
# Wrapper: 确保 --dport/--sport 前有 -p tcp
unset XTABLES_LIBDIR
[ "$UU_DEBUG" = "1" ] && echo "$(date '+%H:%M:%S') xt-leg-wrap[$$] caller=$0 args=$*" >> /tmp/iptables_wrap.log
HAS_P=0
NEED_FIX=0
for a in "$@"; do
    [ "$a" = "-p" ] && HAS_P=1
    [ "$a" = "--protocol" ] && HAS_P=1
    case "$a" in --dport|--sport|--dports|--sports) NEED_FIX=1 ;; esac
done
if [ "$HAS_P" = "1" ] || [ "$NEED_FIX" = "0" ]; then
    /usr/sbin/xtables-legacy-multi.real "$@"
    RC=$?
    [ $RC -ne 0 ] && echo "$(date '+%H:%M:%S') xt-leg-wrap[$$] FAIL exit=$RC args=$*" >> /tmp/iptables_wrap.log
    exit $RC
fi
FIXED=""
DONE=0
for a in "$@"; do
    case "$a" in
        --dport|--sport|--dports|--sports)
            if [ "$DONE" = "0" ]; then
                FIXED="$FIXED -p tcp"
                DONE=1
            fi
            ;;
    esac
    FIXED="$FIXED $a"
done
[ "$UU_DEBUG" = "1" ] && echo "$(date '+%H:%M:%S') xt-leg-wrap[$$] FIXED=$FIXED" >> /tmp/iptables_wrap.log
/usr/sbin/xtables-legacy-multi.real $FIXED
RC=$?
[ $RC -ne 0 ] && echo "$(date '+%H:%M:%S') xt-leg-wrap[$$] FAIL exit=$RC args=$*" >> /tmp/iptables_wrap.log
exit $RC
XTMEOF
chmod +x /usr/sbin/xtables-legacy-multi
echo "[L0] xtables-legacy-multi wrapper installed"

# ── xtables-nft-multi wrapper: OpenWrt 子命令翻译 + --dport 修复 ──
# uuplugin (NX30Pro) 内部调用 xtables-nft-multi iptables-nft / iptables-translate 等
# Debian 的 xtables-nft-multi 不支持这些 OpenWrt 独有子命令
if [ ! -f /usr/sbin/xtables-nft-multi.real ]; then
    mv /usr/sbin/xtables-nft-multi /usr/sbin/xtables-nft-multi.real
fi
cat > /usr/sbin/xtables-nft-multi << 'XTMEOF'
#!/bin/sh
unset XTABLES_LIBDIR
[ "$UU_DEBUG" = "1" ] && echo "$(date '+%H:%M:%S') xt-nft-wrap[$$] caller=$0 args=$*" >> /tmp/iptables_wrap.log

# ── OpenWrt → Debian 子命令映射 ──
case "$1" in
    iptables-nft)        shift; set -- iptables "$@" ;;
    iptables-translate)  shift; set -- iptables-translate "$@" ;;
    ip6tables-nft)       shift; set -- ip6tables "$@" ;;
    ip6tables-translate) shift; set -- ip6tables-translate "$@" ;;
esac

HAS_P=0
NEED_FIX=0
for a in "$@"; do
    [ "$a" = "-p" ] && HAS_P=1
    [ "$a" = "--protocol" ] && HAS_P=1
    case "$a" in --dport|--sport|--dports|--sports) NEED_FIX=1 ;; esac
done
if [ "$HAS_P" = "1" ] || [ "$NEED_FIX" = "0" ]; then
    /usr/sbin/xtables-nft-multi.real "$@"
    RC=$?
    [ $RC -ne 0 ] && echo "$(date '+%H:%M:%S') xt-nft-wrap[$$] FAIL exit=$RC args=$*" >> /tmp/iptables_wrap.log
    exit $RC
fi
FIXED=""
DONE=0
for a in "$@"; do
    case "$a" in
        --dport|--sport|--dports|--sports)
            if [ "$DONE" = "0" ]; then
                FIXED="$FIXED -p tcp"
                DONE=1
            fi
            ;;
    esac
    FIXED="$FIXED $a"
done
[ "$UU_DEBUG" = "1" ] && echo "$(date '+%H:%M:%S') xt-nft-wrap[$$] FIXED=$FIXED" >> /tmp/iptables_wrap.log
/usr/sbin/xtables-nft-multi.real $FIXED
RC=$?
[ $RC -ne 0 ] && echo "$(date '+%H:%M:%S') xt-nft-wrap[$$] FAIL exit=$RC args=$*" >> /tmp/iptables_wrap.log
exit $RC
XTMEOF
chmod +x /usr/sbin/xtables-nft-multi
echo "[L0] xtables-nft-multi wrapper installed"

# ── iptables wrapper: 修复 uuplugin 调用 iptables 缺 -p tcp 导致 --dport 报错 ──
# uuplugin (aarch64) 可能通过 iptables/iptables-legacy/ip6tables/ip6tables-legacy 调用
# 所有路径都必须走 wrapper，wrapper 统一调用 main4（→ xtables-legacy-multi.real, 跳过 xtables wrapper）
# ⚠️ cp 会跟随 symlink 目标，必须先 rm 再写！
rm -f /usr/sbin/iptables /usr/sbin/iptables-legacy /usr/sbin/ip6tables /usr/sbin/ip6tables-legacy /usr/sbin/iptables-real /usr/sbin/main4 2>/dev/null
ln -sf /usr/sbin/xtables-legacy-multi.real /usr/sbin/main4
cat > /usr/sbin/iptables.wrap << 'IPTEOF'
#!/bin/sh
# Wrapper: 确保 --dport/--sport 前有 -p tcp（如果调用者漏了）
# 调试日志（设 UU_DEBUG=1 启用）
unset XTABLES_LIBDIR
[ "$UU_DEBUG" = "1" ] && echo "$(date '+%H:%M:%S') iptables-wrap[$$] caller=$0 args=$*" >> /tmp/iptables_wrap.log
HAS_P=0
NEED_FIX=0
for a in "$@"; do
    [ "$a" = "-p" ] && HAS_P=1
    [ "$a" = "--protocol" ] && HAS_P=1
    case "$a" in --dport|--sport|--dports|--sports) NEED_FIX=1 ;; esac
done

# 已有 -p 或无端口参数 → 直接透传给 main4（→ xtables-legacy-multi, legacy 后端）
if [ "$HAS_P" = "1" ] || [ "$NEED_FIX" = "0" ]; then
    /usr/sbin/main4 "$@"
    RC=$?
    [ $RC -ne 0 ] && echo "$(date '+%H:%M:%S') iptables-wrap[$$] FAIL exit=$RC args=$*" >> /tmp/iptables_wrap.log
    exit $RC
fi

# 缺 -p 但有端口参数 → 在第一个端口参数前插入 -p tcp
FIXED=""
DONE=0
for a in "$@"; do
    case "$a" in
        --dport|--sport|--dports|--sports)
            if [ "$DONE" = "0" ]; then
                FIXED="$FIXED -p tcp"
                DONE=1
            fi
            ;;
    esac
    FIXED="$FIXED $a"
done
[ "$UU_DEBUG" = "1" ] && echo "$(date '+%H:%M:%S') iptables-wrap[$$] FIXED=$FIXED" >> /tmp/iptables_wrap.log
/usr/sbin/main4 $FIXED
RC=$?
[ $RC -ne 0 ] && echo "$(date '+%H:%M:%S') iptables-wrap[$$] FAIL exit=$RC args=$*" >> /tmp/iptables_wrap.log
exit $RC
IPTEOF
chmod +x /usr/sbin/iptables.wrap
# 覆盖 iptables/iptables-legacy/ip6tables/ip6tables-legacy，确保所有调用路径都经过 wrapper
cp -f /usr/sbin/iptables.wrap /usr/sbin/iptables
cp -f /usr/sbin/iptables.wrap /usr/sbin/iptables-legacy
cp -f /usr/sbin/iptables.wrap /usr/sbin/ip6tables
cp -f /usr/sbin/iptables.wrap /usr/sbin/ip6tables-legacy
echo "[L0] iptables wrapper installed (fixes --dport without -p tcp, covers iptables+ip6tables)"

# ── stderr 捕获（在所有 wrapper 的 exec 层面记录，不破坏 argv[0]）──
echo "[L0] stderr capture log initialized" > /tmp/iptables_stderr.log
echo "[L0] uuplugin stderr log initialized" > /tmp/uuplugin_stderr.log

# ── nftables 表（加速规则容器） ──
for family in ip ip6; do
    for table in XU_ACC_MAIN_mangle XU_ACC_MAIN_nat XU_ACC_MAIN_filter; do
        nft add table $family $table 2>/dev/null || true
    done
done
echo "[L0] nftables acceleration tables created"

# ── tun163 + 策略路由 ──
ip tuntap add tun163 mode tun 2>/dev/null || true
ip link set tun163 up 2>/dev/null || true
ip addr add 172.19.163.1/24 dev tun163 2>/dev/null || true
ip route flush table 163 2>/dev/null || true
ip route add default dev tun163 table 163 2>/dev/null || true
ip rule add fwmark 0x163 lookup 163 2>/dev/null || true

# Xbox 永久路由覆盖: fwmark 0x164 → table 163
ip route add default dev tun163 table 164 2>/dev/null || true
ip rule add fwmark 0x164 lookup 163 priority 100 2>/dev/null || true
echo "[L0] tun163 + policy routing ready"

# ── WAN1 dummy 接口 (uuplugin 二进制硬编码检查此接口名称) ──
ip link add name WAN1 type dummy 2>/dev/null || true
ip link set WAN1 up 2>/dev/null || true
ip addr add 192.168.100.1/24 dev WAN1 2>/dev/null || true
echo "[L0] WAN1 dummy interface created (uuplugin requirement)"

# ── 隧道接口被动监控 ──
(
    while true; do
        if ! ip link show tun163 >/dev/null 2>&1; then
            if nft list tables 2>/dev/null | grep -q "XU_ACC_DEVICE_"; then
                ip tuntap add tun163 mode tun 2>/dev/null || true
                ip link set tun163 up 2>/dev/null || true
                ip addr add 172.19.163.1/24 dev tun163 2>/dev/null || true
                ip route add default dev tun163 table 163 2>/dev/null || true
                echo "[watchdog] tun163 recreated (acceleration tables active)" >&2
            fi
        fi
        sleep 5
    done
) &
echo "[L0] tunnel watchdog started (5s, tun163 protection)"

# ═══════════════════════════════════════════════════════════════════
# 设备身份
# ═══════════════════════════════════════════════════════════════════

# ── SN 来源: UU_SN 环境变量 → br-lan MAC → 默认值 ──
if [ -n "$UU_SN" ]; then
    SN="$UU_SN"
else
    SN=$(ip addr show br-lan 2>/dev/null | grep 'link/ether' | awk '{print $2}' | head -1 | sed 's/://g')
    [ -z "$SN" ] && SN=$(ip addr show eth0 2>/dev/null | grep 'link/ether' | awk '{print $2}' | head -1 | sed 's/://g')
    [ -z "$SN" ] && SN="55347901036946359222"
fi

# ── 工作目录 + factoryinfo ──
mkdir -p /usr/uufactory /var/tmp/uu /var/run /usr/sbin/uu
rm -f /usr/sbin/uu/.sn /usr/sbin/uu/.uuplugin_uuid /usr/sbin/uu/*.pid 2>/dev/null || true

cat > /usr/uufactory/factoryinfo << EOF
productname=NX30Pro
ethaddr=00:E0:4C:68:00:01
hardversion=VER.A
bootversion=100
manucode=${SN}
EOF

cp /usr/uufactory/factoryinfo /var/tmp/uu/h3c_info
echo "[OK] factoryinfo + h3c_info created (SN=$SN)"

# NX30Pro 真实工厂数据覆盖（修复"网络组件初始化失败"）
if [ -f /opt/uu/conf/factoryinfo.nx30pro ]; then
    cp /opt/uu/conf/factoryinfo.nx30pro /usr/uufactory/factoryinfo
    cp /opt/uu/conf/factoryinfo.nx30pro /var/tmp/uu/h3c_info
    REAL_SN=$(grep 'manucode' /opt/uu/conf/factoryinfo.nx30pro | cut -d'=' -f2)
    [ -n "$REAL_SN" ] && SN="$REAL_SN" && export UU_SN="$SN"
    echo "[OK] NX30Pro real factoryinfo applied (SN=$SN)"
fi

# ── 附加设备身份文件 ──
echo "NX30Pro" > /var/model
echo "$SN" > /usr/sbin/uu/.sn
echo "br-lan" > /var/run/landevname.txt
touch /tmp/.uu_whoami.txt
echo "[OK] /var/model, landevname.txt created"

# ═══════════════════════════════════════════════════════════════════
# 环境变量（二进制通过 getenv 读取）
# ═══════════════════════════════════════════════════════════════════
export DEVICE_TYPE=router
export UU_VENDOR=h3c
export UU_MODEL=h3c-nx30pro
export UU_PLUGIN_VESION=v14.4.20
export UU_FIRMWARE_VERSION=1.0.0
export UU_LAN_IP=192.168.0.1
export UU_LAN_NAME=br-lan
export UU_WAN_IP=0.0.0.0
export DEVICE_MAC=00:E0:4C:68:00:01
export DEVICE_IP=127.0.0.1
export DEVICE_FWMARK=0
export DEVICE_LINK_TYPE=ethernet
export TUN_IP=10.0.0.1
export TUN_NAME=tun163
export ROUTE_DEFAULT_TABLE=main
export ROUTE_FWMARK_TABLE=163
export N_PR_H=0
export HOME=/root
export TZ=CST-8
export UU_SN="$SN"
export RANDOM_UUID=default
echo "[OK] Environment vars set (UU_MODEL=h3c-nx30pro, UU_VENDOR=h3c, SN=$SN)"

# ═══════════════════════════════════════════════════════════════════
# 启动 NX30Pro aarch64 uuplugin (QEMU user-mode)
# ═══════════════════════════════════════════════════════════════════
echo ""
echo "=== Launching NX30Pro uuplugin (aarch64 → qemu-aarch64) ==="
echo "    Binary:  $UU_BIN"
echo "    Config:  $UU_CONF"
echo "    Sysroot: /arm-root"
echo ""

# QEMU 库路径（arm-root/ 包含 ld-musl + libc + libgcc_s + libstdc++ + guardian）
export QEMU_LD_PREFIX=/arm-root

# Plan A: guardian 由 uuplugin 自行 fork+exec（QEMU binfmt_misc 自动翻译）
# 确保 guardian 在 uuplugin 同目录可找到
mkdir -p /opt/uu/bin
if [ -f "$GUARDIAN_BIN" ]; then
    echo "[OK] guardian binary found: $GUARDIAN_BIN"
else
    echo "[WARN] guardian binary NOT found at $GUARDIAN_BIN"
fi

if [ "$UU_STRACE" = "1" ]; then
    echo "[strace] logging to /tmp/strace_uuplugin.log"
    strace -f -tt -y -s 256 \
        -e trace=network,ioctl,clone,fork,execve,exit,exit_group,write \
        -e signal=none \
        -o /tmp/strace_uuplugin.log \
        qemu-aarch64 "$UU_BIN" "$UU_CONF" 2>>/tmp/uuplugin_stderr.log &
else
    qemu-aarch64 "$UU_BIN" "$UU_CONF" 2>>/tmp/uuplugin_stderr.log &
fi
UUPLUGIN_PID=$!
echo "uuplugin PID=$UUPLUGIN_PID (stderr → /tmp/uuplugin_stderr.log)"

# ═══════════════════════════════════════════════════════════════════
# 进程监控 (Plan A: guardian 正交运行，监控 uuplugin 存活)
# ═══════════════════════════════════════════════════════════════════
echo ""
echo "=== Monitoring uuplugin (PID=$UUPLUGIN_PID) ==="
echo "    Guardian is managed by uuplugin (fork+exec)"
echo "    To debug: docker exec -it nx30pro-qemu sh"
echo ""

# 等待 uuplugin 退出，然后重启
STDERR_CHECK=0
while kill -0 $UUPLUGIN_PID 2>/dev/null; do
    sleep 30
    STDERR_CHECK=$((STDERR_CHECK + 1))
    # 每 5 分钟检查一次 stderr 日志是否有新内容
    if [ $STDERR_CHECK -ge 10 ]; then
        STDERR_CHECK=0
        if [ -s /tmp/uuplugin_stderr.log ]; then
            echo "[stderr] uuplugin has errors! (last 5 lines):"
            tail -5 /tmp/uuplugin_stderr.log >&2
        fi
    fi
    echo "[heartbeat] uuplugin PID=$UUPLUGIN_PID alive"
done

echo ""
echo "============================================"
echo "  uuplugin exited (exit code: $?)"
echo "  Guardian should exit automatically"
echo "  Container will restart via Docker policy"
echo "============================================"

# 退出让 Docker 重启
exit 1
