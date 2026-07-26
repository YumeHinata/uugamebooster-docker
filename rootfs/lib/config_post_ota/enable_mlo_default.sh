#!/bin/ash

if [ "$(uci -q get misc.features.mlo_support)" = "0" ]; then
	uci set misc.features.mlo_support='1'
	uci set misc.hardware.displayName='Xiaomi路由器BE6500 Pro'
	uci commit misc

	if [ "$(uci -q get wireless.@wifi-iface[0].bsd)" = "1" ]; then
		if [ "$(uci -q get wireless.wifi0.ax)" = "1" ]; then
			uci set wireless.@wifi-iface[0].mld='hostap_mld0'
			uci set wireless.@wifi-iface[1].mld='hostap_mld0'
			uci set wireless.hostap_mld0.mlo_enable='1'
			uci commit wireless
		fi
	fi
fi
