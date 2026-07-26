#!/bin/sh
# Copyright (C) 2015 Xiaomi
#
. /usr/share/libubox/jshn.sh
. /lib/functions.sh
section_cb(){
    config_get device $1 device
    if [ x$device = x$device_name ]
    then
	echo $1
	return
    fi
}
wifiap_interface_find_by_device()
{
    config_load wireless
    config_foreach section_cb wifi-iface
}

#default interface num 1
#2.4G interface setup
device_name=`uci get misc.wireless.if_2G`
iface_no=`wifiap_interface_find_by_device $device_name`
[ "$iface_no" == "" ] && return 1

ifname_2g=`uci -q get misc.wireless.ifname_2G`
iface_index=`uci show wireless |grep -w "ifname=\'$ifname_2g\'" |awk -F"." '{print $2}'`
[ -z "$iface_index" ] && return 1

maclist="`uci -q get wireless.$iface_index.maclist`"
maclist_format="`echo -n $maclist | sed "s/ /;/g"`"
filter="`uci -q get wireless.$iface_index.macfilter`"

# add for D01, use new method
auth="`uci -q get devicelist.settings.auth`"
level="`uci -q get devicelist.settings.level`"
HARDWARE=`/sbin/uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE`

if [ "$filter" = "deny" ]; then
    policy=2
elif [ "$filter" = "allow" ]; then
    policy=1
else
    policy=0
fi

#add for repeater mode
tbus list | grep -v netapi | grep -v master | while read a
do
        #call tbus function to notice device change maclist
        timeout -t 2 tbus call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\"}"
done


#add for mesh
json_init

if [ "$HARDWARE" == "D01" -o "$HARDWARE" == "R3600" -o "$HARDWARE" == "RM1800" ]; then
    if [ "$level" != "" -a  "$auth" != "" ]; then
        jmsg="{\"policy\":${policy},\"list\":\"${maclist_format}\",\"level\":${level},\"auth\":${auth}}"
        json_add_string "method" "access"
        json_add_string "payload" $jmsg
        json_str=`json_dump`
        echo $json_str
            logger -p info -t maclist "set both auth:$auth level:$level"
        ubus call xq_info_sync_mqtt send_msg  "$json_str"
    elif [ "$level" != "" ]; then
        jmsg="{\"policy\":${policy},\"list\":\"${maclist_format}\",\"level\":${level}}"
        json_add_string "method" "access"
        json_add_string "payload" $jmsg
        json_str=`json_dump`
        echo $json_str
            logger -p info -t maclist "set only level:$level"
        ubus call xq_info_sync_mqtt send_msg  "$json_str"
    elif [ "$auth" != "" ]; then
        jmsg="{\"policy\":${policy},\"list\":\"${maclist_format}\",\"auth\":${auth}}"
        json_add_string "method" "access"
        json_add_string "payload" $jmsg
        json_str=`json_dump`
        echo $json_str
            logger -p info -t maclist "set only auth:$auth"
        ubus call xq_info_sync_mqtt send_msg  "$json_str"
    else
        #call tbus function to notice device change maclist
        jmsg="{\"policy\":${policy},\"list\":\"${maclist_format}\"}"
        json_add_string "method" "access"
        json_add_string "payload" $jmsg
        json_str=`json_dump`
        echo $json_str
        ubus call xq_info_sync_mqtt send_msg  "$json_str"
    fi
else
    #call tbus function to notice device change maclist
    jmsg="{\"policy\":${policy},\"list\":\"${maclist_format}\"}"
    json_add_string "method" "access"
    json_add_string "payload" $jmsg
    json_str=`json_dump`
    echo $json_str
    ubus call xq_info_sync_mqtt send_msg  "$json_str"
fi

