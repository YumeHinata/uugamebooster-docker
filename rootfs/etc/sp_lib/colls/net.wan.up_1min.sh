#!/bin/ash

api="network.interface.wan"

if ! uci -q get network.wan.ifname|grep -qsE '[0-9]'; then
	# Wan interface not exist and wan detect not enable
	if ! uci -q get port_service.wandt.enable|grep -qsx 1; then
		exit 0
	fi
fi

if ! ubus list|grep -qsx "$api"; then
	echo 0
	exit 0
fi

if ubus call "$api" status|jsonfilter -e '$.up'|grep -sqw true; then
	echo 1
else
	echo 0
fi
