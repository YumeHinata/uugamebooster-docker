#!/bin/sh

readonly SEC_CFG_VOL_FILE="/data/sec_cfg/data.vol"
readonly SEC_CFG_VOL_BACK="/data/usr/sec_cfg/data.vol"
readonly SEC_CFG_MD5_BACK="/data/usr/sec_cfg/data.md5"
readonly SEC_CFG_DIFF_FILE="/data/usr/sec_cfg/data.xdelta3"
readonly SEC_CFG_DIFF_TMP_FILE="/tmp/data.xdelta3"
readonly SEC_CFG_DIFF_MAX_SIZE=1048576  #1MB

LOCK_FILE="/var/run/sec_cfg_bak.lock"
exec 1009<>"$LOCK_FILE"

if ! flock -n 1009; then
	logger -p 2 -t "sec_cfg_bak" "sec_cfg_bak is running, exit."
	exit 1
fi

sec_cfg_md5_chk() {
	local _new_md5=$(uci show | sort | md5sum | awk '{print $1}')

	grep -sqw "$_new_md5" "$SEC_CFG_MD5_BACK"
}

# Check whether the feature enabled
if uci -q get misc.features.sec_cfg_bak | grep -sqw 1; then
	# Do nothing if vol file not exist
	[ ! -f "$SEC_CFG_VOL_FILE" ] && exit 0

	if ! sec_cfg_md5_chk; then
		mkdir -p "${SEC_CFG_VOL_BACK%/*}"
		if [ -f "$SEC_CFG_VOL_BACK" ]; then
			xdelta3 -fes "$SEC_CFG_VOL_BACK" "$SEC_CFG_VOL_FILE" "$SEC_CFG_DIFF_TMP_FILE"
			diff_size=$(stat -c %s "$SEC_CFG_DIFF_TMP_FILE")
			if [ -n "$diff_size" ] && [ "$diff_size" -le "$SEC_CFG_DIFF_MAX_SIZE" ]; then
				mv "$SEC_CFG_DIFF_TMP_FILE" "$SEC_CFG_DIFF_FILE"
			else
				rm -f "$SEC_CFG_DIFF_FILE"
				rm -f "$SEC_CFG_DIFF_TMP_FILE"
				cp "$SEC_CFG_VOL_FILE" "$SEC_CFG_VOL_BACK"
			fi
		else
			cp "$SEC_CFG_VOL_FILE" "$SEC_CFG_VOL_BACK"
		fi
		uci show | sort | md5sum | awk '{print $1}' | tee "$SEC_CFG_MD5_BACK" >/dev/null
	fi
fi
