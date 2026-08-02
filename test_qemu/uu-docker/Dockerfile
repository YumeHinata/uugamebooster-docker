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

# OpenWrt Runtime
COPY rootfs /arm-root

# 启动脚本
COPY start.sh /start.sh

RUN chmod +x /start.sh && \
    chmod +x /arm-root/uuplugin && \
    chmod +x /arm-root/xuplugin-guardian

WORKDIR /arm-root

ENTRYPOINT ["/start.sh"]