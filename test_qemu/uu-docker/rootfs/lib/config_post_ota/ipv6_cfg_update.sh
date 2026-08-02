#!/bin/ash

subver=$(uci -q get ipv6.globals.subver)
[ "$subver" != "1" ] && {
    /usr/sbin/ipv6.sh cfg_v2_to_new
}
