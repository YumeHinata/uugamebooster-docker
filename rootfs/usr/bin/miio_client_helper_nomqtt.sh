#!/bin/sh

. /usr/share/libubox/jshn.sh

readonly MIIO_RECV_LINE="/usr/bin/miio_recv_line"
readonly MIIO_SEND_LINE="/usr/bin/miio_send_line"
readonly DEBUG_FILE="/tmp/miio_debug_input"
readonly PROG_NAME="miio_helper"

# Always set to false if OTA from router server
MIIO_AUTO_OTA=false

gDebug=
gLocal=

dbg_info() {
	if [ -z "$gDebug" ]; then
		return
	fi

	logger -p user.debug -t "$PROG_NAME" "$@"
}

log_info() {
	echo "$@" >&2
	logger -p user.info -t "$PROG_NAME" "$@"
}

recv_miio_json() {
	if [ -z "$gLocal" ]; then
		$MIIO_RECV_LINE
	else
		if wc -l $DEBUG_FILE | grep -sqw ^0; then
			return 1
		fi
		sed -n 1p "$DEBUG_FILE"
		sed -i 1d "$DEBUG_FILE"
	fi
}

send_miio_json() {
	if [ -n "$gLocal" ]; then
		log_info "$@"
		return
	elif [ -n "$gDebug" ]; then
		log_info "$@"
	fi

	$MIIO_SEND_LINE "$@"
}

send_helper_ready() {
	send_miio_json '{"method":"_internal.helper_ready"}'
}

request_dinfo() {
	# del all msq queue, or cause unexpected issues
	rm -f /dev/mqueue/miio_queue*

	local did key vendor mac hw model reply

	did=$(get_miot_did.sh)
	key=$(bdata get miot_key)
	vendor="xiaomi"
	mac=$(getmac wan)
	hw=$(uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE | awk '{print tolower($0)}')
	model="xiaomi.router.$hw"
	mjac_i2c=$(uci -q get  miio_ot.ot.mjac_i2c)
	mjac_gpio=$(uci -q get  miio_ot.ot.mjac_gpio)

	json_init
	json_add_string "method" "_internal.response_dinfo"
	json_add_object "params"
	[ -n "$did" ] && json_add_int "did" "$did"
	[ -n "$key" ] && json_add_string "key" "$key"
	[ -n "$vendor" ] && json_add_string "vendor" "$vendor"
	[ -n "$mac" ] && json_add_string "mac" "$mac"
	[ -n "$model" ] && json_add_string "model" "$model"
	[ -n "$mjac_i2c" ] && json_add_string "mjac_i2c" "$mjac_i2c"
	[ -n "$mjac_gpio" ] && json_add_string "mjac_gpio" "/sys/class/gpio/gpio$mjac_gpio/value"
	json_add_array "sc_type"
	json_add_int "" 1
	json_close_array
	json_close_object

	reply=$(json_dump)
	json_cleanup

	send_miio_json "$reply"
}

request_ot_config() {
	local msg="$1"
	local ntoken
	local otoken
	local rtoken
	local env
	local reply

	ntoken=$(echo "$msg" | jsonfilter -e '@.params.ntoken')
	otoken=$(uci -q get miio_ot.ot.token)
	region=$(uci -q get miio_ot.ot.region)
	env=$(uci -q get miio_ot.dbg.env)

	if [ -n "$otoken" ]; then
		rtoken=$otoken
	else
		uci -q set miio_ot.ot.token="$ntoken"
		uci commit miio_ot
		rtoken=$ntoken
	fi

	json_init
	json_add_string "method" "_internal.res_ot_config"
	json_add_object "params"
	json_add_string "token" "$rtoken"
	if [ "$env" = "pv" ]; then
		json_add_string "country" "p1"
	elif [ "$env" != "rel" ]; then
		json_add_string "country" "$env"
	else
		# In release mode, respect the region info
		if [ -n "$region" ]; then
			json_add_string "country" "$region"
		fi
	fi
	json_close_object

	reply=$(json_dump)
	json_cleanup

	send_miio_json "$reply"
}

req_wifi_conf_status() {
	send_miio_json '{"method":"_internal.res_wifi_conf_status","params":1}'
}

update_dtoken() {
	local msg="$1"
	local update_token reply

	update_token=$(echo "$msg" | jsonfilter -e '@.params.ntoken')

	uci -q set miio_ot.ot.token="$update_token"
	uci commit miio_ot

	json_init
	json_add_string "method" "_internal.token_updated"
	json_add_strint "params" "$update_token"

	reply=$(json_dump)
	json_cleanup

	send_miio_json "$reply"
}

internal_info() {
	local sw_version bind_key partner_id reply
	local lan_ip=""
	local lan_mask=""
	local lan_gw=""

	# get lan info
	lan_ip="$(uci -q get network.lan.ipaddr)"
	lan_mask="$(uci -q get network.lan.netmask)"
	lan_gw="$(uci -q get network.lan.gateway)"

	sw_version=$(uci -q get /usr/share/xiaoqiang/xiaoqiang_version.version.ROM)
	bind_key=$(uci -q get miio_ot.ot.bind_key)
	partner_id=$(uci -q get miio_ot.ot.partner_id)
	if [ -n "$partner_id" ]; then
		partner_id="miwifi.$partner_id"
	fi

	json_init
	json_add_string "method" "_internal.info"
	json_add_object "params"

	json_add_string "partner_id" "$partner_id"
	json_add_string "hw_ver" "Linux"
	json_add_string "fw_ver" "$sw_version"
	[ -n "$bind_key" ] && json_add_string "bind_key" "$bind_key"
	json_add_boolean "auto_ota" "$MIIO_AUTO_OTA"

	json_add_object "ap"
	json_add_string "ssid" ""
	json_add_string "bssid" ""
	json_add_string "rssi" "0"
	json_add_int "freq" 0
	json_close_object

	json_add_object "netif"
	json_add_string "localIp" "$lan_ip"
	json_add_string "mask" "$lan_mask"
	json_add_string "gw" "$lan_gw"
	json_close_object

	json_close_object

	reply=$(json_dump)
	json_cleanup

	send_miio_json "$reply"
}

clear_wifi_conf() {
	log_info "clean wifi config"
}

save_tz_conf() {
	log_info "$1"
}

wifi_start() {
	log_info "wifi start "
}

wifi_reconnect() {
	log_info "wifi reconnect"
}

wifi_reload() {
	log_info "wifi reload"
}

main() {
	local method=""
	local data=""

	send_helper_ready

	while true; do
		if ! data=$(recv_miio_json); then
			sleep 1
			continue
		fi

		if [ -z "$data" ]; then
			continue
		fi

		dbg_info "miio recv data: $data"
		method=$(echo "$data" | jsonfilter -e '@.method')

		if [ "$method" = "_internal.request_dinfo" ]; then
			request_dinfo "$data"
		elif [ "$method" = "_internal.request_ot_config" ]; then
			request_ot_config "$data"
		elif [ "$method" = "_internal.req_wifi_conf_status" ]; then
			req_wifi_conf_status "$data"
		elif [ "$method" = "_internal.update_dtoken" ]; then
			update_dtoken "$data"
		elif [ "$method" = "_internal.info" ]; then
			internal_info "$data"
		elif [ "$method" = "_internal.config_tz" ]; then
			save_tz_conf "$data"
		elif [ "$method" = "_internal.wifi_start" ]; then
			wifi_start "$data"
		elif [ "$method" = "_internal.wifi_reconnect" ]; then
			wifi_reconnect
		elif [ "$method" = "_internal.wifi_reload" ]; then
			wifi_reload
		else
			log_info "Unknown cmd: $data"
		fi
	done
}

usage() {
	cat <<-EOF
		Usage: $PROG ..OPTION
		  -d enable debug output
		  -l enable local read/write
	EOF
}

while getopts "dlh" opt; do
	case "${opt}" in
	d)
		gDebug=1
		;;
	l)
		gLocal=1
		;;
	h)
		usage
		exit
		;;
	\?)
		usage >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

main
