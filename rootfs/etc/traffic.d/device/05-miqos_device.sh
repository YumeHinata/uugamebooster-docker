#!/bin/sh

qosflag=$(uci -q get miqos.settings.enabled)
[ "$qosflag" != "1" ] && return 0
force_disabled=$(uci -q get miqos.settings.force_disabled)
[ "$force_disabled" = "1" ] && return 0

ifname_prefix=${IFNAME:0:2}
if [ "$ifname_prefix" = "wl" ]; then
    #EVENT 0-offline, 1-online
    if [ "$EVENT" = "1" ] || [ "$EVENT" = "3" ]; then
        /usr/sbin/miqosc device_in "$MAC"
        /usr/sbin/miqos_ipv6.sh add "$MAC"
    elif [ "$EVENT" = "0" ]; then
        /usr/sbin/miqosc device_out "$MAC"
        /usr/sbin/miqos_ipv6.sh del "$MAC"
    fi
    return 0
fi

if [ -z "$ifname_prefix" ] || [ "$ifname_prefix" = "et" ]; then
    #EVENT 0-offline, 1-online
    if [ "$EVENT" = "1" ] || [ "$EVENT" = "3" ]; then
        /usr/sbin/miqosc device_in 00
        /usr/sbin/miqos_ipv6.sh add "$MAC"
    elif [ "$EVENT" = "0" ]; then
        /usr/sbin/miqosc device_out 00
        /usr/sbin/miqos_ipv6.sh del "$MAC"
    fi
    return 0
fi
