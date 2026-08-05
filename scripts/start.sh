#!/bin/sh
# Minimal start — 参照 test_qemu/uu-docker/start.sh
# L2: DNS 劫持 + 本地 MITM 注入 H3C NX30Pro 身份

# ── SN: 从 br-lan MAC 生成（与 monitor.sh 一致） ──
SN=$(ip addr show br-lan 2>/dev/null | grep 'link/ether' | awk '{print $2}' | head -1)
[ -z "$SN" ] && SN=$(ip addr show eth0 2>/dev/null | grep 'link/ether' | awk '{print $2}' | head -1)
[ -n "$SN" ] && echo "$SN" > /tmp/uu/.sn

# ── DNS 劫持 + iptables DNAT: rglg.uu.163.com / UU 服务器 → 本地 MITM ──
printf '\n127.0.0.1 rglg.uu.163.com\n' >> /etc/hosts
# 二进制硬编码 IP 直连，hosts 不够，用 iptables DNAT
# MITM 用 socket mark=1 排除自己流量，避免循环
iptables -t nat -A OUTPUT -p tcp --dport 16000 -m mark ! --mark 0x1 -j DNAT --to-destination 127.0.0.1:16000 2>/dev/null || true

# ── 网络（Docker 里没有 br‑lan，需要自己建） ──
ip link add br-lan type bridge 2>/dev/null || true
ip link set br-lan up 2>/dev/null || true

mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200

# ── 启动本地 MITM（后台，劫持 TLS 注册消息注入 H3C 身份） ──
python3 /opt/uu/bin/uu_mitm.py > /tmp/uu_mitm.log 2>&1 &
MITM_PID=$!
for i in $(seq 1 20); do
    ss -tln 2>/dev/null | grep -q '127.0.0.1:16000' && break
    kill -0 "$MITM_PID" 2>/dev/null || { echo 'MITM 启动失败'; cat /tmp/uu_mitm.log; exit 1; }
    sleep 0.3
done

# ── 运行目录 ──
RUNDIR="/tmp/uu"
mkdir -p "$RUNDIR"
cp /opt/uu/bin/uuplugin          "$RUNDIR/"
cp /opt/uu/bin/xuplugin-guardian "$RUNDIR/"
cp /opt/uu/bin/xtables-nft-multi "$RUNDIR/"
cp /opt/uu/conf/uu.conf          "$RUNDIR/"
chmod +x "$RUNDIR/uuplugin" "$RUNDIR/xuplugin-guardian"

cd "$RUNDIR"

# Debian glibc → musl 兼容（OpenWrt 上不需要）
ulimit -n 1024 2>/dev/null || true

exec ./uuplugin
