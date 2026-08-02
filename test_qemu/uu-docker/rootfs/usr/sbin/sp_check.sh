#!/bin/ash

readonly TS_FILE=/var/run/statpoints.ts
readonly WORK_DIR=/tmp/stat_points
readonly LOG_FILES="$WORK_DIR/web.log $WORK_DIR/rom.log $WORK_DIR/privacy.log $WORK_DIR/pri_rom.log"
readonly JSON_FILE="$WORK_DIR/stat_points.json"
readonly GZIP_FILE="$JSON_FILE.gz"
readonly UPLOAD_OUT="$WORK_DIR/upload.out"

readonly INSTANT_KW="stat_points_instant"
readonly PROC_NAME="sp_check"

readonly MAX_LOGSIZE=8 # KiB

dPeriod=3550 # 50 seconds to one hour, reserved for upload

gPeriod=$dPeriod
gForce=
gDebug=

[ "$(uci -q get xiaoqiang.common.sp_enable)" = "0" ] && return

usage() {
	cat <<-EOF
		Usage: $0 OPTION...
		check whether the statpoints' log need to be uploaded

		  -f      Ignore check conditions to force upload
		  -p      Maximum non-upload period, use '$gPeriod' seconds as default
		  -d      Debug mode, do not clean up temporary files
	EOF
}

log_info() {
	logger -t "$PROC_NAME" "$*"
}

init_proc() {
	if [ ! -e "$TS_FILE" ]; then
		touch "$TS_FILE"
	fi
}

deinit_proc() {
	if [ -z "$gDebug" ]; then
		rm -f "$UPLOAD_OUT"
		rm -f "$GZIP_FILE"
	fi
}

check_instant_msg() {
	echo "$LOG_FILES"|xargs grep -qs "$INSTANT_KW"
}

check_max_logsize() {
	local _max=
	local _size=
	local _name=

	_max=$(echo "$LOG_FILES"|xargs du|sort -nr|head -n1)
	_size=$(echo "$_max"|awk '{print $1}')
	_name=$(echo "$_max"|awk '{print $2}')

	if [ "${_size:-0}" -le "$MAX_LOGSIZE" ]; then
		_name=
	fi

	echo "$_name"
}

check_max_timeout() {
	local _old=
	local _new=

	_old=$(stat -c %Y "$TS_FILE")
	_new=$(date +%s)

	test $((_new - _old)) -ge "$gPeriod"
}

get_upload_reason() {
	local _reason=

	_reason=$(check_max_logsize)

	if check_max_timeout; then
		_reason="hourly"
	elif check_instant_msg; then
		_reason="instant"
	fi

	echo "$_reason"
}

create_file() {
	local _nolog=

	_nolog=$(uci -q get misc.features.statpointsNoLog)
	sp_file.lua "$JSON_FILE" "${_nolog:-0}"
	gzip -f "$JSON_FILE"

	echo "$GZIP_FILE"
}

post_upload() {
	local _file=

	# Renew timestamp
	touch "$TS_FILE"

	# Clear all log files, file should be edit in place
	for _file in $LOG_FILES; do
		echo -n ""|tee "$_file"
	done
}

upload_file() {
	local _force=$1
	local _reason=$2
	local _stime=
	local _etime=
	local _fname=
	local _ret=1

	if [ -n "$_force" ]; then
		_reason="force"
	fi

	if [ -z "$_reason" ]; then
		return $_ret
	fi

	_fname=$(create_file)

	_stime=$(cut -d. -f1 /proc/uptime)
	if sp_upload -f "$_fname" >"$UPLOAD_OUT" 2>&1; then
		_ret=0
	fi
	_etime=$(cut -d. -f1 /proc/uptime)

	log_info "stat_points_none log_up_file=$_reason,$((_etime - _stime))"

	return $_ret
}

while getopts "p:fdh" opt; do
	case "${opt}" in
	p)
		gPeriod=${OPTARG}
		;;
	f)
		gForce=1
		;;
	d)
		gDebug=1
		;;
	h)
		usage
		exit 0
		;;
	\?)
		usage >&2
		exit 1
		;;
	esac
done

init_proc

if upload_file "$gForce" "$(get_upload_reason)"; then
	post_upload
fi

deinit_proc
