#!/bin/ash

# Ignore if docker section not exist
if ! uci -q get network.docker >/dev/null; then
	exit 0
fi

if ! uci -q get network.docker.bridge_empty >/dev/null; then
	uci set network.docker.bridge_empty='1'
	uci set network.docker.force_link='1'
	uci set network.docker.type='bridge'
	uci set network.docker.proto='static'
	uci set network.docker.ipaddr='172.17.0.1'
	uci set network.docker.netmask='255.255.0.0'
	uci set network.docker.auto=''
	uci set network.docker.device=''
	uci commit network.docker
fi
