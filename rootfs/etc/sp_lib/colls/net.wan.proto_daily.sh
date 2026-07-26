#!/bin/ash

if uci -q get network.wan.ifname|grep -qsE '[0-9]'; then
	uci get network.wan.proto
fi
