#!/bin/sh
#logger -p notice -t "hotplug.d" "30-eth_iface_up.sh: run because of $INTERFACE $ACTION"

[ "$ACTION" = "ifup" ] && {
	NetMode=$(uci -q get xiaoqiang.common.NETMODE)
	if [ "$NetMode" == "whc_re" ]; then
		echo "eth_iface up,do topo changed check" >/dev/console
		ubus call topomon eth_up
	fi
}

[ "$ACTION" = "ifdown" ] && {
	NetMode=$(uci -q get xiaoqiang.common.NETMODE)
	if [ "$NetMode" == "whc_re" ]; then
		echo "eth_iface down,do topo changed check" >/dev/console
		ubus call topomon eth_down
	fi
}
