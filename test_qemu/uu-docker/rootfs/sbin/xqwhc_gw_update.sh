#!/bin/sh

### this script run on WHC_RE, process gateway update notify

LOGI()
{
    logger -s -p 1 -t "xqwhc_gw_update" "$1"
}

mesh_version=$(uci -q get xiaoqiang.common.MESH_VERSION)
cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)
if [ "$ap_mode" = "whc_cap" ] || [ "$mesh_version" -ge "2" -a "$ap_mode" = "lanapmode" -a "$cap_mode" = "ap" ]; then
    LOGI " error, xqwhc_gw_update scr ONLY call on RE!"
    exit 1
fi

[ $mesh_version -gt 1 ] && {
    . /lib/mimesh/mimesh_public.sh
    . /lib/mimesh/mimesh_stat.sh
} || {
    . /lib/xqwhc/xqwhc_public.sh
    . /lib/xqwhc/network_lal.sh
}

TOUT=10;   # consider a MAX delay on CAP notify all REs
RETRY_MAX=10


NEED_REBOOT=1   # as for now in miwifi, gateway update need a reboot

__restore_cfg()
{
    uci -q set network.lan.proto=dhcp
    uci -q delete network.lan.ipaddr
    uci -q delete network.lan.netmask
    uci -q delete network.lan.gateway
    uci -q delete network.lan.dns
    uci commit network
    sync
}

__reload_lan()
{
    LOGI " reload lan to launch a dhcp discover"

    ## reset dhcpc to send new discovery
    ########ip addr del 192.168.31.247 dev br-lan
    killall udhcpc
    /etc/init.d/network reload_fast
    sleep 2 # delay to wait dhcp offer

}

main()
{
    ## old gateway
    [ $mesh_version -gt 1 ] && {
        gw_pre="$(mimesh_get_gw_ip)"
    } || {
        gw_pre="$(nlal_get_gw_ip)"
    }
    LOGI " pre gateway ip=$gw_pre"

    gw_cur="$1"
    [ "$gw_cur" = "$gw_pre" ] && {
        LOGI " gateway no change, ignore!"
    }

    if [ "$NEED_REBOOT" -gt 0 ]; then
        LOGI " confirm to update gateway, rebooting "
        __restore_cfg
        ((reboot &); sleep 20; reboot -f) &
        return 0
    fi

    # reset lan to launch udhcpc discover,
    for ii in `seq 1 1 $RETRY_MAX`; do
        sleep $TOUT
        __restore_cfg
        __reload_lan

        [ $mesh_version -gt 1 ] && {
            gw_cur="$(mimesh_get_gw_ip)"
        } || {
            gw_cur="$(nlal_get_gw_ip)"
        }

        if [ -z "$gw_cur" ]; then
            LOGI " gateway NO find!"
            continue
        elif [ "$gw_cur" = "$gw_pre" ]; then
            LOGI " gateway STILL pre!"
            continue
        else
            # TODO
            # fork to restart service relay on lanIP.
            break
        fi
    done

    [ $mesh_version -gt 1 ] && {
        /etc/init.d/topomon restart
    } || {
    # we must restart hyfi-bridge.
        /etc/init.d/hyfi-bridging restart
        /etc/init.d/hyd restart
    }
}

main


