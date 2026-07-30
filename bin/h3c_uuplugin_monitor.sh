#!/bin/sh

DOWNLOAD_URL="https://router.uu.163.com/api/plugin?type=h3c-"
MONITOR_FILE="monitor.sh"
UPDATE_FILE="uu.update"
RUNNING_DIR="/var/tmp/uu"
PLUGIN_MOUNT_DIR="/var/tmp/plugmnt"
PLUGIN_DIR="/var/tmp/plugmnt/uu"
PLUGIN_TAR="uu.tar.gz"
PLUGIN_EXE="uuplugin"
PLUGIN_CONF="uu.conf"
PID_FILE="/var/run/uuplugin.pid"
PLUGIN_TAR_MD5_FILE="uu.tar.gz.md5"
H3C_INFO="/var/tmp/uu/h3c_info"

system_init() {
    ulimit -HS -s 8192

    local factoryinfo="${H3C_INFO}"
    ##编辑：替换路径。因这个路径是系统保留路径，程序本意是从这里读取NX30 pro的SN号，这个路径在openwrt系统是没有的。我们需要自己创建一个路径然后把他要读取的文件放进去
    #local proc_factoryinfo="/proc/manufactory/factoryinfo"
    local proc_factoryinfo="/usr/uufactory/factoryinfo"
    local productname=$(grep 'productname' "${factoryinfo}" | cut -d'=' -f2)
    local sn=$(grep 'manucode' "${factoryinfo}" | cut -d'=' -f2)

    if [ "" = "${productname}" ];then
        productname=$(grep 'productname' "${proc_factoryinfo}" | cut -d'=' -f2)
    fi

    if [ "" = "$sn" ];then
        sn=$(grep 'manucode' "${proc_factoryinfo}" | cut -d'=' -f2)
    fi

    productname=$(echo "${productname}" | sed 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/')
    DOWNLOAD_URL=${DOWNLOAD_URL}${productname}"&sn=${sn}"
}

check_dir() {
    if [ ! -d "${RUNNING_DIR}" ];then
        mkdir -p "${RUNNING_DIR}"
    fi

    if [ ! -d "${PLUGIN_DIR}" ];then
        mkdir -p "${PLUGIN_DIR}"
    fi
}

check_plugin_file() {
    # One of ${exefile}, ${runtar}, ${backtar} must exist.
    local exefile="${RUNNING_DIR}/${PLUGIN_EXE}"
    local runtar="${RUNNING_DIR}/${PLUGIN_TAR}"
    local backtar="${PLUGIN_DIR}/${PLUGIN_TAR}"

    if [ ! -e "${exefile}" ] && [ ! -e "${runtar}" ] && [ ! -e "${backtar}" ];then
        download_acc "${runtar}"
    fi
}

# Return: 0 means running.
check_running() {
    if [ -f "$PID_FILE" ];then
        pid=$(cat $PID_FILE)
        running_pid=$(ps | sed 's/^[ \t ]*//g;s/[ \t ]*$//g' | \
            sed 's/[ ][ ]*/#/g' | grep "${PLUGIN_EXE}" | \
            grep -v "grep" | cut -d'#' -f1 | grep -e "^${pid}$")
        if [ "$pid" = "${running_pid}" ];then
            return 0
        fi
    fi
    return 1
}

# Return: 0 means update flag is set.
check_update() {
    if [ -f "${RUNNING_DIR}/${UPDATE_FILE}" ];then
        return 0
    else
        return 1
    fi
}

# $1: FileName to where content to be saved. 
# Return: 0 means success.
download_acc() {
    # Check if network is reachable.
    curl -s -k -H "Accept:text/plain" "$DOWNLOAD_URL" >/dev/null 2>&1  
    [ "$?" != "0" ]  && return 1
    local plugin_info=$(curl -s -k -H "Accept:text/plain" "$DOWNLOAD_URL")
    [ "$?" != "0" ] && return 1
    [ -z "$plugin_info" ] && return 1

    local plugin_url=$(echo "$plugin_info" | cut  -d ',' -f 1)
    local plugin_md5=$(echo "$plugin_info" | cut  -d ',' -f 2)

    if [ -z "${plugin_url}" ];then
        echo "plugin_url is empty."
        return 1
    fi

    if [ -z "${plugin_md5}" ];then
        echo "plugin_md5 is empty."
        return 1
    fi

    curl -s -k "$plugin_url" -o "$1" >/dev/null 2>&1
    if [ "$?" != "0" ];then
        echo "Failed: curl -s -k ${plugin_url} -o ${1}"
        # Clean up
        [ -f "$1" ] && rm "${1}"
        return 1
    fi

    if [ -f "$1" ];then
        local download_md5=$(md5sum "$1")
        # H3C的md5结果多了两个空白符
        local download_md5=$(echo "$download_md5" | sed 's/[ ][ ]*/ /g' | cut -d' ' -f1)
        if [ "$download_md5" != "$plugin_md5" ];then
            echo "${1} downloaded has incorrect md5."
            rm "$1"
            return 1
        fi

        echo "${1} has been successfully downloaded."
        return 0
    else
        echo "Fail to download ${1}."
        return 1
    fi
}

# $1: FileName of which md5sum will be saved.
# $2: FileName where md5sum will be saved.
save_md5sum() {
    [ ! -f "${1}" ] && return
    touch "${2}"

    local filemd5sum=$(md5sum "$1")
    filemd5sum=$(echo "${filemd5sum}" | sed 's/[ ][ ]*/ /g' | cut -d' ' -f1)
    echo "File md5sum: ${filemd5sum}"
    echo "${filemd5sum}" > "${2}"
}

check_backtar_file() {
    local runtar="${RUNNING_DIR}/${PLUGIN_TAR}"
    local backtar="${PLUGIN_DIR}/${PLUGIN_TAR}"
    local md5file="${PLUGIN_DIR}/${PLUGIN_TAR_MD5_FILE}"

    if [ ! -e "${backtar}" ];then
        download_acc "${runtar}"
        if [ "$?" != "0" ]; then
            [ -f "${runtar}" ] && rm "${runtar}"
            return
        fi

        check_space
        if [ "$?" = "0" ];then
            cp "${runtar}" "${backtar}"
            if [ "$?" != "0" ]; then
                [ -f "${backtar}" ] && rm "${backtar}"
                [ -f "${runtar}" ] && rm "${runtar}"
                return
            fi

            save_md5sum "${runtar}" "${md5file}"
        else
            echo "No enough space is available."
        fi

        [ -f "${runtar}" ] && rm "${runtar}"
        return
    fi

    [ -f "${md5file}" ] && return
    save_md5sum "${backtar}" "${md5file}"
}

# $1: FileName of which md5sum to be checked.
# $2: FileName that contains md5.
# Return: 0 means success.
check_md5sum() {
    [ ! -f "$1" -o ! -f "$2" ] && return 1

    local plugin_md5=$(md5sum "$1")
    [ "$?" != "0" ] && return 1

    local right_md5=$(cat "${2}")
    [ "$?" != "0" ] && return 1

    plugin_md5=$(echo "$plugin_md5" | sed 's/[ ][ ]*/ /g' | cut -d' ' -f1)
    if [ "$right_md5" != "$plugin_md5" ];then
        echo "Error: md5 does not match."
        return 1
    fi
    return 0
}

# Check if enough space is available in flash.
# Return: 0 means enough space is available; other mean errors.
check_space() {
    local df_res=$(df | grep "${PLUGIN_MOUNT_DIR}" | grep -v "grep")
    [ -z "${df_res}" ] && return 0

    df_res=$(echo "${df_res}" | sed 's/[ ][ ]*/#/g')
    local available=$(echo "${df_res}" | cut -d'#' -f4)
    echo "Available space is ${available}"

    [ "${available}" -ge 500 ] && return 0
    return 1
}

start_acc() {
    # Start order:
    # 1. ${exefile}
    # 2. ${runtar}
    # 3. ${backtar}
    local exefile="${RUNNING_DIR}/${PLUGIN_EXE}"
    local runtar="${RUNNING_DIR}/${PLUGIN_TAR}"
    local backtar="${PLUGIN_DIR}/${PLUGIN_TAR}"
    local confile="${RUNNING_DIR}/${PLUGIN_CONF}"
    if [ -e "${exefile}" ];then
        chmod u+x "${exefile}"
        ${exefile} "${confile}" >/dev/null 2>&1 &
        return
    fi
    if [ -f "${runtar}" ];then
        tar zxvf "${runtar}" -C "${RUNNING_DIR}" 
        if [ "$?" = "0" ];then
            chmod u+x "${exefile}"
            ${exefile} "${confile}" >/dev/null 2>&1 &

            # ${runtar} is not needed any more.
            rm "${runtar}"
            return
        fi
    fi
    if [ -f "${backtar}" ];then
        check_md5sum "${backtar}" "${PLUGIN_DIR}/${PLUGIN_TAR_MD5_FILE}"
        if [ "$?" != "0" ];then
            # Download a new one. Next time ${runtar} will be used.
            download_acc "${runtar}"
            return
        fi

        tar zxvf "${backtar}" -C "${RUNNING_DIR}"
        if [ "$?" != "0" ];then
            return
        fi

        chmod u+x "${exefile}"
        ${exefile} "${confile}" >/dev/null 2>&1 &
        return
    else
        # Download a new one. Next time ${runtar} will be used.
        download_acc "${runtar}"
        return
    fi
}

check_acc() {
    cd $RUNNING_DIR
    check_running
    [ "$?" = "0" ] && return

    check_update
    if [ "$?" != "0" ];then
        # "uuplugin" is not running, and no need to be updated.
        # Just try to start again.
        start_acc
        return
    fi

    # Try to update.
    local exefile="${RUNNING_DIR}/${PLUGIN_EXE}"
    local runtar="${RUNNING_DIR}/${PLUGIN_TAR}"
    local backtar="${PLUGIN_DIR}/${PLUGIN_TAR}"

    download_acc "${runtar}"
    if [ "$?" != "0" ];then
        # Download failed; Just try to start again.
        [ -f "${runtar}" ] && rm "${runtar}"
        start_acc
        return
    fi

    rm $(ls | grep -v "$MONITOR_FILE" | grep -v "$PLUGIN_TAR" | grep -v "${H3C_INFO}")
    # 刚下载的插件，不需要重新检查md5
    tar zxvf "${runtar}" -C "${RUNNING_DIR}"
    if [ "$?" != "0" ];then
        # Clean up.
        rm $(ls | grep -v "$MONITOR_FILE" | grep -v "${H3C_INFO}")
        start_acc
        return
    fi

    chmod u+x "${exefile}"
    ${exefile} "${RUNNING_DIR}/$PLUGIN_CONF" >/dev/null 2>&1 &

    # Check if flash space is enough
    rm ${backtar}
    check_space
    if [ "$?" = "0" ];then
        local backtar_md5file="${PLUGIN_DIR}/${PLUGIN_TAR_MD5_FILE}"
        cp ${runtar} ${backtar}
        if [ "$?" != "0" ];then
            [ -f "${backtar}" ] && rm "${backtar}"
            [ -f "${backtar_md5file}" ] && rm "${backtar_md5file}"
            rm ${runtar}
            echo "Update operation failed."
            return
        fi

        save_md5sum "${runtar}" "${backtar_md5file}"

        echo "Update operation succeeded."
        rm ${runtar}
        return
    else
        echo "Warning: no enough space is available."
        echo "Update operation failed."
        rm ${runtar}
        return
    fi
}

system_init
check_dir

while :
do
    check_backtar_file
    check_plugin_file
    check_acc
    sleep 1
    check_running
    if [ "$?" = "0" ];then
        # Plugin is running, so we will check again in 60 seconds.
        sleep 60
    else
        # Plugin is not running now, so check it more frequently.
        sleep 5
    fi
done

