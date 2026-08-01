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

# ── Binary patches: model identity + from_file fix ──────────────────────
# Patch group 1: model strings (hardcoded in binary)
#   "openwrt" at 0x3E64DB → "h3cnx30" (7 bytes)
#   "OpenWrt" at 0x3EA86F → "NX30Pro" (7 bytes)
#   "openwrt-x86_64\0" at 0x3E6D5F → "h3c-nx30pro\0\0\0" (12+2 nulls)
#
# Patch group 2: ALL UU_* env var names → XX_* (same-length, preserves null)
#   Binary checks ANY UU_* env var existence → from_file=0 if found.
#   Renaming all 8 strings prevents any getenv("UU_*") from matching.
#   Offsets verified by hex dump of .rodata string table.
#   NOTE: if network features break, restore UU_LAN_IP/UU_WAN_IP/UU_LAN_NAME.
RUN printf 'h3cnx30' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4089051 conv=notrunc && \
    printf 'NX30Pro' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4106351 conv=notrunc && \
    printf 'h3c-nx30pro' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091231 conv=notrunc && \
    dd if=/dev/zero of=/opt/uu/bin/uuplugin bs=1 count=2 seek=4091243 conv=notrunc && \
    printf 'XX_VENDOR' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091607 conv=notrunc && \
    printf 'XX_MODEL' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091617 conv=notrunc && \
    printf 'XX_SN' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091626 conv=notrunc && \
    printf 'XX_PLUGIN_VESION' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091632 conv=notrunc && \
    printf 'XX_FIRMWARE_VERSION' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091649 conv=notrunc && \
    printf 'XX_LAN_NAME' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091669 conv=notrunc && \
    printf 'XX_LAN_IP' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091681 conv=notrunc && \
    printf 'XX_WAN_IP' | dd of=/opt/uu/bin/uuplugin bs=1 seek=4091691 conv=notrunc && \
    echo "[OK] uuplugin patched: all UU_*→XX_*, model→h3c-nx30pro"

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
