#!/bin/ash

for band in 2G 5G 5GH; do
	ifname=$(uci get "misc.wireless.ifname_${band}")
	if [ -z "$ifname" ]; then
		continue
	fi

	count=$(iwinfo "$ifname" a 2>/dev/null|grep stacount:|awk '{print $2}')

	echo "${band/GH/G2}:${count:-0}"
done
