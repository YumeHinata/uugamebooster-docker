#!/bin/sh
#

. /lib/upgrade/libupgrade.sh

hotupgrade_preinit_clean() { return; }
hotupgrade_json_check() { return; }
hotupgrade_file_check() { return; }
hotupgrade_file_pre() { return; }
hotupgrade_file_main() { return; }
hotupgrade_file_post() { return; }
hotupgrade_file_end() { return; }

HOTUPGRADE_DIR="/data/hotupgrade"
HOTUPGRADE_TMP_DIR="/tmp/hotupgrade"
MOUNT_DIR_NAME="mountfile"
STATUS_FILE_NAME="hotupgrade_status"
HOTUPGRADE_INFO_FILE_NAME="hotupgrade_info"
HOTUPGRADE_NAME_PREFIX="HOTUPGRADE_NAME="

HOTUPGRADE_STATUS_END=0
HOTUPGRADE_STATUS_START=1
HOTUPGRADE_STATUS_CHECK_DONE=2
HOTUPGRADE_STATUS_PRE_DONE=3
HOTUPGRADE_STATUS_MAIN_DONE=4
HOTUPGRADE_STATUS_POST_DONE=5

# 固件校验
hotupgrade_verify_image() {
    local image_path="$1"

    # 校验签名
    if ! mkxqimage -v "$image_path"; then
        return 1
    fi

    # 确认是hotupgrade文件
    if ! mkxqimage -c $image_path -f $HOTUPGRADE_INFO_FILE_NAME 1>/dev/null; then
        return 1
    fi

    return 0
}

# 移动文件到对应目录
hotupgrade_prepare_dir() {
    absolute_path=$(echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")")
    rm -rf "$HOTUPGRADE_TMP_DIR"
    mkdir -p "$HOTUPGRADE_TMP_DIR"

    if [ ${absolute_path:0:4} = "/tmp" ]; then
        mv "$absolute_path" "$HOTUPGRADE_TMP_DIR"
    else
        cp "$absolute_path" "$HOTUPGRADE_TMP_DIR"
    fi
}

# 更新升级状态
hotupgrade_status_update()
{
    local name=$1
    local status=$2

    if [ -z "$name" -o -z "$status" ]; then
        return
    fi

    if [ -d $HOTUPGRADE_DIR/$name ]; then
        klogger "Hotupgrade: $name status change to $status"
    else
        klogger "Hotupgrade: $name status change to $status fail, $HOTUPGRADE_DIR/$name not exist"
    fi
    sync
    echo $status > $HOTUPGRADE_DIR/$name/$STATUS_FILE_NAME
}

# 遍历mountfile目录进行umount
hotupgrade_file_umount()
{
    local name=$1

    if [ -z "$name" ]; then
        return 1
    fi

    if [ -d $HOTUPGRADE_DIR/"$name"/$MOUNT_DIR_NAME ]; then
        for file in $(find $HOTUPGRADE_DIR/"$name"/$MOUNT_DIR_NAME -mindepth 1 ! -type d); do
            umount ${file##$HOTUPGRADE_DIR/"$name"/$MOUNT_DIR_NAME}
        done
    fi
}

# 遍历mountfile目录进行mount
hotupgrade_file_mount()
{
    local name=$1

    if [ -z "$name" ]; then
        return 1
    fi

    if [ -d $HOTUPGRADE_DIR/"$name"/$MOUNT_DIR_NAME ]; then
        for file in $(find $HOTUPGRADE_DIR/"$name"/$MOUNT_DIR_NAME -mindepth 1 ! -type d); do
            # 只读方式mount到对应
            mount --bind $file ${file##$HOTUPGRADE_DIR/"$name"/$MOUNT_DIR_NAME}
            mount -o remount,bind,ro $file ${file##$HOTUPGRADE_DIR/"$name"/$MOUNT_DIR_NAME}
        done
    fi
}

# 清空hotupgrade指定内容
hotupgrade_clean()
{
    local name=$1

    if [ -z "$name" ]; then
        return 1
    fi

    klogger "Hotupgrade: clean $name hotupgrade file"
    hotupgrade_file_umount $name
    rm -rf $HOTUPGRADE_DIR/"$name"/
}