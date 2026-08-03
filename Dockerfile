FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

# ── Runtime dependencies (x86_64 native, no QEMU) ──────────────────────────
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
        python3 && \
    rm -rf /var/lib/apt/lists/*

# ── Application files ──────────────────────────────────────────────────────
COPY conf/uu.conf          /opt/uu/conf/uu.conf
COPY bin/uuplugin           /opt/uu/bin/uuplugin
COPY bin/xuplugin-guardian  /opt/uu/bin/xuplugin-guardian
COPY scripts/start.sh       /opt/uu/scripts/start.sh
COPY scripts/uuclearnat.sh  /opt/uu/scripts/uuclearnat.sh
COPY tools/uu_mgmt_proxy.py /opt/uu/scripts/uu_mgmt_proxy.py

# ── Binary patches: model identity only ────────────────────────────────
#   "openwrt" at 0x3E64DB → "h3c_" + 3 nulls (matches NX30Pro's "h3c_")
#   "OpenWrt" at 0x3EA86F → "NX30Pro" (7 bytes)
#   "openwrt-x86_64\0" at 0x3E6D5F → "h3c-nx30pro\0\0\0" (12+2 nulls)
# NOTE: UU_* → XX_* patches REMOVED — x86 binary NEEDS getenv("UU_*").
# Missing H3C fields are injected by MITM (uu_mitm_mod.py) at transit.
RUN printf 'h3c_' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4089051 conv=notrunc && \
    dd if=/dev/zero of=/opt/uu/bin/uuplugin bs=1 count=3 seek=4089055 conv=notrunc && \
    printf 'NX30Pro' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4106351 conv=notrunc && \
    printf 'h3c-nx30pro' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091231 conv=notrunc && \
    dd if=/dev/zero of=/opt/uu/bin/uuplugin bs=1 count=2 seek=4091243 conv=notrunc && \
    echo "[OK] uuplugin patched: model→h3c_+h3c-nx30pro"

# ── One-time setup ─────────────────────────────────────────────────────────
RUN chmod +x \
        /opt/uu/bin/uuplugin \
        /opt/uu/bin/xuplugin-guardian \
        /opt/uu/scripts/start.sh \
        /opt/uu/scripts/uuclearnat.sh \
        /opt/uu/scripts/uu_mgmt_proxy.py && \
    # uuplugin hardcodes /bin/uuclearnat (OpenWrt path)
    ln -sf /opt/uu/scripts/uuclearnat.sh /bin/uuclearnat && \
    ln -sf /opt/uu/scripts/uuclearnat.sh /usr/bin/uuclearnat && \
    # uuplugin spawns ./xuplugin-guardian (CWD relative); WORKDIR=/opt/uu
    ln -sf /opt/uu/bin/xuplugin-guardian /opt/uu/xuplugin-guardian && \
    # xtables compat: uuplugin uses XTABLES_LIBDIR=/lib (OpenWrt convention)
    mkdir -p /lib && \
    ln -sf /usr/lib/x86_64-linux-gnu/xtables /lib/xtables && \
    for f in /usr/lib/x86_64-linux-gnu/xtables/libxt_*.so; do \
        bn=$(basename "$f"); \
        ln -sf "xtables/$bn" "/lib/$bn"; \
    done && \
    # Pre-create OpenWrt paths the binary expects at runtime
    mkdir -p /usr/sbin/uu /var/tmp/uu /tmp/uu && \
    # uuplugin calls xtables-nft-multi from its own directory
    ln -sf /usr/sbin/xtables-nft-multi /opt/uu/bin/xtables-nft-multi && \
    # OpenSSL cert paths (binary hardcodes build-machine paths for tunnel TLS)
    mkdir -p /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/certs && \
    ln -sf /etc/ssl/certs/ca-certificates.crt /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/cert.pem && \
    # OpenWrt paths the binary may read (dhcp/dnsmasq) — touch empty to avoid ENOENT
    touch /etc/dnsmasq.conf && \
    touch /tmp/nmp_client_list && \
    mkdir -p /etc/config && touch /etc/config/dhcpd.leases && \
    mkdir -p /var/lib/misc /tmp/var/lib/misc && \
    touch /var/lib/misc/dnsmasq.leases /tmp/var/lib/misc/dnsmasq.leases && \
    # iptables legacy mode (Debian default is nft, but xtables modules need legacy)
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

WORKDIR /opt/uu
ENTRYPOINT ["/opt/uu/scripts/start.sh"]
