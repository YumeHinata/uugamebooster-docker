#!/bin/sh

. /lib/miwifi/hotupgrade/hotupgrade_func.sh

HOTUPGRADE_TYPE=antiy-url-firewall

CONFIG_FILE=antiy_url_policy
DB_PROFILE=antiy_url_class

TARGET_PATH=/etc/antiy
OVERLAY_PATH=/data/etc/antiy

hotupgrade_preinit_clean() {
    umount "${TARGET_PATH}"
    rm -rf "${OVERLAY_PATH}"/*
    cp -r "${TARGET_PATH}"/* "${OVERLAY_PATH}"
    mount --bind "${OVERLAY_PATH}" "${TARGET_PATH}"
}

is_update_enable() {
    [ "$(uci get ${CONFIG_FILE}.meta.auto_update)" = "1" ]
}

is_db_newer() {
    [ "$1" -gt "$(uci get ${DB_PROFILE}.meta.version)" ]
}

hotupgrade_json_check() {
    if ! is_update_enable; then
        return 1
    fi

    local json_input="$1"
    local version

    . /usr/share/libubox/jshn.sh
    json_load "$json_input"
    json_get_var version version
    is_db_newer "${version}"
}

hotupgrade_file_check() {
    is_db_newer "$(uci -c ./etc/antiy get ${DB_PROFILE}.meta.version)"
}

hotupgrade_file_pre() {
    /etc/init.d/antiy-url-fw stop
}

hotupgrade_file_main() {
    rm -rf "${TARGET_PATH}"/*
    cp -r ./etc/antiy/* "${TARGET_PATH}"
}

hotupgrade_file_end() {
    uci set antiy_url_policy.meta.update_ts="$(date +%s)" && uci commit antiy_url_policy
    /etc/init.d/antiy-url-fw start
}
