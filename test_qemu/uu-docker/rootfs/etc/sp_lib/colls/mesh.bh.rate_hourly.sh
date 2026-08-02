#!/bin/sh

ifname=$(uci get misc.backhauls.backhaul_5g_ap_iface)

if [ -z "$ifname" ]; then
	exit 0
fi

if [ -d /etc/wireless/mediatek/ ]; then
	mtknetlink_cli "$ifname" stalist \
		|grep -oE '[TR]xRate:.*' \
		|tr 'TR' 'tr' \
		|sed 's/rate//'
else
	wlanconfig "$ifname" list \
		|grep -E '^([0-9a-f]{2}:){5}' \
		|awk '{printf "tx:%s\nrx:%s\n", $4, $5}' \
		|tr -d M
fi
