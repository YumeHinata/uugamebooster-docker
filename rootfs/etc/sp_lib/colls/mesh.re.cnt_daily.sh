#!/bin/ash

if ! mesh_cmd role|grep -qsw CAP; then
	exit 0
fi

ubus call xq_info_sync_mqtt topo_dump \
	|jsonfilter -e '$.*.assoc' \
	|grep -cx 1
