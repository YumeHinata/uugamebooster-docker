#!/bin/sh
# Copyright (C) 2015 Xiaomi
#

HARDWARE=`/sbin/uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE`
JSON_TOOL="/usr/sbin/parse_json"

my_usage()
{
    echo "$0:"
    echo "RE get msg form cap and parse msg do action."
    return;
}

re_do_action_log()
{
    logger -s -p info -t action "$1"
}

parse_json(){  
    value=`echo $1  | sed 's/.*'$2':\([^},]*\).*/\1/'`
    echo $value | sed 's/\"//g'
}

do_sync_led()
{
    # 最近一次设置生效原则：
    # 首次Mesh组网CAP同步后，如果用户单独在RE界面设置，则覆盖原CAP同步的情况；
    # 用户最新在CAP设置了以后，RE按最新设置同步
    # 此处同步为CAP做了修改，因此需要同步，不再判断led_mesh_sync_disabled标志
    orig_led_blue=$(uci -q get xiaoqiang.common.BLUE_LED)
    new_led_blue=$($JSON_TOOL "$DATA_MSG" "blue_led")
    orig_ethled=$(uci -q get xiaoqiang.common.ETHLED)
    new_ethled=$($JSON_TOOL "$DATA_MSG" "ethled")
    orig_xled=$(uci -q get xiaoqiang.common.XLED)
    new_xled=$($JSON_TOOL "$DATA_MSG" "xled")
    
    re_do_action_log "=============== orig: blueled:$orig_led_blue ethled:$orig_ethled xled:$orig_xled"
    re_do_action_log "=============== new: blueled:$new_led_blue ethled:$new_ethled xled:$new_xled"

    # save blue_led
    if [ -n "$new_led_blue" -a "$new_led_blue" != "$orig_led_blue" ]; then
        if [ "$new_led_blue" == "0" ]; then
            led_ctl led_off
        else
            led_ctl led_on
        fi
    fi

    # save ethled
    if [ -n "$new_ethled" -a "$new_ethled" != "$orig_ethled" ]; then
        if [ "$new_ethled" == "0" ]; then
            led_ctl led_off ethled
        else
            led_ctl led_on ethled
        fi
    fi

    # save xled
    if [ -n "$new_xled" -a "$new_xled" != "$orig_xled" ]; then
        if [ "$new_xled" == "0" ]; then
            led_ctl led_off xled
        else
            led_ctl led_on xled
        fi
    fi
}

do_sync_nfc()
{
    local nfc_support="$(uci -q get misc.nfc.nfc_support)"

    if [ "$nfc_support" != "1" ]; then
        re_do_action_log "=============== not support nfc, return."
        return
    fi

    orig_nfc_enable=$(uci -q get nfc.nfc.nfc_enable)
    new_nfc_enable=$($JSON_TOOL "$DATA_MSG" "nfc_enable")
    nfc_config_id=$($JSON_TOOL "$DATA_MSG" "config_id")
    re_do_action_log "=============== orig_nfc_enable: $orig_nfc_enable"
    re_do_action_log "=============== new_nfc_enable: $new_nfc_enable"
    re_do_action_log "=============== nfc_config_id: $nfc_config_id"

    if [ -z "$new_nfc_enable" ]; then
        re_do_action_log "=============== new_nfc_enable is null, do nothing"
        return
    elif [ "$new_nfc_enable" != "$orig_nfc_enable" ]; then
        if [ -z "$(uci -q show nfc)" ]; then
            touch /etc/config/nfc
            uci -q add nfc.nfc=nfc
        fi
        uci -q set nfc.nfc.nfc_enable="$new_nfc_enable"
        uci commit nfc

        [ -f /usr/sbin/nfc.lua ] && /usr/sbin/nfc.lua &
    fi
    uci -q set nfc.nfc.config_id="$nfc_config_id"
    uci commit nfc
}

do_sync_time()
{
    timezone=$($JSON_TOOL  "$DATA_MSG" "timezone")
    index=$($JSON_TOOL  "$DATA_MSG" "index")
    tz_value=$($JSON_TOOL  "$DATA_MSG" "tz_value")
    re_do_action_log "=============== timezone: $timezone"
    re_do_action_log "=============== index: $index"
    re_do_action_log "=============== tz_value: $tz_value"

    # save timezone
    if [ "$timezone" != "" ]; then
        if [ "$index" != "" ]; then
            uci set system.@system[0].timezone=$timezone
            uci set system.@system[0].timezoneindex=$index
            uci commit system

            # restart timezone service to apply
            /etc/init.d/timezone restart
        fi
    fi

    # save time and date, for later use
    #if [ "$time" != "" ]; then
        #time=$($JSON_TOOL  "$DATA_MSG" "time")
        #re_do_action_log "=============== time: $time"
        # XQFunction.forkExec("echo 'ok,xiaoqiang' > /tmp/ntp.status; sleep 3; date -s \""..time.."\"")
        #echo 'ok,xiaoqiang' > /tmp/ntp.status
        #date -s "$time"
    #fi

    return
}

do_set_backhaul_mode()
{
    backhaul_mode=$($JSON_TOOL  "$DATA_MSG" "backhaul_mode")
    re_do_action_log "=============== backhaul_mode: $backhaul_mode"
    uci -q set repacd.WiFiLink.2GIndependentChannelSelectionEnable=$backhaul_mode
    uci commit repacd
    uci -q set xiaoqiang.common.son_no_24backhaul=$backhaul_mode
    uci commit xiaoqiang
    /etc/init.d/repacd restart
    re_do_action_log "=============== call repacd restart."
    return
}
## notify REs with precompose cmd, if re exist&active
# 1. get and validate WHC_RE active in tbus list, exclude repeater & xiaomi_plc
# 2. run tbus cmd



# msg format as follow
#local info = {
#    ["timezone"] = tzone,
#    ["index"] = index,
#}
#local msg = {
#    ["cmd"] = "sync_time",
#    ["msg"] = j_info,
#}

# {"cmd":"sync_time","index":"0","timezone":"CST+12"}
DATA_MSG="$1"
#main
re_do_action_log "get msg: $DATA_MSG"

#parse cmd
cmd=`$JSON_TOOL "$DATA_MSG" "cmd"`
#timezone=`$JSON_TOOL "$DATA_MSG" "timezone"`
re_do_action_log "=============== cmd: $cmd"
case $cmd in
    sync_time)
        re_do_action_log "=============== do cmd: sync_time"
        do_sync_time
        return $?
    ;;

    sync_led)
        re_do_action_log "=============== do cmd: sync_led"
        do_sync_led
        return $?
    ;;

    sync_nfc)
        re_do_action_log "=============== do cmd: sync_nfc"
        do_sync_nfc
        return $?
    ;;

    set_backhaul_mode)
        re_do_action_log "=============== do cmd: set_backhaul_mode"
        do_set_backhaul_mode
        return $?
    ;;
    test)
        re_do_action_log "=============== test "
        return $?
    ;;

    *)
        my_usage
        return 0
    ;;
esac


return $?
