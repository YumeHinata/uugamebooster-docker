#!/bin/ash

if [ ! -n "$(uci -q get misc.ipaccount)" ]; then
	uci set misc.ipaccount=misc
	uci add_list misc.ipaccount.if_matching='sta'
	uci commit misc
fi
