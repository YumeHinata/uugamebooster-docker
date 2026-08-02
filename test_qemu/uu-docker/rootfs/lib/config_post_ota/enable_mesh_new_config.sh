#!/bin/ash

if [ "$(uci -q get misc.features.supportMeshNewConfig)" != "1" ]; then
	uci set misc.features.supportMeshNewConfig='1'
	uci commit misc
fi