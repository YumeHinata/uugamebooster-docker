#!/bin/sh

wan_port=$(uci -q get misc.sw_reg.sw_wan_port)
[ -n "$wan_port" ] || exit 0

[ "$wan_port" = "$PORT_NUM" ] && {
	[ "$LINK_STATUS" = "linkup" ] || [ "$LINK_STATUS" = "linkdown" ] && {
		/usr/sbin/wan_check.sh reset &
	}
}
