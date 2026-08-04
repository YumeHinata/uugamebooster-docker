FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && \
    apt-get install -y \
        iproute2 \
        iptables \
        ipset \
        nftables \
        procps \
        kmod \
        ca-certificates \
        curl \
        gdb && \
    rm -rf /var/lib/apt/lists/* && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true

# ── copy binaries ──────────────────────────────────────────────────────────
COPY bin/uuplugin           /opt/uu/bin/uuplugin
COPY bin/xuplugin-guardian  /opt/uu/bin/xuplugin-guardian
COPY conf/uu.conf           /opt/uu/conf/uu.conf
COPY scripts/start.sh       /opt/uu/scripts/start.sh
COPY scripts/uuclearnat.sh  /bin/uuclearnat

RUN chmod +x \
        /opt/uu/bin/uuplugin \
        /opt/uu/bin/xuplugin-guardian \
        /opt/uu/scripts/start.sh \
        /bin/uuclearnat && \
    mkdir -p /tmp/uu /var/run

WORKDIR /opt/uu
ENTRYPOINT ["/opt/uu/scripts/start.sh"]
