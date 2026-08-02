#! /bin/sh

# this script has three usages:
# 1. start udhcpc client, rent an ip address and other info from a DHCP server.
# 2. a call back script of udhcpc, set DHCP information to /etc/config/network
# 3. restart lan swtich port to trigger client DHCP resending.

usage () {
    echo "$0 start [interface]"
    echo -e "\t default interface is apcli0"
    echo "$0 restart lan"
    echo "$0 help"
    exit 1
}


router_config_backup() {
    local backup_file="/etc/config/.network.mode.router"
    [ -f $backup_file ] || cp /etc/config/network $backup_file
}

setup_interface () {
    [ -z "$ip" ] && exit 1
    netmask="${subnet:-255.255.255.0}"
    mtu="${mtu:-1500}"
    dns="${dns:-$router}"
    ap_hostname_tmp=${vendorinfo:7}
    ap_hostname_tmp=${ap_hostname_tmp%%-*}
    ap_hostname=MiWiFi-${ap_hostname_tmp}-srv

    old_ip=$(uci -q get network.lan.ipaddr)
    old_netmask=$(uci -q get network.lan.netmask)

    country_code=$(bdata get CountryCode)

    uci -q batch <<EOF >/dev/null
        set xiaoqiang.common.ap_hostname=$ap_hostname
        set xiaoqiang.common.vendorinfo=$vendorinfo
        commit xiaoqiang
        set network.lan=interface
        set network.lan.type=bridge
        set network.lan.proto=static
        set network.lan.ipaddr=$ip
        set network.lan.netmask=$netmask
        set network.lan.gateway=$router
        set network.lan.mtu=$mtu
        del network.lan.dns
EOF
    if [ "${country_code:-CN}" != "CN" ]; then
        # for international version, disable vpn, and will recover it when switch to router mode
        uci set network.vpn.disabled=1
    else
        # for china version, delete vpn config, will not recover it when switch to router mode
        uci del network.vpn
    fi

    for d in $dns
    do
        uci -q add_list network.lan.dns=$d
    done
    uci commit network

    if [ "$old_ip" != "$ip" ]; then
        /usr/sbin/ip_conflict.sh br-lan

        netmode=$(uci -q get xiaoqiang.common.NETMODE)
        if [ "$netmode" = "lanapmode" -o "$netmode" = "wifiapmode" ]; then
            /usr/sbin/ip_changed.sh lan "$old_ip" "$old_netmask" "$ip" "$netmask"
        fi
    fi

    exit 0
}

start_dhcp () {
    local hostname=$(uci -q get misc.hardware.dhcp_hostname)
    [ -z "$hostname" ] && {
        local  model=$(uci -q get misc.hardware.model)
        [ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)
        hostname="MiWiFi-$model"
    }

    local mypath=`dirname $0`
    cd $mypath >/dev/null
    local abspath=`pwd`
    cd - >/dev/null
    local ifname="$1"
    local wan_mac=$(getmac wan)
    local client_id="01:$wan_mac"
    local res

    local i=1
    while [[ $i -le 10 ]]
    do
        ifconfig $ifname >/dev/null 2>&1
        [ $? -eq 0 ] && break
        i=`expr $i + 1`
        sleep 1
    done

    [ -x "/etc/init.d/local_gw_security" ] && /etc/init.d/local_gw_security stop
    udhcpc -q -s $abspath/`basename $0` -t 5 -T 2 -i "$ifname" -x hostname:"$hostname" -x 0x3d:$client_id >/dev/null 2>&1
    res="$?"
    [ -x "/etc/init.d/local_gw_security" ] && /etc/init.d/local_gw_security start
    exit "$res"
}

restart_lan () {
    exec /sbin/phyhelper restart lan
    return $?
}

case "$1" in
    start)
        start_dhcp "$2"
    ;;
    restart)
        restart_lan
        exit $?
    ;;
    renew|bound)
        #if xq already in ap mode,it don't need to backup route config file
        ap_mode=`uci get network.ap_mode 2>/dev/null`
        [ "$ap_mode" != "bridgeap" ] && router_config_backup

        setup_interface
    ;;
    *)
        usage
    ;;
esac
