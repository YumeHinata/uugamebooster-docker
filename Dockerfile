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
        kmod && \
    rm -rf /var/lib/apt/lists/*

# ── Application files ──────────────────────────────────────────────────────
COPY conf/uu.conf          /opt/uu/conf/uu.conf
COPY bin/uuplugin           /opt/uu/bin/uuplugin
COPY bin/xuplugin-guardian  /opt/uu/bin/xuplugin-guardian
COPY scripts/start.sh       /opt/uu/scripts/start.sh
COPY scripts/uuclearnat.sh  /opt/uu/scripts/uuclearnat.sh

# ── Binary patch: replace hardcoded "openwrt" model strings ────────────────
# Generic x86_64 uuplugin hardcodes "openwrt"/"OpenWrt" in login protobuf,
# ignoring UU_MODEL env var. Patch to H3C NX30Pro identity (same byte length).
RUN printf 'h3cnx30' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4089051 conv=notrunc && \
    printf 'NX30Pro' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4106351 conv=notrunc && \
    printf 'h3cnx30-aarch64' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091231 conv=notrunc && \
    echo "[OK] uuplugin patched: openwrt → h3cnx30, OpenWrt → NX30Pro, x86_64 → aarch64"

# ── Binary patch: rename UU_SN → XX_SN to break from_file=0 logic ──────────
# Binary calls getenv("UU_SN") via helper; if env exists → from_file=0 (non-genuine).
# Renaming to XX_SN forces the helper to return NULL → falls through to file path
# → from_file=1. Keep UU_SN="" in start.sh to prevent segfault on other code paths.
RUN printf 'XX_SN' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4095722 conv=notrunc && \
    echo "[OK] uuplugin patched: UU_SN → XX_SN (force from_file=1 via file path)"

# ── One-time setup ─────────────────────────────────────────────────────────
RUN chmod +x \
        /opt/uu/bin/uuplugin \
        /opt/uu/bin/xuplugin-guardian \
        /opt/uu/scripts/start.sh \
        /opt/uu/scripts/uuclearnat.sh && \
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
    # iptables legacy mode (Debian default is nft, but xtables modules need legacy)
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

WORKDIR /opt/uu
ENTRYPOINT ["/opt/uu/scripts/start.sh"]
