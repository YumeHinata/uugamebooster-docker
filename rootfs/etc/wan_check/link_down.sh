#!/bin/ash

readonly SCRIPTS_DIR="/etc/wan_check/link_down.d"

if [ -d "$SCRIPTS_DIR" ]; then
	find "$SCRIPTS_DIR" -type f -exec sh -c 'sh $1 &' _ {} \;
fi
