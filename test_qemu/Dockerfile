# QEMU aarch64 test environment for NX30Pro uuplugin
# Purpose: run the real NX30Pro aarch64 binary, redirect registration to MITM,
#           capture the complete Register protobuf for field comparison.
#
# Uses uu-docker rootfs (firmware-extracted aarch64 libs + guardian binary)
# instead of Alpine CDN downloads — avoids version mismatch with NX30Pro binary.
#
# Build (from repo root):
#   docker compose -f test_qemu/docker-compose.yml up --build

FROM debian:bullseye-slim

# ── QEMU + network tools (matching uu-docker deps) ────────────────────────
RUN apt-get update && apt-get install -y \
        qemu-user \
        strace \
        tcpdump \
        curl \
        iptables \
        bridge-utils \
        iproute2 \
        procps \
        net-tools \
    && update-alternatives --set iptables /usr/sbin/iptables-legacy \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy \
    && rm -rf /var/lib/apt/lists/*

# ── Firmware rootfs: provides ld-musl, libstdc++, libgcc_s, guardian ──────
# These are the exact libraries from the NX30Pro firmware, avoiding
# Alpine version mismatches that can cause symbol resolution issues.
COPY test_qemu/uu-docker/rootfs /arm-root

# ── NX30Pro aarch64 binary (v14.4.20, newer than rootfs version) ──────────
COPY bin/NX30Pro_v14.4.20/uuplugin /opt/uu/bin/uuplugin
COPY test_qemu/uu.conf /opt/uu/conf/uu.conf
COPY test_qemu/entry.sh /entry.sh

# ── Copy guardian from rootfs (binary tries to execl it) ───────────────────
RUN cp /arm-root/xuplugin-guardian /opt/uu/bin/xuplugin-guardian && \
    chmod +x /opt/uu/bin/xuplugin-guardian

# ── Runtime paths ─────────────────────────────────────────────────────────
RUN mkdir -p /usr/uufactory /var/tmp/uu /tmp/uu /var/run /opt/uu/conf /opt/uu/log && \
    chmod +x /opt/uu/bin/uuplugin /entry.sh

# ── Default MITM host (override with env var) ────────────────────────────
ENV MITM_HOST=host.docker.internal

ENTRYPOINT ["/entry.sh"]
