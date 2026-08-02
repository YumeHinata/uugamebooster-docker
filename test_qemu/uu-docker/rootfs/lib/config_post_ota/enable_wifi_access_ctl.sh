#!/bin/ash

if [ "$(uci -q get misc.features.supportWifiAccessCtl)" != "1" ]; then
	uci set misc.features.supportWifiAccessCtl='1'
	uci commit misc
fi