#!/bin/sh
#logger -p notice -t "hotplug.d" "90-wan_chech.sh: run because of $INTERFACE $ACTION"

wanif=$(uci -q get network.wan.ifname)
if [ "$INTERFACE" = "wan" ] || [ "$INTERFACE" = "$wanif" ]; then
	if [ "$ACTION" = "ifdown" ] || [ "$ACTION" = "ifup" ]; then
		/usr/sbin/wan_check.sh reset &
	fi
fi
