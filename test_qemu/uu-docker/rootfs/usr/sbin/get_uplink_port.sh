#!/bin/sh

gateway=$(uci -q get network.lan.gateway)
[ -z "$gateway" ] && exit 1

gw_mac=$(cat /proc/net/arp | grep -w "$gateway" | grep br-lan | awk '{print $4}')
[ -z "$gw_mac" ] && exit 1

brctl showmacs br-lan | grep "$gw_mac" | awk '{print $1}'