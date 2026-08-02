#!/bin/ash

bound=$(uci -q get miio_ot.ot.bound)

if [ "$bound" != "1" ]; then
	# Skip central start if OT not bound
	return 0
fi

central_software_pack.sh start 15 2>&1 | logger -t central
