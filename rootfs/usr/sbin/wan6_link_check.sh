#!/bin/sh

. /lib/functions/network.sh
. /lib/miwifi/miwifi_functions.sh

ipv6_conn_status=0  #0:disconnected, 1:connected

sec_list=$(uci show ipv6 | grep "ipv6.wan6[_0-9]*=wan" | awk -F"[.|=]" '{print $2}')
for sec in $sec_list; do
    wan6_iface="$sec"
    dedicated=$(util_network_dedicated_get "ipv6" $wan6_iface)
    [ "$dedicated" != "1" ] && {
        if network_is_up "$wan6_iface"; then
            network_get_gateway6 ip6gw "$wan6_iface"
            [ -n "$ip6gw" ] && {
                ipv6_conn_status=1
                break
            }
        fi
    }
done

exit "$ipv6_conn_status"
