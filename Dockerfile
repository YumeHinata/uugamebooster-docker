FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
        qemu-user-static \
        bridge-utils \
        iproute2 \
        iptables \
        procps \
        net-tools \
        tcpdump \
        strace \
        curl \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# ARM rootfs（精简版：仅含 uuplugin 运行所需的最小依赖集）
COPY rootfs /arm-root
COPY start.sh /start.sh

RUN chmod +x /start.sh /arm-root/uuplugin /arm-root/xuplugin-guardian && \
    # ── 1. 修复符号链接（Windows 构建会丢失 symlink） ──
    ln -sf libc.so /arm-root/lib/ld-musl-aarch64.so.1 && \
    cd /arm-root/bin && \
    for cmd in sh cat tar mv rm grep mkdir echo sleep ps kill ls pwd date \
               ln cp chmod touch uname gzip gunzip sed head ping netstat \
               zcat dd df sync true false mktemp watch ip; do \
        ln -sf busybox "$cmd"; \
    done && \
    # ── 2. 创建运行时目录和 sbin 工具链接 ──
    mkdir -p /arm-root/var/tmp/uu /arm-root/tmp/uu /arm-root/sbin && \
    cd /arm-root/sbin && \
    for cmd in ifconfig insmod route; do \
        ln -sf ../bin/busybox "$cmd"; \
    done && \
    # ── 3. iptables 兼容（ARM 进程调用 iptables 时回退到宿主机） ──
    XTD=$(dirname $(find /usr/lib -name "libxt_tcp.so" | head -1)) && \
    mv /usr/sbin/iptables-legacy /usr/sbin/iptables-legacy.real && \
    mv /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables-legacy.real && \
    mkdir -p /usr/libexec/iptables && \
    ln -sf /usr/sbin/iptables-legacy.real /usr/libexec/iptables/iptables-legacy && \
    ln -sf /usr/sbin/iptables-legacy.real /usr/libexec/iptables/iptables-legacy-save && \
    ln -sf /usr/sbin/iptables-legacy.real /usr/libexec/iptables/iptables-legacy-restore && \
    ln -sf /usr/sbin/ip6tables-legacy.real /usr/libexec/iptables/ip6tables-legacy && \
    ln -sf /usr/sbin/ip6tables-legacy.real /usr/libexec/iptables/ip6tables-legacy-save && \
    ln -sf /usr/sbin/ip6tables-legacy.real /usr/libexec/iptables/ip6tables-legacy-restore && \
    printf '#!/bin/sh\nexport XTABLES_LIBDIR=%s\nexec /usr/libexec/iptables/iptables-legacy "$@"\n' "$XTD" > /usr/sbin/iptables-legacy && \
    printf '#!/bin/sh\nexport XTABLES_LIBDIR=%s\nexec /usr/libexec/iptables/ip6tables-legacy "$@"\n' "$XTD" > /usr/sbin/ip6tables-legacy && \
    chmod +x /usr/sbin/iptables-legacy /usr/sbin/ip6tables-legacy && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

WORKDIR /arm-root
ENTRYPOINT ["/start.sh"]
