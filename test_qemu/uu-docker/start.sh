#!/bin/sh

echo "=================================="
echo "UU Plugin Docker Runtime"
echo "=================================="

cd /arm-root

export LD_LIBRARY_PATH=/arm-root/lib:/arm-root/usr/lib
export QEMU_LD_PREFIX=/arm-root

exec /usr/bin/qemu-aarch64-static ./uuplugin