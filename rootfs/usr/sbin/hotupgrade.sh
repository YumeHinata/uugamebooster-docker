#!/bin/sh
#

. /lib/miwifi/hotupgrade/hotupgrade_func.sh

run_with_lock()
{
    local result=0
    {
        klogger "$$, ====== TRY locking......"
        flock -w 120 1004
        [ $? -eq "1" ] && { klogger "$$, ===== GET lock failed. exit 1" ; exit 1 ; }
        klogger "$$, ====== GET lock to RUN."
        $@ 1004>&-
        result=$?
        klogger "$$, ====== END lock to RUN."
    } 1004<>/var/log/hotupgrade_lock.lock
    return $result
}

# 检查传入的Json，判断是否要下载
hotupgrade_check()
{
    local name=$1
    local json_str=$2

    if [ -z "$name" -o -z "$json_str" ]; then
        return 1
    fi

    if [ ! -f /lib/miwifi/hotupgrade/"$name".sh ]; then
        return 1
    fi

    . /lib/miwifi/hotupgrade/"$name".sh
    hotupgrade_json_check $json_str
    return $?
}

# 热升级前准备工作
hotupgrade_pre_process()
{
    local bin_file=$1
    local tar_file

    # 参数确认
    if [ -z "$bin_file" -o ! -f "$bin_file" ]; then
        klogger "USAGE: $0 input.bin"
        return 1
    fi

    # 固件校验
    hotupgrade_verify_image $bin_file
    if [ "$?" = "0" ]; then
        klogger "Hotupgrade: image verify O.K."
    else
        klogger "Hotupgrade: image verify Failed!!!"
        return 1
    fi

    [ -d $HOTUPGRADE_DIR ] || mkdir $HOTUPGRADE_DIR
    hotupgrade_prepare_dir $bin_file
    cd $HOTUPGRADE_TMP_DIR

    mkxqimage -x $HOTUPGRADE_TMP_DIR/$(basename "$bin_file")

    if [ ! -f ./$HOTUPGRADE_INFO_FILE_NAME ]; then
        klogger "Hotupgrade: No hotupgrade info file found"
        return 1
    fi

    # 获取tar文件
    tar_file=$(ls | grep "\.tar\.gz" | head -n 1)
    if [ -z "$tar_file" ]; then
        klogger "Hotupgrade: No hotupgrade tar file found"
        return 1
    fi

    rm $HOTUPGRADE_TMP_DIR/$(basename "$bin_file")
    tar -xzvf $tar_file > /dev/null
}

# 进行热升级流程
hotupgrade_process()
{
    local hotupgrade_name

    if [ ! -f ./$HOTUPGRADE_INFO_FILE_NAME ]; then
        return 1
    else
        hotupgrade_name=$(grep "$HOTUPGRADE_NAME_PREFIX" $HOTUPGRADE_INFO_FILE_NAME | awk -F= '{print $2}')
    fi

    if [ ! -f /lib/miwifi/hotupgrade/"$hotupgrade_name".sh ]; then
        return 1
    else
        . /lib/miwifi/hotupgrade/"$hotupgrade_name".sh
    fi

    if [ ! -d $HOTUPGRADE_DIR/$hotupgrade_name ]; then
        mkdir $HOTUPGRADE_DIR/$hotupgrade_name
    fi

    hotupgrade_status_update $hotupgrade_name $HOTUPGRADE_STATUS_START

    # 热升级文件校验
    hotupgrade_file_check || { hotupgrade_status_update $hotupgrade_name $HOTUPGRADE_STATUS_END; return 1; }
    hotupgrade_status_update $hotupgrade_name $HOTUPGRADE_STATUS_CHECK_DONE

    # 热升级文件前
    hotupgrade_file_pre || return 1
    hotupgrade_status_update $hotupgrade_name $HOTUPGRADE_STATUS_PRE_DONE

    # 热升级文件
    hotupgrade_file_main || return 1
    hotupgrade_status_update $hotupgrade_name $HOTUPGRADE_STATUS_MAIN_DONE

    # 热升级文件后
    hotupgrade_file_post || return 1
    hotupgrade_status_update $hotupgrade_name $HOTUPGRADE_STATUS_POST_DONE

    # 热升级结束阶段
    hotupgrade_file_end || return 1
    hotupgrade_status_update $hotupgrade_name $HOTUPGRADE_STATUS_END
}

# 清空临时目录
hotupgrade_post_process()
{
    if [ -d $HOTUPGRADE_TMP_DIR ]; then
        rm -rf $HOTUPGRADE_TMP_DIR
    fi
    return 0
}

hotupgrade_main()
{
    local file=$1
    local result=1

    hotupgrade_pre_process $file && hotupgrade_process && result=0
    hotupgrade_post_process
    return $result
}

op=$1
case "${op}" in
    clean*)
        run_with_lock hotupgrade_clean $2
        exit $?
        ;;
    check*)
        run_with_lock hotupgrade_check $2 $3
        exit $?
        ;;
    *)
        run_with_lock hotupgrade_main $1 $2
        exit $?
        ;;
esac