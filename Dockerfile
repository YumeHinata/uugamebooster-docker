# QEMU aarch64 — NX30Pro uuplugin 生产环境
# 直连 H3C 注册服，运行真正的 aarch64 uuplugin + guardian
#
# bin/       — aarch64 二进制: uuplugin, xuplugin-guardian, factoryinfo
# arm-root/  — aarch64 动态库: ld-musl-aarch64.so.1, libc.so, libgcc_s.so.1, libstdc++.so.6
#
# Build (from repo root):
#   docker compose up --build

FROM debian:bullseye-slim

# ── QEMU + 网络工具 + nftables/conntrack ────────────────────────────────
# nftables 从 bookworm 安装 (v1.0.6+)，bullseye 的 v0.9.8 在 kernel 6.6 上 SIGSEGV
RUN apt-get update && apt-get install -y \
        strace \
        tcpdump \
        curl \
        iptables \
        conntrack \
        bridge-utils \
        iproute2 \
        procps \
        net-tools \
        python3 \
        openssl \
    && echo "deb http://deb.debian.org/debian bookworm main" > /etc/apt/sources.list.d/bookworm.list \
    && apt-get update \
    && apt-get install -y -t bookworm nftables qemu-user \
    && rm -f /etc/apt/sources.list.d/bookworm.list \
    && apt-get update \
    && update-alternatives --set iptables /usr/sbin/iptables-legacy \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy \
    && rm -rf /var/lib/apt/lists/*

# ── TLS cert for MITM monitor (self-signed) ─────────────────────────────
RUN mkdir -p /opt/uu/certs && \
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /opt/uu/certs/mitm_key.pem \
        -out /opt/uu/certs/mitm_cert.pem \
        -days 3650 \
        -subj '/CN=uu.163.com/O=UU/OU=MITM' \
        -addext 'subjectAltName=DNS:rglg.uu.163.com,DNS:*.uu.163.com'

# ── aarch64 动态库 (QEMU_LD_PREFIX=/arm-root) ──────────────────────────
COPY arm-root/lib /arm-root/lib

# ── uuclearnat → natflushd wrapper (uuplugin fork+exec's /usr/bin/uuclearnat) ──
# On Debian, /usr/sbin is not a symlink to /usr/bin, so copy to both paths.
# The stub script checks if natflushd is already running; if not, starts it.
COPY uuclearnat /usr/bin/uuclearnat
COPY uuclearnat /usr/sbin/uuclearnat
RUN chmod +x /usr/bin/uuclearnat /usr/sbin/uuclearnat

# ── natflushd: FIFO protocol daemon ─────────────────────────────────────
COPY natflushd.sh /tmp/natflushd.sh
RUN chmod +x /tmp/natflushd.sh

# ── MITM monitor: TLS pass-through observer for uuplugin ↔ UU server ────
COPY uu_mitm_monitor.py /tmp/uu_mitm_monitor.py
RUN chmod +x /tmp/uu_mitm_monitor.py

# ── NX30Pro aarch64 二进制 ──────────────────────────────────────────────
COPY bin/uuplugin /opt/uu/bin/uuplugin
COPY bin/xuplugin-guardian /opt/uu/bin/xuplugin-guardian.real
COPY bin/factoryinfo /opt/uu/conf/factoryinfo.nx30pro
COPY conf/uu.conf /opt/uu/conf/uu.conf
COPY entry.sh /entry.sh

# ── Guardian wrapper: QEMU 翻译 aarch64 二进制 ─────────────────────────
# 内核可能无 binfmt_misc，shell wrapper 显式调用 qemu-aarch64
RUN printf '#!/bin/sh\nexec /usr/bin/qemu-aarch64 /opt/uu/bin/xuplugin-guardian.real "$@"\n' > /opt/uu/bin/xuplugin-guardian && \
    chmod +x /opt/uu/bin/xuplugin-guardian

# ── 运行时路径 ───────────────────────────────────────────────────────────
RUN mkdir -p /usr/uufactory /var/tmp/uu /tmp/uu /var/run /opt/uu/conf /opt/uu/log /var/tmp/plugmnt/uu && \
    chmod +x /opt/uu/bin/uuplugin /entry.sh

ENTRYPOINT ["/entry.sh"]
