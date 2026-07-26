#!/bin/sh
# Copyright (C) 2015 Xiaomi
#
. /usr/share/libubox/jshn.sh
. /lib/functions.sh

#2.4G backhaul interface setup
device_2g_name=`uci -q get misc.backhauls.backhaul_2g_ap_iface`
iface_2g_no=
[ -n "$device_2g_name" ] && iface_2g_no=`uci show wireless|grep $device_2g_name|awk -F "." '{print $2}'`
[ -n "$iface_2g_no" ] && {
    maclist_2g="`uci -q get wireless.$iface_2g_no.maclist`"
    maclist_2g_format="`echo -n $maclist_2g | sed "s/ /;/g"`"
    filter_2g="`uci -q get wireless.$iface_2g_no.macfilter`"
}

#5G backhaul interface setup
device_5g_name=`uci get misc.backhauls.backhaul_5g_ap_iface`
iface_5g_no=`uci show wireless|grep $device_5g_name|awk -F "." '{print $2}'`
[ -n "$iface_5g_no" ] && {
    maclist_5g="`uci -q get wireless.$iface_5g_no.maclist`"
    maclist_5g_format="`echo -n $maclist_5g | sed "s/ /;/g"`"
    filter_5g="`uci -q get wireless.$iface_5g_no.macfilter`"
}

#call tbus function to notice device change maclist
if [ -n "$iface_2g_no"  ]; then
    jmsg="{\"policy_2g\":\"${filter_2g}\",\"list_2g\":\"${maclist_2g_format}\",\"policy_5g\":\"${filter_5g}\",\"list_5g\":\"${maclist_5g_format}\"}"
else
    jmsg="{\"policy_5g\":\"${filter_5g}\",\"list_5g\":\"${maclist_5g_format}\"}"
fi
json_init
json_add_string "method" "backhaul_access"
json_add_string "payload" $jmsg
json_str=`json_dump`
echo $json_str
ubus call xq_info_sync_mqtt send_msg  "$json_str"


