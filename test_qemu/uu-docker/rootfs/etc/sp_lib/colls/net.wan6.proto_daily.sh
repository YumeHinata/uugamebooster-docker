#!/bin/ash

if uci -q get network.wan.ifname|grep -qsE '[0-9]'; then
    ver=$(uci -q get ipv6.globals.ver)
    if [ "$ver" = "2" ]; then
        uci -q get ipv6.wan6.mode
    else
        uci -q get ipv6.settings.mode
    fi
fi
