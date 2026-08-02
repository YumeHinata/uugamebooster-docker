#!/bin/ash

get_ips() {
	local _mac=$1
	local _params=

	_params=$(printf '{"debug":true,"hw":"%s"}' "$_mac")
	ubus call trafficd hw "$_params" | \
		jsonfilter -q -e "$.ip_list.*.ip"
}

gen_json() {
	local _mac=$1

	get_ips "$_mac" | \
		while read -r _ip; do
			printf '{"mac":"%s","ip":"%s","eventID":0,"payload":""}' "$_mac" "$_ip"
		done
}

if [ "$EVENT" != "0" ]; then
	exit 0
fi

if [ "0" = "$(uci -q get misc.features.ma_push_support)" ]; then
	exit 0
fi

res=$(gen_json "$MAC")

if [ "$res" != "" ]; then
	json=$(echo "$res"|jsonfilter -a -e "$")
	/usr/bin/matool --method reportEvents --params "$json"
fi
