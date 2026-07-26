#!/bin/ash

. /usr/share/libubox/jshn.sh

# Load libs
for file in "/etc/miio_spec"/lib_*; do
	. "${file}"
done

gDid=$(get_miot_did.sh)

is_ignore() {
	local siid="$1"
	local did="$2"
	local ignore=

	ignore=$(uci -q get "miio_spec.$siid.ignore")

	# Ignore whether to ignore the request
	if [ "$gDid" != "$did" ] || [ "$ignore" = "1" ]; then
		return 0
	fi

	return 1
}

get_properties() {
	local params="$1"

	json_init
	json_add_array "result"

	IFS=$'\n'
	for param in $(echo "$params" | jsonfilter -e '@.*'); do
		local map piid siid did value code ignore
		piid=$(echo "$param" | jsonfilter -e '@.piid')
		siid=$(echo "$param" | jsonfilter -e '@.siid')
		did=$(echo "$param" | jsonfilter -e '@.did')
		map=$(uci -q get "miio_spec.$siid.$piid")
		ignore=$(uci -q get "miio_spec.$siid.ignore")

		# Ignore whether to ignore the request
		# TODO: fix request that combines multiple did, maybe should not happen
		is_ignore "$siid" "$did" && exit 5;

		if [ -n "$map" ]; then
			code=0
			if type "get_${siid}_${piid}" >/dev/null 2>&1; then
				value=$("get_${siid}_${piid}")
			else
				value=$(uci -q get "$map")
			fi
			type=$(uci -q get "miio_spec.${siid}_${piid}.type")
		else
			code=-4001
		fi

		json_add_object
		json_add_int piid "$piid"
		json_add_int siid "$siid"
		json_add_string "did" "$did"
		[ "$code" -eq 0 ] && "json_add_$type" "value" "$value"
		json_add_int code "$code"
		json_close_object
	done

	json_close_array

	# output to stdout
	json_dump
	json_cleanup
}

set_properties() {
	local params="$1"

	json_init
	json_add_array "result"

	IFS=$'\n'
	for param in $(echo "$params" | jsonfilter -e '@.*'); do
		local map piid siid did val value code ignore
		piid=$(echo "$param" | jsonfilter -e '@.piid')
		siid=$(echo "$param" | jsonfilter -e '@.siid')
		did=$(echo "$param" | jsonfilter -e '@.did')
		val=$(echo "$param" | jsonfilter -e '@.value')
		map=$(uci -q get "miio_spec.$siid.$piid")
		ignore=$(uci -q get "miio_spec.$siid.ignore")

		# Ignore whether to ignore the request
		# TODO: fix request that combines multiple did, maybe should not happen
		is_ignore "$siid" "$did" && exit 5;

		if [ -n "$map" ]; then
			code=0
			if type "set_${siid}_${piid}" >/dev/null 2>&1; then
				"set_${siid}_${piid}" "$val"
			else
				uci -q set "$map=$val"
			fi
			type=$(uci -q get "miio_spec.${siid}_${piid}.type")
		else
			code=-4001
		fi

		json_add_object
		json_add_int piid "$piid"
		json_add_int siid "$siid"
		json_add_string "did" "$did"
		[ "$code" -eq 0 ] && "json_add_$type" "value" "$value"
		json_add_int code "$code"
		json_close_object
	done

	json_close_array

	# output to stdout
	json_dump
	json_cleanup
}

action() {
	local param="$1"
	siid=$(echo "$param" | jsonfilter -e '@.siid')
	did=$(echo "$param" | jsonfilter -e '@.did')
	ignore=$(uci -q get "miio_spec.$siid.ignore")

	# Ignore whether to ignore the request
	is_ignore "$siid" "$did" && return;

	json_init
	json_add_object "result"
	json_add_int "code" 0
	json_close_object

	# output to stdout
	json_dump
	json_cleanup
}

properties_changed() {
	local param="$1"
	local siid piid value did type ignore
	siid=$(echo "$param" | cut -d: -f1)
	piid=$(echo "$param" | cut -d: -f2)
	value=$(echo "$param" | cut -d: -f3-)
	did=$(get_miot_did.sh)

	type=$(uci -q get "miio_spec.${siid}_${piid}.type")
	ignore=$(uci -q get "miio_spec.$siid.ignore")
	map=$(uci -q get "miio_spec.$siid.$piid")

	# Ignore whether to ignore the request
	is_ignore "$siid" "$did" && return;
	[ -z "$map" ] && return;

	json_init
	json_add_string "method" "properties_changed"
	json_add_array "params"
	json_add_object
	json_add_int "siid" "$siid"
	json_add_int "piid" "$piid"
	json_add_string "did" "$did"
	"json_add_$type" "value" "$value"
	json_close_object
	json_close_array

	# output to stdout
	json_dump
	json_cleanup
}
