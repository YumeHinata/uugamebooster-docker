#!/bin/ash

CUR_DIR='/data/etc/mipctl'
ROM_DIR='/etc/mipctl'
DOWNLOAD_DIR='/tmp/mipctl_upg'
MIPCTL_LOCK='/var/lock/mipctl.lock'
INIT_FILE='/etc/init.d/mipctl.d'
PROG_UPG='mipctl_upg_ucfg'

cur_ver=$(uci -c ${CUR_DIR} get mipctl_app.meta.appinfo_version)

# $1: new ver string
# $2: old ver string
is_same_iplmt() {
    local new_ver="${1}"
    local old_ver="${2:-"${cur_ver}"}"

    new_ver=$(echo "${new_ver}" | sed -nr 's/^(.*)\.[0-9]+$/\1/ p')
    old_ver=$(echo "${old_ver}" | sed -nr 's/^(.*)\.[0-9]+$/\1/ p')

    if [ "${new_ver}" = "${old_ver}" ]; then
        return 0
    else
        return 1
    fi
}

# $1: new ver string
# $2: old ver string
is_new_version() {
    local new_ver="${1}"
    local old_ver="${2:-"${cur_ver}"}"

    new_ver=$(echo "${new_ver}" | sed -nr 's/^.*\.([0-9]+)$/\1/ p')
    old_ver=$(echo "${old_ver}" | sed -nr 's/^.*\.([0-9]+)$/\1/ p')

    if [ "${new_ver}" -gt "${old_ver}" ]; then
        return 0
    else
        return 1
    fi
}

# 0: suc upgraded
# 1: upgraded files not found
# 2: failed to stop mipctl
# 4: failed to merge user config
upgrade() {
    # 1. check upgrade files
    if [ -e "${ROM_DIR}/mipctl_app" ]; then
        rom_ver=$(uci -c ${ROM_DIR} get mipctl_app.meta.appinfo_version)
        if is_new_version "${rom_ver}" "${cur_ver}" || ! is_same_iplmt "${rom_ver}" "${cur_ver}"; then
            cur_ver=${rom_ver}
            new_dir=${ROM_DIR}
        fi
    fi
    if [ -e "${DOWNLOAD_DIR}/mipctl_app" ]; then
        download_ver=$(uci -c ${DOWNLOAD_DIR} get mipctl_app.meta.appinfo_version)
        if is_new_version "${download_ver}" "${cur_ver}" && is_same_iplmt "${download_ver}" "${cur_ver}"; then
            cur_ver=${download_ver}
            new_dir=${DOWNLOAD_DIR}
        fi
    fi
    if [ -z "${new_dir}" ]; then
        return 1    # can not find the upgrade file.
    fi
    logger -s -t mipctlv2 -p user.info "Found a dpi in ${new_dir}"

    # 2. stop mipctl if is running
    if [ -e "${MIPCTL_LOCK}" ]; then
        logger -s -t mipctlv2 -p user.info "Stopping mipctlv2..."
        if "${INIT_FILE}" stop; then
            is_running=1
        else 
            logger -s -t mipctlv2 -p user.err "Cannot stop mipctlv2"
            return 2    # cannot stop mipctl
        fi
    fi

    # 3. run shell script
    if [ -e "${new_dir}"/_run.sh ]; then
        if ! "${new_dir}"/_run.sh; then
            logger -s -t mipctlv2 -p user.err "_run.sh blocks upgrading"
            return 3
        fi
    fi

    # 4. try to upgrade user config file
    logger -s -t mipctlv2 -p user.info "Upgrading user configuration"
    if ! "${PROG_UPG}" "${new_dir}/mipctl_app" "${CUR_DIR}/mipctl_app"; then
        logger -s -t mipctlv2 -p user.err "Failed to upgrade mipctl_user"
        if [ -n "${is_running}" ]; then # try to resume
            logger -s -t mipctlv2 -p user.err "Try to resume"
            "${INIT_FILE}" start
        fi
        return 4
    fi

    # 5. upgrade
    # TODO: remove useless files
    cp -f "${new_dir}"/* "${CUR_DIR}"
    if [ -e "${DOWNLOAD_DIR}" ]; then
        rm -rf "${DOWNLOAD_DIR}"
    fi

    # 6. resume
    if [ -n "${is_running}" ]; then
        "${INIT_FILE}" start
    fi

    logger -s -t mipctlv2 -p user.info "DPI upgrading finished."
}

case "${1}" in
    is_same_iplmt)
        is_same_iplmt "${2}" "${3}"
    ;;
    is_new_version)
        is_new_version "${2}" "${3}"
    ;;
    *)
        upgrade
    ;;
esac