#!/bin/ash

get_clis() {
	local _ifname=
	local _band=

	for _band in 2G 5G 5GH; do
		_ifname=$(uci get "misc.wireless.ifname_${_band}")
		if [ -z "$_ifname" ]; then
			continue
		fi

		iwinfo "$_ifname" a 2>/dev/null|sed '1,7d'|awk '{print $2}'
	done

	# Add default value to avoid nothing to show
	echo 'n ac ax'|grep -oE '[^ ]+'
}

get_clis \
	|sort \
	|uniq -c \
	|awk '{printf "%s:%d\n", $2, $1 - 1}'
