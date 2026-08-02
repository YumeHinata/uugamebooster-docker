#!/bin/ash

readonly SCRIPTS_DIR="/etc/messagingagent/unbind"

if [ -d "$SCRIPTS_DIR" ]; then
	find "$SCRIPTS_DIR" -type f -exec sh -c 'sh $1 &' _ {} \;
fi
