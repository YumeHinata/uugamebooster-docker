#!/bin/sh
# Copyright (C) 2015 Xiaomi
#

. /usr/share/libubox/jshn.sh

RETRY_MAX=3
TOUT=5
RET_OK="success"

HARDWARE=`/sbin/uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE`

my_usage()
{
    echo "$0:"
    echo "    log_upload     : send log update message to RE"
    echo "    format: $0 log_upload [log_key]"
    echo "    other: usage."
    return;
}

whc_to_re_log()
{
    logger -s -p info -t whc_to_re "$1"
}


__if_whc_re()
{
    tbus -v list "$1" 2>/dev/null | grep -qE "whc_quire[:\",]+" || return 1
    return 0
}

## notify REs with precompose cmd, if re exist&active
# 1. get and validate WHC_RE active in tbus list, exclude repeater & xiaomi_plc
# 2. run tbus cmd
notify_re()
{
    json_init
    json_add_string "method" $cmd
    json_add_string "payload" $jmsg
    json_str=`json_dump`
    echo $json_str
    ubus call xq_info_sync_mqtt send_msg "$json_str"
    return 0
}


# send log update message to RE
call_re_upload_log()
{
    json_init
    json_add_string "method" $cmd
    json_add_string "payload" $jmsg
    json_str=`json_dump`
    echo $json_str
    ubus call xq_info_sync_mqtt send_msg "$json_str"
    return
}

# send log update message to RE
tell_re_do_action()
{
    json_init
    json_add_string "method" "$cmd"
    json_add_string "payload" "$jmsg"
    json_str=`json_dump`
    echo $json_str
    ubus call xq_info_sync_mqtt send_msg "$json_str"
    return
}

OPT=$1
#main
whc_to_re_log "$OPT"

cmd="common_set"
jmsg=""

case $OPT in
    log_upload)
        jmsg="{\"log_upload\":\"log_upload\"}"
        call_re_upload_log $1
        return $?
    ;;
    gw_update)
        newgw="$2"
        jmsg="{\"newgw\":\"$newgw\"}"
    ;;

    action)
        json_init
        json_add_string "action" $2
        json_str=`json_dump`
        jmsg=$json_str

        whc_to_re_log "$2"
        tell_re_do_action "$2"
        return $?
    ;;

    test)
        whc_to_re_log "=============== common api test "
        return $?
    ;;
    whc_sync)
        cmd="whc_sync"
        jmsg=`mesh_cmd syncbuf`
    ;;
    webpasswd_update)
        cmd="webpasswd_update"
        jmsg=""
    ;;
    *)
        my_usage
        return 0
    ;;
esac

notify_re
return $?

