#!/bin/sh
# Copyright (C) 2014 Xiaomi

#
# $1 = opt. open/close
# usage:
#      lanap_mode.sh open/close
#
bridgeap_connect_init() { return 0; }
bridgeap_connect_deinit() { return 0; }
util_plugin_restart() { return 0; }

. /lib/functions.sh
. /lib/miwifi/miwifi_core_libs.sh

usage() {
    echo "usage:"
    echo "    lanap_mode.sh opt=open/close/check_gw"
    echo "    example1:  lanap_mode.sh open"
    echo "    example2:  lanap_mode.sh close"
    echo "    example2:  lanap_mode.sh check_gw"
}

bridgeap_logger()
{
    logger -t bridgeap "$*"
}

#return value 1: gw ip unreachable;
#return value 0: gw ip exists
bridgeap_check_gw()
{
    local bridgeap_gw_ip

    bridgeap_gw_ip=$(uci get network.lan.gateway)
    bridgeap_logger "current gateway ip $bridgeap_gw_ip"
    [ -z "$bridgeap_gw_ip" ] && return 0

    if arping "$bridgeap_gw_ip" -q -I br-lan -c 3; then
        bridgeap_logger "current gateway ip $bridgeap_gw_ip, gw ip exists."
        return 0
    else
        bridgeap_logger "current gateway ip $bridgeap_gw_ip, gw ip unreachable."
        return 1
    fi
}

# return value 1: not ap mode
# return value 0: ap mode;
bridgeap_check_apmode()
{
    local network_apmode

    network_apmode=$(uci get xiaoqiang.common.NETMODE)
    bridgeap_logger "network apmode $network_apmode."
    [ "$network_apmode" = "lanapmode" ] && return 0

    bridgeap_logger "network apmode $network_apmode false."
    return 1
}

# add timer task to crontab
# eg.
# bridgeap mode gateway check
# */1 * * * * /usr/sbin/lanap_mode.sh check_gw
bridgeap_check_gw_stop()
{
   grep -v "/usr/sbin/lanap_mode.sh check_gw" /etc/crontabs/root > /etc/crontabs/root.new
   mv /etc/crontabs/root.new /etc/crontabs/root
   /etc/init.d/cron restart
}

bridgeap_check_gw_start()
{
   grep -v "/usr/sbin/lanap_mode.sh check_gw" /etc/crontabs/root > /etc/crontabs/root.new
   echo "*/1 * * * * /usr/sbin/lanap_mode.sh check_gw" >> /etc/crontabs/root.new
   mv /etc/crontabs/root.new /etc/crontabs/root
   /etc/init.d/cron restart
}

ipv6_autocheck_clear_result() {
    local wan6_iface_list=$(uci -q show ipv6 | grep "ipv6.wan6[_0-9]*.automode='1'" | awk -F"[.|=]" '{print $2}' | xargs echo -n)
    for wan6_iface in $wan6_iface_list; do
        /usr/sbin/ipv6.sh autocheck "$wan6_iface" clear_result &
    done
}

OPT=$1


if [ $# -ne 1 ]; then
    usage
    exit 1
fi

case $OPT in
    connect)
        res=1

        lanap_pre_connect

        wan_device="$(uci -q get network.wan.ifname)"
        [ "br-internet" != "$wan_device" ] && wan_device=$(port_map iface service wan)
        [ -n "$wan_device" ] && {
            ubus call network.interface.wan up
            /usr/sbin/dhcp_apclient.sh start "$wan_device"
            res=$?
        }

        lanap_post_connect "$res"
        exit $res
    ;;

    open)
        ifdown vpn

        lanap_open
        /etc/init.d/miqos stop
        /usr/sbin/port_service restart
        /etc/init.d/ipv6 ip6_fw close
        /etc/init.d/firewall restart
        /etc/init.d/odhcpd stop
        /etc/init.d/dnsmasq stop
        phyhelper restart lan

        #downup wifi to ensure all clients reconnect again
        /sbin/wifi update 1

        #/etc/init.d/wan_check restart
        ubus call wan_check reset &

        /etc/init.d/dnsmasq start
        /usr/sbin/vasinfo_fw.sh off
        /etc/init.d/trafficd restart
        /etc/init.d/xqbc restart
        /etc/init.d/tbusd restart
        /etc/init.d/xiaoqiang_sync start

        # accelleration hook event
        network_accel_hook "lanap" "open"

        bridgeap_check_gw_start

        util_plugin_restart
        [ -f /etc/init.d/minet ] && /etc/init.d/minet restart
        [ -f /etc/init.d/cab_meshd ] && /etc/init.d/cab_meshd restart
        [ -f /etc/init.d/guestwifi_separation ] && /etc/init.d/guestwifi_separation restart

        easymesh_support=$(mesh_cmd easymesh_support)
        if [ "$easymesh_support" = "1" ]; then
            [ -f /etc/init.d/mapd ] && /etc/init.d/mapd restart
            [ -f /etc/init.d/lldpd ] && /etc/init.d/lldpd restart
        fi

        /etc/init.d/mosquitto restart
        /etc/init.d/miwifi-discovery restart
        /etc/init.d/xq_info_sync_mqtt restart
        /etc/init.d/topomon restart
        [ -f /etc/init.d/br_dns ] && /etc/init.d/br_dns start
        [ -f /etc/init.d/bridge_ipv6 ] && /etc/init.d/bridge_ipv6 restart
        [ -f /etc/init.d/local_gw_security ] && /etc/init.d/local_gw_security restart
        [ -x /usr/sbin/ntpsetclock ] && /usr/sbin/ntpsetclock post >/dev/null 2>&1 &

        return $?
    ;;

    close)
        bridgeap_check_gw_stop
        lanap_close
        ipv6_autocheck_clear_result
        [ -f /etc/init.d/bridge_ipv6 ] && /etc/init.d/bridge_ipv6 stop
        /usr/sbin/port_service restart
        /etc/init.d/ipv6 ip6_fw open
        /etc/init.d/firewall restart
        /etc/init.d/odhcpd start
        /etc/init.d/dnsmasq stop

        inittd=$(uci -q get xiaoqiang.common.INITTED)
        mesh_support=$(uci -q get misc.features.supportMesh)
        if [ "$mesh_support" -eq 1 ]; then
            support_meshv4=$(mesh_cmd support_mesh_version 4)
            if [ "$inittd" = "YES" ] && [ "$support_meshv4" = "1" ]; then
                /usr/sbin/mesh_connect.sh init_cap 2
            fi
        fi

        #downup wifi to ensure all clients reconnect again
        /sbin/wifi update 1
        phyhelper restart lan

        ubus call wan_check reset &
        /etc/init.d/dnsmasq restart
        /usr/sbin/vasinfo_fw.sh post_ota
        /etc/init.d/trafficd restart
        /etc/init.d/xqbc restart
        /etc/init.d/xiaoqiang_sync stop
        /etc/init.d/tbusd start
        [ -f /etc/init.d/minet ] && /etc/init.d/minet restart
        [ -f /etc/init.d/cab_meshd ] && /etc/init.d/cab_meshd restart
        /etc/init.d/miqos start

        easymesh_support=$(mesh_cmd easymesh_support)
        if [ "$easymesh_support" = "1" ]; then
            [ -f /etc/init.d/mapd ] && /etc/init.d/mapd restart
            [ -f /etc/init.d/lldpd ] && /etc/init.d/lldpd restart
        fi

        # accelleration hook event
        network_accel_hook "lanap" "close"

        [ -f /etc/init.d/guestwifi_separation ] && /etc/init.d/guestwifi_separation restart

        /etc/init.d/mosquitto restart
        /etc/init.d/miwifi-discovery restart
        /etc/init.d/xq_info_sync_mqtt restart
        /etc/init.d/topomon restart
        /etc/init.d/messagingagent.sh restart
        [ -f /etc/init.d/br_dns ] && /etc/init.d/br_dns stop
        [ -f /etc/init.d/local_gw_security ] && /etc/init.d/local_gw_security restart
        util_plugin_restart
        return $?
    ;;

    check_gw)
        [ "$(uci -q get network.lan.proto)" = "dhcp" ] && return
        # this part is used for "link up/down" "root ap change" check, in those situation
        # gateway/lan/sta ip must be "dhcp renew"
        bridgeap_logger "check apmode."
        bridgeap_check_apmode || exit 0

        bridgeap_logger "check gateway."
        bridgeap_check_gw && exit 0

        # in bridge ap mode and gateway unreachable, we had to run dhcp renew issue;
        # if can't renew ipaddr, script should  exit. otherwise, restart network && lan
        bridgeap_logger "gateway changed, try dhcp renew."
        lan_ipaddr_ori=$(uci -q get network.lan.ipaddr)

        /usr/sbin/dhcp_apclient.sh start br-lan
        lan_ipaddr_now=$(uci -q get network.lan.ipaddr)
        [ "$lan_ipaddr_ori" = "$lan_ipaddr_now" ] && exit 0

        matool --method setKV --params "ap_lan_ip" "$lan_ipaddr_now"
        bridgeap_logger "gateway changed, try lan restart"
        phyhelper restart lan
        bridgeap_logger "gateway changed, lan ip changed from $lan_ipaddr_ori to $lan_ipaddr_now."
        ubus call network reload
        /sbin/wifi update 1
        exit 0
    ;;

    * )
        echo "usage:" >&2
    ;;
esac
