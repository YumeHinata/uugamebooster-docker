#!/bin/sh
# Copyright (C) 2013-2019 Xiaomi
# 
# This script run on CAP.
#    dedicate for general process data active push from RE.


XQLOGTAG="xqwhc_cap_common_push"

LOGI()
{
    logger -p user.info -t "$XQLOGTAG" "$1"
}


LOGD()
{
    logger -p user.debug -t "$XQLOGTAG" "$1"
}


jstr="$1"
echo "$jstr"


# TODO user datamsg handler
echo "##### TODO, user common_push handle..."

msg_type="`/usr/sbin/parse_json "$jstr" msgtype`"
msg="`/usr/sbin/parse_json "$jstr" msg`"
# msg_type:
# 1-WifiAuthenFailed
# 2-WifiBlacklisted
# 3-LoginAuthenFailed
case "$msg_type" in
    1|2)
        type="`/usr/sbin/parse_json "$msg" type`"
        data="`/usr/sbin/parse_json "$msg" data`"
        mac="`/usr/sbin/parse_json "$data" mac`"
        dev="`/usr/sbin/parse_json "$data" dev`"
        if [ -n "$type" ] && [ -n "$mac" ] && [ -n "$dev" ]; then
            feedPush "{\"type\":$type,\"data\":{\"mac\":\"$mac\",\"dev\":\"$dev\"}}"
        fi
    ;;
    3)
        type="`/usr/sbin/parse_json "$msg" type`"
        data="`/usr/sbin/parse_json "$msg" data`"
        mac="`/usr/sbin/parse_json "$data" mac`"
        if [ -n "$type" ] && [ -n "$mac" ]; then
            feedPush "{\"type\":$type,\"data\":{\"mac\":\"$mac\"}}"
        fi
    ;;
    *)
        echo "unknown msg_type:$msg_type received"
    ;;
esac






