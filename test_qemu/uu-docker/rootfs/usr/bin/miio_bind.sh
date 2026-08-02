#!/bin/sh

readonly PROG_NAME="miio_bind"
readonly MAX_RETRY=3

gBkey=
gUser=
gMver=
gCheck=

log() {
	logger -p user.err -t "$PROG_NAME" "$1"
}

matool_api() {
	local api="$1"

	matool --method api_call --params "$api" 'data={}'
}

get_uid() {
	local code state data

	data=$(matool_api /device/minet_get_bindinfo)
	code=$(echo "$data" | jsonfilter -e "$.code")

	if [ "$code" -eq 3029 ]; then
		log "Device invalid"
		return 0
	fi

	if [ "$code" -ne 0 ]; then
		log "Fail to get bound state. info: $data"
		return 2
	fi

	state=$(echo "$data" | jsonfilter -e "$.data.bind")

	if [ "$state" -ne 1 ]; then
		log "Device unbound. info: $data"
		return 1
	fi

	echo "$data" | jsonfilter -e "$.data.admin"
}

get_key() {
	local code data

	data=$(matool_api /device/miot/get_bind_key)
	code=$(echo "$data" | jsonfilter -e "$.code")

	if [ "$code" -eq 3029 ]; then
		log "Device invalid"
		return 0
	fi

	if [ "$code" -ne 0 ]; then
		log "Fail to get bindkey. info: $data"
		return 1
	fi

	echo "$data" | jsonfilter -e "$.data.bindKey"
}

retry_func() {
	local func="$1"
	local data=
	local retry=0

	while [ "$retry" -lt "$MAX_RETRY" ]; do
		if data=$("$func"); then
			echo "$data"
			return 0
		fi

		retry=$((retry + 1))
		log "Retry matool $api count $retry"
		sleep 1
	done
}

ctrl_srv() {
	local cmd="$1"
	local srv="$2"

	if [ ! -e "/etc/init.d/$srv" ]; then
		return
	fi

	/etc/init.d/"$srv" "$cmd"
}

stop_srvs() {
	ctrl_srv stop miio_client
	ctrl_srv stop miio_bt
	ctrl_srv stop central_lite
}

start_srvs() {
	ctrl_srv restart miio_client
	ctrl_srv restart miio_bt
	ctrl_srv restart central_lite
}

bind_v1() {
	local uci_bind_key=
	local uci_partner_id=
	local bind_uid=""
	local bind_key=""

	uci_bind_key=$(uci -q get miio_ot.ot.bind_key)
	uci_partner_id=$(uci -q get miio_ot.ot.partner_id)

	if [ "$(uci -q get xiaoqiang.common.NETMODE)" = "whc_re" ]; then
		uci_device_id=$(uci -q get bind.info.remoteID)
	else
		uci_device_id=$(uci -q get messaging.deviceInfo.DEVICE_ID)
	fi

	if [ "$uci_device_id" = "null" ] || [ -z "$uci_device_id" ]; then
		log "Device id not exist"
		return 0
	fi

	if [ -n "$uci_bind_key" ] && [ "$uci_device_id" = "$uci_partner_id" ]; then
		log "Duplicate binding"
		return 0
	fi

	bind_uid=$(get_uid)
	if [ -n "$bind_uid" ]; then
		return 1
	fi

	bind_key=$(get_key)

	if [ -n "$bind_key" ]; then
		return 0
	fi

	stop_srvs

	uci -q set miio_ot.ot.bind_key="$bind_key"
	uci -q set miio_ot.ot.partner_id="$uci_device_id"
	uci -q set y=""
	uci commit miio_ot

	rm -rf /data/miio_ot/
	rm -rf /data/bt_mesh
	rm -rf /data/local/miio_bt

	start_srvs

	log "bind finished"
}

get_payload() {
	matool --method identifyDevice --params simple
}

bind_v2() {
	local key="$1"
	local uid="$2"
	local method="_sync.device_bind"
	local nmode token did name pid mid hw model mac ts payload reply

	if [ -z "$key" ] || [ -z "$uid" ]; then
		log "Invalid params"
		return 1
	fi

	nmode=$(uci -q get xiaoqiang.common.NETMODE)

	if [ "$nmode" != "whc_re" ]; then
		# Device ID will be changed after payload got!
		payload=$(get_payload)
	fi

	token=$(uci -q get miio_ot.ot.token | xargs printf | hexdump -ve '1/1 "%.2x"')
	if [ -z "$token" ]; then
		# no token in uci, delete miio_ot database and restart miio_client
		rm /data/miio_ot/config.db
		/etc/init.d/miio_client restart

		# loop to get token
		local retry=0
		while [ "$retry" -lt "$MAX_RETRY" ]; do
			token=$(uci -q get miio_ot.ot.token | xargs printf | hexdump -ve '1/1 "%.2x"')
			if [ -n "$token" ]; then
				# wait for miio_client to connect to cloud server
				sleep 2
				break
			fi

			retry=$((retry + 1))
			log "Retry get token count $retry"
			# wait for miio_client to generate token
			sleep 1
		done
	fi

	did=$(get_miot_did.sh)
	name=$(uci -q get xiaoqiang.common.ROUTER_NAME)
	pid=$(uci -q get messaging.deviceInfo.DEVICE_ID)
	mid="$pid"
	hw=$(uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE | awk '{print tolower($0)}')
	model="xiaomi.router.$hw"
	mac=$(getmac wan)
	ts=$(date +%s)

	if [ "$nmode" = "whc_re" ]; then
		mid=$(uci get bind.info.remoteID)
	fi

	# Format json
	. /usr/share/libubox/jshn.sh

	json_init
	json_add_string "method" "$method"
	json_add_object "params"

	json_add_int "uid" "$uid"
	json_add_string "did" "$did"
	json_add_string "model" "$model"
	json_add_string "name" "$name"
	json_add_string "bindkey" "$key"
	json_add_string "token" "$token"
	json_add_string "mac" "$mac"
	json_add_int "time" "$ts"
	json_add_string "partner_id" "$pid"
	json_add_string "mesh_id" "$mid"

	if [ "$nmode" != "whc_re" ]; then
		json_add_boolean "is_sync_to_third" "1"
		json_add_object "reg_info"
		json_add_string "payload" "$payload"
		json_close_object
	fi

	json_close_object

	reply=$(json_dump)
	json_cleanup

	json_init
	json_add_string "msg" "$reply"
	json_add_string "cb" "$method"
	reply=$(json_dump)
	json_cleanup

	ubus send miio_proxy "$reply"
}

is_bound() {
	local check="$1"

	if [ -z "$check" ]; then
		return 1
	fi

	# Only RE mode need to check
	if ! uci -q get xiaoqiang.common.NETMODE | grep -qsw whc_re; then
		log "not in re mode, skip it"
		return 0
	fi

	if uci -q get miio_ot.ot.bound | grep -qsx 1; then
		log "already bound, skip it"
		return 0
	fi

	return 1
}

do_unbind() {
	local retry=4

	while [ $retry -gt 0 ]; do
		local bind_status="$(uci -q get miio_ot.ot.bound)"
		[ "$bind_status" != "1" ] && break

		ubus send miio_proxy '{ "msg": "{ \"method\": \"_sync.device_unbind\", \"params\":{} }", "cb": "_sync.device_unbind" }'
		sleep 1
		retry=$((retry - 1))
	done
}

usage() {
	cat <<-EOF
		Usage: $PROG ..OPTION
		  -b bind key
		  -u user id
		  -c check bind status first, skip if already bound
	EOF
}

while getopts "b:u:ch" opt; do
	case "${opt}" in
	b)
		gBkey=${OPTARG}
		;;
	u)
		gUser=${OPTARG}
		;;
	c)
		gCheck=1
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

gMver=$(uci -q get miio_ot.ot.ver)

if [ "${gMver:-0}" -ge 2 ]; then
	if is_bound "$gCheck"; then
		exit 0
	fi

	if [ "$(uci -q get xiaoqiang.common.NETMODE)" = "whc_re" ]; then
		# Auto gen key and uid in re mode if not specified
		[ -z "$gBkey" ] && gBkey=$(retry_func get_key)
		[ -z "$gUser" ] && gUser=$(retry_func get_uid)
	else
		[ -z "$gBkey" ] || [ -z "$gUser" ] && exit 0

		# unbinding if already bound, only on non-whc_re node
		do_unbind
	fi

	bind_v2 "$gBkey" "$gUser"
else
	bind_v1
fi
