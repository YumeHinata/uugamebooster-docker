#!/bin/ash

readonly SCRIPTS_DIR="/etc/info_sync/topo_change.d"

if [ -d "$SCRIPTS_DIR" ]; then
	topo=$(ubus -S call xq_info_sync_mqtt topo_dump)
	find "$SCRIPTS_DIR" -type f -exec sh -c 'sh $1 "$2" &' _ {} "$topo" \;
fi
