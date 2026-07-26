#!/bin/sh

old_ip=""
cur_ip=""
wan_ipfile=/var/run/wan_ip

wanif=$(uci -q get network.wan.ifname)
initted=$(uci -q get xiaoqiang.common.INITTED)

LOG() {
	logger -t ip_change_check -p info "$@"
}

[ "$ACTION" != "ifup" -o "$initted" != "YES" ] && return

if [ "$INTERFACE" = "wan" -o "$INTERFACE" = "$wanif" ]; then
	[ -f "$wan_ipfile" ] && old_ip=$(cat $wan_ipfile | grep ipaddr | awk -F':' '{print $2}')
	cur_ip=$(ifconfig $wanif | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1)
	[ -z "$cur_ip" ] && return
	[ -n "$old_ip" -a "$old_ip" != "$cur_ip" ] && /usr/sbin/ip_changed.sh wan

	echo "ipaddr:$cur_ip" > $wan_ipfile
	LOG "wan ip: old=$old_ip, new=$cur_ip"
fi
