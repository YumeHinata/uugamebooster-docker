#!/bin/sh

if uci -q get network.wan_2.ifname | grep -qsE '[0-9]'; then
	uci -q get network.wan_2.proto
fi
