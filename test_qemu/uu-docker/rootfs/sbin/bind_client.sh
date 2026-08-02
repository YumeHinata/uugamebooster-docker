#!/bin/sh
# Copyright (C) 2016 Xiaomi
#
#set -x

. /lib/functions.sh
. /usr/share/libubox/jshn.sh

bind_log()
{
    echo "$1"
    local date=$(date)
    logger -p warn "bind_client[$date]: $1"
}

run_with_lock(){
    {
        bind_log "$$, ====== TRY locking......"
        flock -x -w 10 1001
        [ $? -eq "1" ] && { bind_log "$$, ===== GET lock failed. exit 1" ; exit 1 ; }
        bind_log "$$, ====== GET lock to RUN."
        $@ 1001>&-
        bind_log "$$, ====== END lock to RUN."
    } 1001<>/var/run/re_bind.lock
}

# parse json code
parse_json()
{
    # {"code":0,"data":{"bind":1,"admin":499744955}}
    echo "$1" | awk -F "$2" '{print$2}'|awk -F "" '{print $3}'
}

# do on client, after get his signatures
check_my_bind_status()
{
    local bind_status code bind

    if ! bind_status=$(timeout -t 5 matool --method api_call --params "/device/minet_get_bindinfo" 2>/dev/null);
    then
        echo "[matool --method minet_get_bindinfo] error!"
        return 2
    fi
    # {"code":0,"data":{"bind":1,"admin":499744955}}
    code=$(parse_json "$bind_status" "code")
    if [ -n "$code" ] && [ "$code" -eq 0 ]; then
        #bind_log "code: $code"
        bind=$(parse_json "$bind_status" "bind")
        bind_log "my bind_status: $bind"
        return "$bind"
    else
        return 0
    fi
}

bind_remote_client()
{
    local HardwareVersion="$1"
    local SN="$2"
    local ROM="$3"
    local IP="$4"
    local RECORD="$5"
    local Channel="$6"
    local signature deviceID location server
    #local Channel=$(uci get /usr/share/xiaoqiang/xiaoqiang_version.version.CHANNEL)
    # 1. get signature for client
    #bind_log "HardwareVersion: $HardwareVersion"
    #bind_log "SN: $SN"
    #bind_log "ROM: $ROM"
    #bind_log "IP: $IP"
    #bind_log "client Channel: $Channel"
    # get signatures for client
    # matool --method sign --params "{SN}&{HardwareVersion}&{ROM}&{Channel}"
    #matool --method sign --params "{$SN}&{$HardwareVersion}&{$ROM}&{$Channel}"
    bind_log "matool --method sign --params \"$SN&$HardwareVersion&$ROM&$Channel\""
    if ! signature=$(timeout -t 5 matool --method sign --params "$SN&$HardwareVersion&$ROM&$Channel" 2>/dev/null);
    then
        echo "[matool --method sign] error!"
        return 1
    fi
    #bind_log "get signature: $signature"

    # 2. sent my device ID and signature to client
    #tbus call 192.168.31.73 bind '{"action":1,"msg":"hello"}'
    #signature="582e7ad35a1479f9f3e2cb7f0855b5549b0e1501"
    #IP="192.168.31.73"
    deviceID=$(uci get messaging.deviceInfo.DEVICE_ID 2>/dev/null)
    #bind_log "get deviceID: $deviceID"

    #bind_log "CMD: timeout -t 10 tbus call $IP bind  {\"record\":\"$RECORD\",\"deviceID\":\"$deviceID\",\"sign\":\"$signature\"}"
    #local ret=$(timeout -t 10 tbus call $IP bind {\"record\":\"$RECORD\",\"deviceID\":\"$deviceID\",\"sign\":\"$signature\"})
    #bind_log "client bind return: $ret"
    #if [ $? -ne 0 ];
    #then
    #    bind_log "[tbus call $IP bind] error!"
    #    return 1
    #fi
    #bind_log "timeout -t 5 tbus call $IP bind "\'{\"action\":1,\"deviceID\":\"$deviceID\",\"sign\":\"$signature\"}\'""

    # get location and server
    location=$(nvram get CountryCode)
    server=$(uci -q get country_mapping."$location".region)

    jmsg="{\"record\":\"$RECORD\",\"deviceID\":\"$deviceID\",\"sign\":\"$signature\",\"location\":\"$location\",\"server\":\"$server\"}"
    json_add_string "method" "bind"
    json_add_string "payload" "$jmsg"
    json_str=$(json_dump)
    echo "$json_str"
    ubus call xq_info_sync_mqtt send_msg "$json_str"

    if [ "$(mesh_cmd easymesh_support)" = "1" ]; then
        #mac字段复用IP字段 easymesh为二层通信
        easymesh_msg='{"mac":"'$IP'","record":"'$RECORD'","device_id":"'$deviceID'","sign":"'$signature'"}'
        ubus -t3 call mapd bind_agent "$easymesh_msg"
        bind_log "easymesh bind msg:$easymesh_msg"
    fi
}

# do on client, after get his signatures
bind_me()
{
    #matool --method joint_bind --params {device_id} {sign}
    local device_id="$1"
    local sign="$2"
    local record="$3"
    local location="$4"
    local server="$5"

    bind_log "bind me: $device_id $sign $record $location $server"
    # check init flag first
    INIT_FLAG="$(uci get xiaoqiang.common.INITTED 2>/dev/null)"
    if [ "${INIT_FLAG}" != 'YES' ]; then
        bind_log "router not init, jump bind."
        return 0
    fi

    # check bind record
    bind_record="$(uci get bind.info.record 2>/dev/null)"
    if [ "${bind_record}" = "$record" ]; then
        bind_log "re already bind, jump bind"
        return 0
    fi

    # change location of RE to be the same as master
    if [ -n "$location" ] && [ -n "$server" ]; then
        bind_log "set location: $location  $server"
        lua -e "require('xiaoqiang.util.XQSysUtil').setLocation('$location', true, '$server')"
        sleep 3
    fi

    # do join bind
    bind_log "get master deviceID: $device_id"
    bind_log "get master sign: $sign"
    bind_log "get master record: $record"
    bind_log "cmd: timeout -t 5 matool --method joint_bind --params $device_id $sign 2>/dev/null"

    if ! timeout -t 5 matool --method joint_bind --params "$device_id" "$sign" 2>/dev/null; then
        bind_log "[method joint_bind] error!"
        return 0
    else
        # update bind record according to master bind info.
        uci set bind.info.status=1
        uci set bind.info.record="$record"
        uci set bind.info.remoteID="$device_id"
        uci commit bind
        bind_log "[method joint_bind] ok!"

        uci set wireless.miot_2G.bindstatus=1
        uci commit wireless

        # push re on bind success
        sh /usr/sbin/topomon_action.sh push re &

        [ -x "/usr/bin/miio_bind.sh" ] && /usr/bin/miio_bind.sh

        local userSwitch="$(uci -q get wireless.miot_2G.userswitch)"
        # if platform is qca,then radio is wifi0 or wifi1.else, other.
        local radio="$(uci -q get misc.wireless.if_2G)"

        if [ "$userSwitch" != "0" ]; then
            if [ "$radio" = "wifi0" ]; then
                hostapd_cli -i wl13 -p /var/run/hostapd-wifi0 enable
            elif [ "$radio" = "wifi1" ]; then
                hostapd_cli -i wl13 -p /var/run/hostapd-wifi1 enable
            else
                ifconfig wl13 up
            fi
            /usr/sbin/sysapi miot
        fi

        # push xqwhc setkv on bind success
        logger -p 1 -t "xqwhc_push" " RE push xqwhc kv info on bind success"
        sh /usr/sbin/xqwhc_push.cron now &
        sh /usr/sbin/topomon_action.sh push re &
    fi

    local deviceID="$(uci get messaging.deviceInfo.DEVICE_ID 2>/dev/null)"
    bind_log "get new deviceID: $deviceID"
    # check new status
    check_my_bind_status
}


OPT=$1
#bind_log "OPT: $OPT"

json_init

echo  $OPT
case $OPT in
    bind_remote)
        #1. check bind status
        check_my_bind_status
        if [ $? -eq 1 ]; then
            bind_remote_client "$2" "$3" "$4" "$5" "$6" "$7"
        fi
        return 0
        ;;
    bind_me)
        #check_my_bind_status
        # just do when not binded
        #if [ $? -eq 0 ]; then
        #    bind_me "$2" "$3" "$4"
        #fi
        # bind all the time
        run_with_lock bind_me "$2" "$3" "$4" "$5" "$6"

        return 0
        ;;
    *)
        return 0
        ;;
esac
