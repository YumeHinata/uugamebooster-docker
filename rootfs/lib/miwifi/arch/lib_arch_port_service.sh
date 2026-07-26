#!/bin/sh

. /lib/miwifi/arch/lib_arch_accel.sh

arch_ps_rebuild_network() {
    ubus call network reload
    swconfig dev switch1 load network &
}

arch_ps_check_service() {
    local service="$1"

    if [ "$service" = "lag" ]; then
        local lag_enable=$(uci -q get port_service.lag.enable)
        local lag_ports=$(uci -q get port_service.lag.ports)
        local port_2_base_iface=$(uci -q get port_map.2.base_iface)
        if [ "$lag_enable" = "1" ] && [ "$lag_ports" = "1 2" -o "$lag_ports" = "3 4" ]; then
            [ "eth1" = "$port_2_base_iface" ] && return
        else
            [ "eth0" = "$port_2_base_iface" ] && return
        fi
        LIST_SERVICES="lag game iptv wan wan_2"
    fi
}

arch_ps_post_start_service() {
    [ "whc_re" = "$(uci -q get xiaoqiang.common.NETMODE)" ] && {
        # in re mode, the topomon must restart when user change the lag's config
        /etc/init.d/topomon restart
    }
    util_portmap_update
}

arch_ps_setup_wan() {
    local service="$1"
    local wan_port="$2"
    local wan_ifname
    local list_lan_ifname wan_mac

    # reconfig network wan and lan
    wan_mac=$(uci -q get network.$service.macaddr)
    wan_ifname=$(port_map iface port "$wan_port")

    list_lan_ifname=$(uci -q get network.lan.ifname)
    list_lan_ifname=$(echo "$list_lan_ifname" | sed "s/$wan_ifname//g" | xargs)

    uci -q batch <<-EOF
        set network."$service".ifname="$wan_ifname"
        set network."${service/n/n6}".ifname="$wan_ifname"
        set network."macv_${service/n/n6}".ifname="$wan_ifname"
        set network.lan.ifname="$list_lan_ifname"
        set network."${wan_ifname}_dev".macaddr="$wan_mac"
       commit network
	EOF

    # reload network
    ip link set dev "$wan_ifname" address "$wan_mac"
    ubus call network reload
    ubus call network.interface."$service" up
    [ "$(uci -q get miqos.settings.enabled)" = "1" ] && {
        arch_accel_event_qos_update
    }
}

arch_ps_reset_lan() {
    local service="$1"
    local wan_port="$2"
    local wan_ifname list_lan_ifname lan_mac

    [ -z "$wan_port" ] && return

    wan_ifname=$(port_map config get "$wan_port" ifname)
    list_lan_ifname=$(uci -q get network.lan.ifname)
    append list_lan_ifname "$wan_ifname"
    lan_mac=$(uci -q get network.lan.macaddr)
    [ -z "$lan_mac" ] && lan_mac=$(getmac lan)

    # reconfig network
    uci -q batch <<-EOF
        delete network."$service".ifname
        delete network."${service/n/n6}".ifname
        delete network."macv_${service/n/n6}".ifname
        set network.lan.ifname="$list_lan_ifname"
        commit network
	EOF

    # reload network
    ip addr flush dev "$wan_ifname"
    [ -n "$lan_mac" ] && ip link set dev "$wan_ifname" address "$lan_mac"
    echo 1 > /proc/sys/net/ipv6/conf/"$wan_ifname"/disable_ipv6
    ubus call network.interface."$service" down
    ubus call network reload
    util_portmap_update
    [ "$(uci -q get miqos.settings.enabled)" = "1" ] && {
        arch_accel_event_qos_update
    }

    return
}

arch_ps_iptv_config() {
    [ "$(uci -q get miqos.settings.enabled)" = "1" ] && {
        arch_accel_event_qos_update
    }
}
