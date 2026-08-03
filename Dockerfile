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
        net-tools \
        ca-certificates \
        curl \
        strace \
        kmod \
        gdb && \
    rm -rf /var/lib/apt/lists/*

COPY conf/uu.conf          /opt/uu/conf/uu.conf
COPY bin/uuplugin           /opt/uu/bin/uuplugin
COPY bin/xuplugin-guardian  /opt/uu/bin/xuplugin-guardian
COPY scripts/start.sh       /opt/uu/scripts/start.sh
COPY scripts/uuclearnat.sh  /opt/uu/scripts/uuclearnat.sh

RUN chmod +x \
        /opt/uu/bin/uuplugin \
        /opt/uu/bin/xuplugin-guardian \
        /opt/uu/scripts/start.sh \
        /opt/uu/scripts/uuclearnat.sh && \
    ln -sf /opt/uu/scripts/uuclearnat.sh /bin/uuclearnat && \
    ln -sf /opt/uu/scripts/uuclearnat.sh /usr/bin/uuclearnat && \
    ln -sf /opt/uu/bin/xuplugin-guardian /opt/uu/xuplugin-guardian && \
    mkdir -p /lib && \
    ln -sf /usr/lib/x86_64-linux-gnu/xtables /lib/xtables && \
    for f in /usr/lib/x86_64-linux-gnu/xtables/libxt_*.so; do \
        bn=$(basename "$f"); \
        ln -sf "xtables/$bn" "/lib/$bn"; \
    done && \
    mkdir -p /usr/sbin/uu /var/tmp/uu /tmp/uu && \
    ln -sf /usr/sbin/xtables-nft-multi /opt/uu/bin/xtables-nft-multi && \
    mkdir -p /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/certs && \
    ln -sf /etc/ssl/certs/ca-certificates.crt /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/cert.pem && \
    touch /etc/dnsmasq.conf && \
    touch /tmp/nmp_client_list && \
    mkdir -p /etc/config && touch /etc/config/dhcpd.leases && \
    mkdir -p /var/lib/misc /tmp/var/lib/misc && \
    touch /var/lib/misc/dnsmasq.leases /tmp/var/lib/misc/dnsmasq.leases && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

WORKDIR /opt/uu
ENTRYPOINT ["/opt/uu/scripts/start.sh"]
