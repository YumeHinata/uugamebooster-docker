#!/bin/sh
# Minimal start — 参照 test_qemu/uu-docker/start.sh，QEMU 版只有 exec ./uuplugin
# 去掉 QEMU 专用的 QEMU_LD_PREFIX / LD_LIBRARY_PATH / qemu-aarch64-static

# ── 网络（Docker 里没有 br‑lan，需要自己建） ──
ip link add br-lan type bridge 2>/dev/null || true
ip link set br-lan up 2>/dev/null || true

mkdir -p /dev/net
[ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200

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
