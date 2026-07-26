#!/bin/ash

list_plugin(){
	local _st=
	local _id=
	local _file=

	find "$1" -type f | grep -E '[^a-zA-Z]\.manifest$' | while read -r _file; do
		_st=$(grep -n "^status " "$_file" | cut -d'=' -f2 | cut -d'"' -f2)
		_id=$(grep "name" "$_file" | cut -d'=' -f2 | cut -d'"' -f2)
		if [ "$_st" = "5" ]; then
			echo "$_id"
		fi
	done
}

list_plugin /userdisk/appdata/app_infos
