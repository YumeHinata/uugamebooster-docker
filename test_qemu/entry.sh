#!/bin/sh
set -e

MITM_HOST="${MITM_HOST:-host.docker.internal}"
MITM_PORT="${MITM_PORT:-16000}"

echo "============================================"
echo "  QEMU NX30Pro uuplugin Test Environment"
echo "  MITM: ${MITM_HOST}:${MITM_PORT}"
echo "============================================"

# ── Create fake factoryinfo (matches real NX30Pro layout) ──────────────────
mkdir -p /usr/uufactory /var/tmp/uu /var/run

cat > /usr/uufactory/factoryinfo << 'EOF'
productname=NX30Pro
ethaddr=00:E0:4C:68:00:01
hardversion=VER.A
bootversion=100
manucode=55347901036946359222
EOF

cp /usr/uufactory/factoryinfo /var/tmp/uu/h3c_info
echo "[OK] factoryinfo + h3c_info created"

# ── Additional device identity files ───────────────────────────────────────
echo "NX30Pro" > /var/model
mkdir -p /usr/sbin/uu
echo "55347901036946359222" > /usr/sbin/uu/.sn
echo "br-lan" > /var/run/landevname.txt
echo "[OK] /var/model, landevname.txt created"

# ── DNS redirect: registration server → MITM ───────────────────────────────
# The binary reads /etc/hosts but also sends raw DNS to 127.0.0.11
# /etc/hosts hijack alone is NOT sufficient — we need iptables DNAT
MITM_IP=$(getent hosts ${MITM_HOST} | awk '{print $1}')
echo "${MITM_HOST} h3crglg.uu.163.com" >> /etc/hosts
echo "${MITM_HOST} rglg.uu.netease.com" >> /etc/hosts

# DNAT: any TCP → port 16000 → MITM (catches raw-DNS-resolved connections)
iptables -t nat -A OUTPUT -p tcp --dport ${MITM_PORT} -j DNAT --to-destination ${MITM_IP}:${MITM_PORT}
echo "[OK] iptables DNAT: *:${MITM_PORT} → ${MITM_IP}:${MITM_PORT}"

# ── Environment variables (binary uses getenv for ALL of these) ───────────
export DEVICE_TYPE=router
export UU_VENDOR=h3c
export UU_MODEL=h3c-nx30pro
export UU_PLUGIN_VESION=v14.4.20
export UU_FIRMWARE_VERSION=1.0.0
export UU_LAN_IP=192.168.1.1
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
export UU_SN=55347901036946359222
export RANDOM_UUID=default

echo "[OK] Environment vars set (UU_MODEL=h3c-nx30pro, UU_VENDOR=h3c)"

# ── Run NX30Pro aarch64 binary via QEMU + strace ──────────────────────────
echo ""
echo "=== Launching NX30Pro uuplugin (aarch64 → qemu-aarch64) ==="
echo "    Binary: /opt/uu/bin/uuplugin"
echo "    Config: /opt/uu/conf/uu.conf"
echo "    Sysroot: /arm-root (firmware libs + guardian)"
echo ""

# Use firmware rootfs as QEMU library prefix (matches uu-docker approach)
export QEMU_LD_PREFIX=/arm-root

strace -e trace=open,openat,read,write,connect,sendto,recvfrom \
       -o /tmp/strace.log -f -v -s 512 \
       qemu-aarch64 /opt/uu/bin/uuplugin /opt/uu/conf/uu.conf \
       2>&1 &
PID=$!

# Wait for binary to attempt registration (connect to server)
sleep 15

echo ""
echo "============================================"
echo "  STRACE OUTPUT (syscalls)"
echo "============================================"
cat /tmp/strace.log 2>/dev/null || echo "(empty)"

echo ""
echo "============================================"
echo "  CONTAINER STATUS"
echo "============================================"
echo "Binary PID: ${PID}"
echo "Strace log: /tmp/strace.log"
echo ""
echo "To debug:  docker exec -it nx30pro-qemu sh"
echo "To check:  cat /tmp/strace.log"
echo ""
echo "Keeping container alive..."
echo "============================================"

# Keep container alive for debugging
wait $PID 2>/dev/null || true
echo ""
echo "uuplugin exited. Container stays alive for inspection."
tail -f /dev/null
