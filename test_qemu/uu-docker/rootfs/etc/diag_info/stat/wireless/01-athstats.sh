#!/bin/ash

wl_if_count=$(uci -q get misc.wireless.wl_if_count)
[ -z "$wl_if_count" ] && wl_if_count=2

wl_if_count=$(expr $wl_if_count - 1)

for i in $(seq 0 $wl_if_count); do
	echo "========== wifi$i"
	athstats -i "wifi$i"
done
