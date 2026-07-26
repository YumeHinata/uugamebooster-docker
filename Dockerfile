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

# ARM rootfs（小米路由器固件 + UU 加速器）
COPY rootfs /arm-root
COPY start.sh /start.sh

RUN chmod +x /start.sh /arm-root/uuplugin /arm-root/xuplugin-guardian && \
    # ── 1. 修复符号链接（Windows 构建会丢失 symlink） ──
    ln -sf libc.so /arm-root/lib/ld-musl-aarch64.so.1 && \
    ln -sf busybox /arm-root/bin/sh && \
    cd /arm-root/lib && \
    for f in *.so.*.*; do \
        [ -f "$f" ] || continue; \
        s=$(echo "$f" | sed 's/\(.so\.[0-9]*\).*/\1/'); \
        [ "$s" != "$f" ] && [ ! -e "$s" ] && ln -sf "$f" "$s"; \
    done || true && \
    cd /arm-root/usr/lib && \
    for f in *.so.*.*; do \
        [ -f "$f" ] || continue; \
        s=$(echo "$f" | sed 's/\(.so\.[0-9]*\).*/\1/'); \
        [ "$s" != "$f" ] && [ ! -e "$s" ] && ln -sf "$f" "$s"; \
    done || true && \
    # ── 2. iptables 兼容（ARM 进程会污染 XTABLES_LIBDIR） ──
    # 将 iptables-legacy 替换为 wrapper，强制指定 x86_64 扩展路径
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
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true && \
    # ── 3. 删除 ARM 版 iptables，强制回退到宿主机 wrapper ──
    rm -f /arm-root/usr/sbin/iptables* /arm-root/usr/sbin/ip6tables* \
          /arm-root/sbin/iptables /arm-root/sbin/ip6tables 2>/dev/null || true

WORKDIR /arm-root
ENTRYPOINT ["/start.sh"]
