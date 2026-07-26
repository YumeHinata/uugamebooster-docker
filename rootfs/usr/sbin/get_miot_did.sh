#!/bin/sh

times=10
[ -n "$1" ] && times="$1"

mjac_enabled=$(uci -q get miio_ot.ot.mjac_enabled)
if [ "$mjac_enabled" = "1" ]; then
    mjac_did_file="/tmp/mjac_did"
    while true; do
        [ -e "$mjac_did_file" ] && {
            cat "$mjac_did_file"
            exit 0
        }

        [ $times -le 0 ] && exit 0
        ubus send miio_proxy '{ "msg": "{ \"method\": \"local.query_did\" }", "cb": "_sync.mjac_did" }'
        sleep 1
        times=$((times - 1))
    done
else
    bdata get miot_did
fi
