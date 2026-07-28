FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive
# PATH 中优先搜索 ARM rootfs 的 wrapper 路径（宿主 shell 执行时需要）
ENV PATH=/arm-root/usr/sbin:/arm-root/sbin:/usr/sbin:/usr/bin:/sbin:/bin

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
COPY uuclearnat.sh /usr/bin/uuclearnat

RUN chmod +x /start.sh /arm-root/uuplugin /arm-root/xuplugin-guardian /usr/bin/uuclearnat && \
    # ── 1. 修复动态链接器（用实际副本+执行权限，避免 symlink/权限问题） ──
    chmod +x /arm-root/lib/libc.so && \
    rm -f /arm-root/lib/ld-musl-aarch64.so.1 && \
    cp /arm-root/lib/libc.so /arm-root/lib/ld-musl-aarch64.so.1 && \
    chmod +x /arm-root/lib/ld-musl-aarch64.so.1 && \
    # ── 2. xuplugin-guardian → wrapper 脚本（QEMU 5.2 不拦截子进程 execve） ──
    mv /arm-root/xuplugin-guardian /arm-root/xuplugin-guardian.real && \
    printf '#!/bin/sh\nexec setpriv --reuid=nobody --regid=nogroup --clear-groups /usr/bin/qemu-aarch64-static -L /arm-root /arm-root/xuplugin-guardian.real "$@"\n' > /arm-root/xuplugin-guardian && \
    chmod +x /arm-root/xuplugin-guardian && \
    cd /arm-root/bin && \
    # ── 3. busybox 符号链接（不含 sh，sh 用宿主 shell） ──
    for cmd in cat tar mv rm grep mkdir echo sleep ps kill ls pwd date \
               ln cp chmod touch uname gzip gunzip sed head ping netstat \
               zcat dd df sync true false mktemp watch; do \
        ln -sf busybox "$cmd"; \
    done && \
    # busybox 本身必须有 +x（PIE ELF，QEMU 需要执行权限） ──
    chmod +x busybox && \
    # ── 4. /bin/sh → 宿主 shell（所有 system() 调用依赖此链路） ──
    rm -f /arm-root/bin/sh && \
    ln -sf /bin/sh /arm-root/bin/sh && \
    # ── 5. 创建运行时目录和 sbin 工具链接 ──
    mkdir -p /arm-root/var/tmp/uu /arm-root/tmp/uu /arm-root/sbin /arm-root/usr/sbin && \
    chmod 777 /arm-root/var/tmp/uu /arm-root/tmp/uu && \
    cd /arm-root/sbin && \
    for cmd in ifconfig insmod route; do \
        ln -sf ../bin/busybox "$cmd"; \
    done && \
    # ── 6. 创建宿主机网络工具 wrapper ──
    printf '#!/bin/sh\nexec /usr/sbin/iptables-legacy "$@"\n' > /arm-root/usr/sbin/iptables && \
    printf '#!/bin/sh\nexec /usr/sbin/ip6tables-legacy "$@"\n' > /arm-root/usr/sbin/ip6tables && \
    printf '#!/bin/sh\nexec /sbin/ip "$@"\n' > /arm-root/sbin/ip && \
    printf '#!/bin/sh\nexec /usr/sbin/ipset "$@"\n' > /arm-root/usr/sbin/ipset && \
    printf '#!/bin/sh\nexec /usr/sbin/nft "$@"\n' > /arm-root/usr/sbin/nft && \
    chmod +x /arm-root/usr/sbin/iptables /arm-root/usr/sbin/ip6tables \
             /arm-root/sbin/ip /arm-root/usr/sbin/ipset /arm-root/usr/sbin/nft && \
    # ── 7. iptables 兼容（强制指定 x86_64 扩展路径，避免 ARM 污染） ──
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
    # ── 8. uuplugin 期望 XTABLES_LIBDIR=/lib，创建符号链接 ──
    mkdir -p /lib && \
    ln -sf /usr/lib/x86_64-linux-gnu/xtables /lib/xtables && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

WORKDIR /arm-root
ENTRYPOINT ["/start.sh"]
