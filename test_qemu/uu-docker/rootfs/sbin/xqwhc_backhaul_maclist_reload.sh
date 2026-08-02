#!/bin/sh

### activate wifi black/white maclist after sync from gateway router / whc_CAP

# this script warm process maclist on wifi ap iface
. /lib/functions.sh

LOGI()
{
    logger -s -p 1 -t "xqwhc_maclist" "$1"
}

__wifi_stalist()
{
    echo -n "`wlanconfig $1 list 2>&1 | grep -Eo "..:..:..:..:..:.." | xargs`"
}

__backhaul_malist_config()
{
    local ifa="$1"
    local policy="$2"
    local maclist="$3"

    iface_index=`uci show wireless|grep -w ifname=\'$ifa\'|awk -F "." '{print $2}'`
    [ "$iface_index" == "" ] && return 1

    uci del wireless.$iface_index.macfilter
    uci del wireless.$iface_index.maclist

    uci set wireless.$iface_index.macfilter="$policy"
    for mac in $maclist; do
        uci -q add_list wireless.$iface_index.maclist="$mac"
    done
    uci commit wireless
}

__maclist_flush()
{
    local ifa="$1"
    iwpriv $ifa maccmd_sec 3
}

__maclist_disable()
{
    local ifa="$1"
    iwpriv $ifa maccmd_sec 0
}

__maclist_active_inactive()
{
    local ifa="$1"
    local policy="$2"
    local maclist="$3"

    if [ "$policy" == "deny" ];then
        iwpriv $ifa maccmd_sec 2

        # add all maclist and process mac DO in assoclist
        for umac in $maclist; do
            umac="`echo -n $umac | sed 'y/ABCDEF/abcdef/'`"

            iwpriv $ifa addmac_sec $umac

            # if umac in assoc list, kick it
            local assoclist="$(__wifi_stalist $ifa)"
            list_contains assoclist $umac && {
                LOGI " $umac in deny maclist, kick it from $ifa "
                iwpriv $ifa  kickmac $umac
            }
        done
    fi
    if [ "$policy" == "allow" ];then
        iwpriv $ifa maccmd_sec 1

        # add all maclist and process mac NOT in assoclist
        for umac in $maclist; do
            iwpriv $ifa addmac_sec $umac
        done

        # if asmac NOT in allow maclist, kick it
        local assoclist="$(__wifi_stalist $ifa)"
        for umac in $assoclist; do
            umac="`echo -n $umac | sed 'y/abcdef/ABCDEF/'`"
            list_contains maclist $umac || {
                LOGI " $umac NOT in allow maclist, kick it from $ifa "
                iwpriv $ifa  kickmac $umac
            }
        done
    fi
}

backhaul_2g_maclist="$3"
backhaul_2g_maclist_format="`echo -n $backhaul_2g_maclist | sed "s/;/ /g"`"
backhaul_2g_macfilter="$4"

backhaul_5g_maclist="$1"
backhaul_5g_maclist_format="`echo -n $backhaul_5g_maclist | sed "s/;/ /g"`"
backhaul_5g_macfilter="$2"

LOGI " 2G backhaul wifi macfilter [$backhaul_2g_macfilter]:[$backhaul_2g_maclist_format] and 5G backhaul wifi macfilter [$backhaul_5g_macfilter]:[$backhaul_5g_maclist_format] "

#mesh_ver3/mesh_ver4 and later version only store macfilter rules, not put into effect
mesh_ver=$(uci -q get xiaoqiang.common.MESH_VERSION)
if [ "$mesh_ver" -gt "2" ]; then
    LOGI "mesh_ver3/mesh_ver4 and later version only store macfilter rules, not put int affect, cur_ver=$mesh_ver"
    exit 0
fi

ifa=`uci -q get misc.backhauls.backhaul_2g_ap_iface`
if [ -n "$ifa" ];then
    __backhaul_malist_config $ifa $backhaul_2g_macfilter "$backhaul_2g_maclist_format"
    __maclist_flush $ifa
    __maclist_disable $ifa
    #if [ "$mesh_ver" -le "2" ]; then
    #    __maclist_active_inactive $ifa $backhaul_2g_macfilter "$backhaul_2g_maclist_format"
    #fi
fi

ifa=`uci -q get misc.backhauls.backhaul_5g_ap_iface`
if [ -n "$ifa" ];then
    __backhaul_malist_config $ifa $backhaul_5g_macfilter "$backhaul_5g_maclist_format"
    __maclist_flush $ifa
    __maclist_disable $ifa
    #if [ "$mesh_ver" -le "2" ]; then
    #    __maclist_active_inactive $ifa $backhaul_5g_macfilter "$backhaul_5g_maclist_format"
    #fi
fi
