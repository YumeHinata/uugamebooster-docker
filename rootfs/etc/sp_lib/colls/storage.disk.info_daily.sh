#!/bin/ash

. /lib/functions.sh

STORAGE_CONFIG_PATH="/tmp/etc/storage"

storage_list_partition(){
	local size type
	config_get size $1 size 0
	config_get type $1 type unknown

	size=$(awk 'BEGIN{printf "%.2f\n",'$size/2/1024/1024'}')

	echo "$1:$type:$size"
}

storage_list_device(){
	config_list_foreach $1 partition storage_list_partition
}

storage_info(){
	config_foreach storage_list_device device
}

if [ -f "${STORAGE_CONFIG_PATH}" ]; then
	config_load "${STORAGE_CONFIG_PATH}"
	storage_info
fi
