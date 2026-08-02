#!/bin/sh

if [ "0" = "$(uci -q get misc.features.ma_push_support)" ]; then
    exit 0
fi

if [ -n "$STA" ]; then
    authorize=$(uci -q get misc.iwevent.authorize)
    if [ "$ACTION" = "AUTHORIZE" -a "$authorize" = "1" ]; then
        feedPush "{\"type\":1,\"data\":{\"mac\":\"$STA\",\"dev\":\"$DEVNAME\"}}"
    elif [ "$ACTION" = "ASSOC" -a "$authorize" != "1" ]; then
        feedPush "{\"type\":1,\"data\":{\"mac\":\"$STA\",\"dev\":\"$DEVNAME\"}}"
    elif [ "$ACTION" = "DISASSOC" ]; then
        feedPush "{\"type\":2,\"data\":{\"mac\":\"$STA\",\"dev\":\"$DEVNAME\"}}"
    elif [ "$ACTION" = "MIC_DIFF" ]; then
        feedPush "{\"type\":14,\"data\":{\"mac\":\"$STA\",\"dev\":\"$DEVNAME\"}}"
    elif [ "$ACTION" = "BLACKLISTED" ]; then
        feedPush "{\"type\":15,\"data\":{\"mac\":\"$STA\",\"dev\":\"$DEVNAME\"}}"
    fi
fi
