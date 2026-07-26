FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
        qemu-user-static \
        bridge-utils \
        iproute2 \
        iptables \
        ipset \
        nftables \
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
               zcat dd df sync true false mktemp watch; do \
        ln -sf busybox "$cmd"; \
    done && \
    # ── 2. 创建运行时目录和 sbin 工具链接 ──
    mkdir -p /arm-root/var/tmp/uu /arm-root/tmp/uu /arm-root/sbin /arm-root/usr/sbin && \
    cd /arm-root/sbin && \
    for cmd in ifconfig insmod route; do \
        ln -sf ../bin/busybox "$cmd"; \
    done && \
    # ── 3. 创建宿主机网络工具 wrapper（ARM 进程通过 QEMU 执行宿主机 x86 工具） ──
    printf '#!/bin/sh\nexec /usr/sbin/iptables-legacy "$@"\n' > /arm-root/usr/sbin/iptables && \
    printf '#!/bin/sh\nexec /usr/sbin/ip6tables-legacy "$@"\n' > /arm-root/usr/sbin/ip6tables && \
    printf '#!/bin/sh\nexec /sbin/ip "$@"\n' > /arm-root/sbin/ip && \
    printf '#!/bin/sh\nexec /usr/sbin/ipset "$@"\n' > /arm-root/usr/sbin/ipset && \
    printf '#!/bin/sh\nexec /usr/sbin/nft "$@"\n' > /arm-root/usr/sbin/nft && \
    chmod +x /arm-root/usr/sbin/iptables /arm-root/usr/sbin/ip6tables \
             /arm-root/sbin/ip /arm-root/usr/sbin/ipset /arm-root/usr/sbin/nft && \
    # ── 4. iptables 兼容（强制指定 x86_64 扩展路径，避免 ARM 污染） ──
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
