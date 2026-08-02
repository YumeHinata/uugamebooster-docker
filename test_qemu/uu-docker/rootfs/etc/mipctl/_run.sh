#!/bin/ash
set -e

readonly UPG_INFO_FILE='mipctl_upg_info'
readonly USER_CONFIG_DIR='/data/etc/config'
readonly USER_UCI_FILE='mipctl_user'
cfg_dir=$( readlink -f "$0" | xargs dirname )

if ! uci -c "${USER_CONFIG_DIR}" get "${USER_UCI_FILE}.@user[0]" > /dev/null 2>&1; then
    exit 0
fi

touch "${cfg_dir}/${UPG_INFO_FILE}"
if ! uci -c "${cfg_dir}" get "${UPG_INFO_FILE}.meta" > /dev/null 2>&1; then
    uci -c "${cfg_dir}" set "${UPG_INFO_FILE}.meta=meta"
fi

#uci -c "${cfg_dir}" set "${UPG_INFO_FILE}.meta.date=$(date +%Y-%m-%d)"
uci -c "${cfg_dir}" commit "${UPG_INFO_FILE}"