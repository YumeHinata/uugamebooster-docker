#!/bin/sh

. /lib/functions.sh
. /lib/miwifi/lib_ipv6.sh


UCI_GET="uci -q get"
UCI_SHOW="uci -q show"

loginfo() {
    local msg="$1"
    local prio="$2"
    [ -z "$msg" ] && return 0

    if [ -z "$prio" ]; then
        logger -t "ipv6.sh[${$}]" "$msg"
    else
        logger -p "$prio" -t "ipv6.sh[${$}]" "$msg"
    fi
}

logerr() {
    loginfo "$msg" "9"
}

usage() {
    $0 <action> [parm1] [param2] ...
}

ipv6_reload_network () {
    local wan6_iface="$1"
    local ipv6_mode="$2"
    local wan_iface=${wan6_iface/6/}
    local wan_proto=$($UCI_GET network.$wan_iface.proto)
    local need_reload=1
    local netmode=$($UCI_GET xiaoqiang.common.NETMODE)

    [ -z "$ipv6_mode" -a "$wan6_iface" != "all" ] && {
        $UCI_SHOW ipv6.$wan6_iface > /dev/null 2>&1
        [ "$?" != "0" ] && {
            logerr "ipv6_reload ipv6.$wan6_iface doesn't exist."
            return
        }

        ipv6_mode=$($UCI_GET ipv6.$wan6_iface.mode)
    }

    [ -z "$wan6_iface" ] && {
        logger "ipv6_reload_network params error."
        return
    }

    if [ "$wan6_iface" = "all" ]; then
        local sec_list=$($UCI_SHOW ipv6 | grep "ipv6.wan6[_0-9]*=wan" | awk -F"[.|=]" '{print $2}')
        for sec in $sec_list; do
            local iface="$sec"
            local mode=$(uci -q get ipv6.$sec.mode)
            [ "$mode" != "off" ] && {
                need_reload=0
                #up-down ipv6 interface: trigger hotplug
                ifup "$iface" >/dev/null 2>&1
                [ "$mode" = "pppoev6" ] && ifup "${iface}ppp" >/dev/null 2>&1
                [ "$wan_proto" = "pppoe" ] && ifup "${iface/6/}" >/dev/null 2>&1
            }
        done
    else
        [ "$ipv6_mode" != "off" ] && {
            need_reload=0
            #up-down ipv6 interface: trigger hotplug
            if [ "$netmode" != "lanapmode" ]; then
                ifup "$wan6_iface" >/dev/null 2>&1
                [ "$ipv6_mode" = "pppoev6" ] && ifup "${wan6_iface}ppp" >/dev/null 2>&1
                [ "$wan_proto" = "pppoe" ] && ifup "$wan_iface" >/dev/null 2>&1
            fi
        }
    fi

    # for ipv6 off mode
    [ "$need_reload" = "1" ] && ubus call network reload

    /etc/init.d/dnsmasq restart
}

ipv6_reload_firewall()
{
    local wan6_iface="$1"
    local ipv6_mode="$2"
    local reload=0

    local network_list=$(uci -q get firewall.@zone[1].network)
    local islist=$(uci -q show firewall.@zone[1].network | grep -v -q "$network_list" && echo 1)

    if [ "$ipv6_mode" = "passthrough" ] ; then
        list_contains network_list "$wan6_iface" && {
            if [ "$islist" = "1" ]; then
                uci -q batch <<-EOF
                    del_list firewall.@zone[1].network=${wan6_iface}
                    commit firewall
EOF
            else
                local new_network_list=""
                for iface in $network_list; do
                    [ "$iface" != "$wan6_iface" ] && append new_network_list "$iface"
                done
                uci -q batch <<-EOF
                    set firewall.@zone[1].network="${new_network_list}"
                    commit firewall
EOF
            fi
            reload=1
        }
    else
        list_contains network_list "$wan6_iface" || {
            if [ "$islist" = "1" ]; then
                uci -q batch <<-EOF
                    add_list firewall.@zone[1].network=${wan6_iface}
                    commit firewall
EOF
            else
                append network_list "$wan6_iface"
                uci -q batch <<-EOF
                    set firewall.@zone[1].network="${network_list}"
                    commit firewall
EOF
            fi

            reload=1
        }
    fi

    [ "$reload" -eq 1 ] && /etc/init.d/firewall reload
}

odhcpd_status_process() {
    local status="$1"

    if [ "$status" = "enabled" ]; then
        local odhcpd_exist=$(ps | grep odhcpd | grep -v grep | wc -l)
        [ "$odhcpd_exist" = "0" ] && {
            /etc/init.d/odhcpd restart
        }
    else
        /etc/init.d/odhcpd stop
    fi
}

passthrough_module_process() {
    local status="$1"

    [ "$status" = "disabled" ] && {
        [ -d /sys/module/passthrough ] && rmmod passthrough >/dev/null 2>&1
    }
}

add_relay_fw_rule() {
    local rule=$($UCI_SHOW firewall | grep 'Allow-DHCPv6-Relay' | cut -d '.' -f 2)
    [ -z "$rule" ] && {
        uci -q batch <<EOF
            set firewall.dhcpv6_relay=rule
            set firewall.dhcpv6_relay.name='Allow-DHCPv6-Relay'
            set firewall.dhcpv6_relay.src='wan'
            set firewall.dhcpv6_relay.proto='udp'
            set firewall.dhcpv6_relay.src_port='547'
            set firewall.dhcpv6_relay.dest_port='547'
            set firewall.dhcpv6_relay.family='ipv6'
            set firewall.dhcpv6_relay.target='ACCEPT' 
            commit firewall
EOF
    }
    ip6tables -C zone_wan_input -p udp --dport 547 --sport 547 -m comment --comment "!fw3: Allow-DHCPv6-relay" -j ACCEPT >/dev/null 2>&1
    [ "$?" != "0" ] && {
        ip6tables -A zone_wan_input -p udp --dport 547 --sport 547 -m comment --comment "!fw3: Allow-DHCPv6-relay" -j ACCEPT
    }
}

del_relay_fw_rule() {
    local rule=$($UCI_SHOW firewall | grep 'Allow-DHCPv6-Relay' | cut -d '.' -f 2)
    [ -n "$rule" ] && {
        uci -q batch <<EOF
        delete firewall.$rule
        commit firewall
EOF
    }
    ip6tables -D zone_wan_input -p udp --dport 547 --sport 547 -m comment --comment "!fw3: Allow-DHCPv6-relay" -j ACCEPT
}

relay_fw_process() {
    local status="$1"

    if [ "$status" = "enabled" ]; then
        add_relay_fw_rule
    else
        del_relay_fw_rule
    fi
}

module_status_process() {
    . /lib/miwifi/miwifi_functions.sh

    local odhcpd_status="disabled"
    local relay_status="disabled"
    local passthrough_status="disabled"
    local sec_list=$($UCI_SHOW ipv6 | grep "ipv6.wan6[_0-9]*=wan" | awk -F"[.|=]" '{print $2}')
    for sec in $sec_list; do
        local ipv6_mode=$(uci -q get ipv6.$sec.mode)
        local dedicated=$(util_network_dedicated_get "ipv6" $wan6_iface)
        case $ipv6_mode in
            "relay")
                relay_status="enabled";;
            "passthrough")
                passthrough_status="enabled";;
            *);;
        esac

        [ "$ipv6_mode" != "off" -a "$ipv6_mode" != "passthrough" -a "$dedicated" != "1" ] && {
            odhcpd_status="enabled"
        }
    done

    relay_fw_process "$relay_status"
    passthrough_module_process "$passthrough_status"
    odhcpd_status_process "$odhcpd_status"
}

ipv6_reload() {
    local wan6_iface="$1"

    [ "${wan6_iface:0:4}" != "wan6" ] && {
        logger "ipv6_reload wan6_iface:$wan6_iface error."
        return
    }

    local wan_iface="wan"
    local idx=${wan6_iface##*_}
    [ "$idx" != "$wan6_iface" ] && {
        wan_iface="${wan_iface}_$idx"
    }

    $UCI_SHOW ipv6.$wan6_iface > /dev/null 2>&1
    [ "$?" != "0" ] && {
        logger "ipv6_reload ipv6.$wan_iface doesn't exist."
        return
    }

    local ipv6_mode=$($UCI_GET ipv6.$wan6_iface.mode)
    local wan_ifname=$($UCI_GET network.$wan_iface.ifname)
    [ -z "$ipv6_mode" ] && ipv6_mode="off"

    [ "$ipv6_mode" != "passthrough" ] && {
        brctl delif br-lan "${wan_ifname}_6" > /dev/null 2>&1
        [ -e "/usr/bin/pconfig" ] && pconfig del "${wan_ifname}_6" > /dev/null 2>&1
    }

    ipv6_reload_network "$wan6_iface" "$ipv6_mode"
    ipv6_reload_firewall "$wan6_iface" "$ipv6_mode"

    module_status_process

    return 0
}

ipv6_old_cfg_to_v2() {
    local ver=$($UCI_GET ipv6.globals.ver)
    #[ -n "$ver" ] && return

    local disabled
    local wan_ipv6=1
    local automode=0
    local wan_iface="wan"
    local wan6_iface="wan6"
    local ipv6_mode=$($UCI_GET ipv6.wan6.mode)
    local ipv6_new_mode="$ipv6_mode"
    local ip6addr=$($UCI_GET ipv6.settings.ip6addr)
    local ip6gw=$($UCI_GET ipv6.settings.ip6gw)
    local ip6prefix=$($UCI_GET ipv6.settings.ip6prefix)
    local ip6assign=$($UCI_GET ipv6.settings.ip6assign)
    local peerdns=$($UCI_GET ipv6.dns.peerdns)
    local dns_list=$($UCI_GET ipv6.dns.dns)
    local ifname=$($UCI_GET network.wan.ifname)
    local wan_proto=$($UCI_GET network.wan.proto)
    local ipv6_firewall=$($UCI_GET ipv6.settings.firewall)

    [ "$wan_proto" = "pppoe" ] && {
        disabled=1
        wan_ipv6="auto"
    }

    case "$ipv6_mode" in
        "native" | "nat")
            automode=1
            ipv6_new_mode="native"
            uci -q batch <<EOF
            delete network.wan6
            delete network.wan_6
            set network.${wan_iface}.ipv6=${wan_ipv6}
            set network.${wan6_iface}=interface
            set network.${wan6_iface}.proto=dhcpv6
            set network.${wan6_iface}.ifname=${ifname}
            set network.${wan6_iface}.reqaddress=try
            set network.${wan6_iface}.reqprefix=auto
            set network.${wan6_iface}.wantype=eth
            set network.${wan6_iface}.disabled=${disabled}
            commit network
EOF
            ;;
        "passthrough")
            automode=1
            ipv6_new_mode="pi_relay"
            uci -q batch <<EOF
            delete network.wan6
            delete network.wan_6
            set network.${wan_iface}.ipv6=${wan_ipv6}
            set network.${wan6_iface}=interface
            set network.${wan6_iface}.proto=dhcpv6
            set network.${wan6_iface}.ifname=${ifname}
            set network.${wan6_iface}.reqaddress=try
            set network.${wan6_iface}.reqprefix=auto
            set network.${wan6_iface}.wantype=eth
            set network.${wan6_iface}.disabled=${disabled}
            commit network
EOF
            ;;
        "static")
            uci -q batch <<EOF
            delete network.wan6
            delete network.wan_6
            set network.${wan_iface}.ipv6=${wan_ipv6}
            set network.${wan6_iface}=interface
            set network.${wan6_iface}.proto=static
            set network.${wan6_iface}.ifname=${ifname}
            set network.${wan6_iface}.ip6addr=${ip6addr}
            set network.${wan6_iface}.ip6gw=${ip6gw}
            set network.${wan6_iface}.ip6prefix=${ip6prefix}
            set network.${wan6_iface}.wantype=eth
            set network.${wan6_iface}.disabled=${disabled}
            commit network
EOF
            ;;
        *)
            uci -q batch <<EOF
            delete network.wan6
            delete network.wan_6
            commit network
EOF
            ;;
    esac

    [ "$ipv6_mode" != "off" -a "$peerdns" = "0" -a -n "$dns_list" ] && {
        local dns1=${dns_list%,*}
        local dns2=$(echo $dns_list | grep ',' | cut -d ',' -f2)
        if [ -n "$dns2" ]; then
            uci -q batch <<EOF
            set network.${wan6_iface}.peerdns=0
            add_list network.${wan6_iface}.dns=${dns1}
            add_list network.${wan6_iface}.dns=${dns2}
            commit network
EOF
        else
            uci -q batch <<EOF
            set network.${wan6_iface}.peerdns=0
            add_list network.${wan6_iface}.dns=${dns1}
            commit network
EOF
        fi
    }

    uci -q batch <<EOF
        delete ipv6.dns
        delete ipv6.settings
        delete dhcp.lan.ra_flags
        set ipv6.globals=globals
        set ipv6.globals.ver=2
        set ipv6.globals.enabled=1
        set ipv6.globals.firewall=${ipv6_firewall}
        set ipv6.wan6=wan
        set ipv6.wan6.mode=${ipv6_new_mode}
        set ipv6.wan6.automode=${automode}
        add_list ipv6.wan6.support_modes='off'
        add_list ipv6.wan6.support_modes='native'
        add_list ipv6.wan6.support_modes='dhcpv6'
        add_list ipv6.wan6.support_modes='pppoev6'
        add_list ipv6.wan6.support_modes='static'
        add_list ipv6.wan6.support_modes='pi_relay'
        set ipv6.wan6.automode_backup='pi_relay'
        set ipv6.wan6.automode_pppoe_backup='pi_relay'
        set ipv6.lan6=lan
        set ipv6.lan6.mode=0
        set network.lan.ip6assign=64
        set dhcp.lan.dhcpv6="server"
        set dhcp.lan.ra="server"
        set dhcp.lan.ra_default="1"
        set dhcp.lan.ra_preference="high"
        set dhcp.lan.ra_maxinterval="20"
        set dhcp.lan.ra_lifetime="1800"
        add_list dhcp.lan.ra_flags=managed-config
        add_list dhcp.lan.ra_flags=other-config
        commit dhcp
        commit ipv6
        commit network
EOF

    if [ "$ipv6_new_mode" = "pi_relay" ]; then
        uci -q batch <<EOF
            set dhcp.wan6=dhcp
            set dhcp.wan6.master="1"
            set dhcp.wan6.ignore="1"
            set dhcp.wan6.ndp="relay"
            set dhcp.wan6.ra_flags="none"
            set dhcp.wan6.interface="wan6"
            set dhcp.lan.ndp="hybrid"
            commit dhcp
EOF
    fi
}

ipv6_cfg_v2_to_new() {
    local subver=$($UCI_GET ipv6.globals.subver)
    [ "$subver" = "1" ] && return

    local wan6_iface="wan6"
    local automode=$($UCI_GET ipv6.wan6.automode)
    local ipv6_mode=$($UCI_GET ipv6.wan6.mode)
    local lan_mode=$($UCI_GET ipv6.lan6.mode)
    local ifname=$($UCI_GET network.wan.ifname)

    [ "$ipv6_mode" = "passthrough" -a "$automode" != "1" ] && {
        lan_mode="5"
        ipv6_mode="pi_relay"
        uci -q batch <<EOF
            set dhcp.wan6=dhcp
            set dhcp.wan6.master="1"
            set dhcp.wan6.ignore="1"
            set dhcp.wan6.ndp="relay"
            set dhcp.wan6.ra_flags="none"
            set dhcp.wan6.interface="wan6"
            set dhcp.lan.ndp="hybrid"
            delete network.wan6
            set network.${wan6_iface}=interface
            set network.${wan6_iface}.proto=dhcpv6
            set network.${wan6_iface}.ifname=${ifname}
            set network.${wan6_iface}.reqaddress=try
            set network.${wan6_iface}.reqprefix=auto
            set network.${wan6_iface}.wantype=eth
            commit dhcp
            commit network
EOF
    }

    uci -q batch <<EOF
        set ipv6.globals.subver="1"
        set ipv6.wan6.mode=${ipv6_mode}
        add_list ipv6.wan6.support_modes='off'
        add_list ipv6.wan6.support_modes='native'
        add_list ipv6.wan6.support_modes='dhcpv6'
        add_list ipv6.wan6.support_modes='pppoev6'
        add_list ipv6.wan6.support_modes='static'
        add_list ipv6.wan6.support_modes='pi_relay'
        set ipv6.wan6.automode_backup='pi_relay'
        set ipv6.wan6.automode_pppoe_backup='pi_relay'
        set ipv6.lan6.mode="$lan_mode"
        commit ipv6
EOF
}

ipv6_autocheck_run() {
    local wan6_iface="$1"
    local action="$2"
    local script="/usr/sbin/ipv6check.sh"
    local netmode=$($UCI_GET xiaoqiang.common.NETMODE)
    local initted=$($UCI_GET xiaoqiang.common.INITTED)
    [ "$netmode" = "whc_re" -o "$netmode" = "wifiapmode" -o "$netmode" = "lanapmode" -o "$netmode" = "agent" -o "$initted" != "YES" ] && return

    for pid in $(pgrep -f "$script up $wan6_iface"); do
        kill -TERM "$pid" >/dev/null 2>&1
        sleep 1
    done

    [ "$action" != "stop" ] && $script up "$wan6_iface" &
}

ipv6_autocheck_clear_result() {
    uci -c /tmp -q batch <<EOF
        delete ipv6check.${1}
        commit ipv6check
EOF
}

ipv6_autocheck() {
    local wan6_iface_list="$1"
    local action="$2"
    action=${action:='up'}

    [ -z "$iface_list" ] && {
        wan6_iface_list=$($UCI_SHOW ipv6 | grep "ipv6.wan6[_0-9]*.automode='1'" | awk -F"[.|=]" '{print $2}' | xargs echo -n)
    }
    for wan6_iface in $wan6_iface_list; do
        case $action in
        "up" | "stop" )
            ipv6_autocheck_run "$wan6_iface" "$action"
            ;;
        "clear_result")
            ipv6_autocheck_clear_result "$wan6_iface"
            ;;
        esac
    done
}

add_icmpv6_forward_rule() {
    uci -q batch <<EOF
        set firewall.AIF=rule
        set firewall.AIF.name='Allow-ICMPv6-Forward'
        set firewall.AIF.src='wan'
        set firewall.AIF.dest='lan'
        set firewall.AIF.proto='icmp'
        add_list firewall.AIF.icmp_type='echo-request'
        add_list firewall.AIF.icmp_type='echo-reply'
        add_list firewall.AIF.icmp_type='destination-unreachable'
        add_list firewall.AIF.icmp_type='packet-too-big'
        add_list firewall.AIF.icmp_type='time-exceeded'
        add_list firewall.AIF.icmp_type='bad-header'
        add_list firewall.AIF.icmp_type='unknown-header-type'
        set firewall.AIF.limit='1000/sec'
        set firewall.AIF.family='ipv6'
        set firewall.AIF.target='ACCEPT'
        commit firewall
EOF
}

delete_icmpv6_forward_rule() {
    local rule=$1
    uci -q batch <<EOF
        delete firewall.$rule
        commit firewall
EOF
}

ipv6_set_firewall() {
    local enable=$1
    [ "$enable" != 0 ] && enable=1

    local rule=$(uci show firewall | grep 'Allow-ICMPv6-Forward' | cut -d '.' -f 2)
    if [ -z "$rule" -a "$enable" = "0" ]; then
        add_icmpv6_forward_rule
        /etc/init.d/firewall restart
    elif [ -n "$rule" -a "$enable" = "1" ]; then
        delete_icmpv6_forward_rule $rule
        /etc/init.d/firewall restart
    fi
}

ACTION="$1"
[ -z "$ACTION" ] && {
    usage
    return
}

INITTED=$($UCI_GET xiaoqiang.common.INITTED)
[ "$INITTED" != "YES" ] && {
    [  "$ACTION" = "reload" -o "$ACTION" = "reload_network" ] && return
}

case ${ACTION} in
    "reload")
        wan6_iface="$2"
        ipv6_reload "$wan6_iface"
        ;;
    "reload_network")
        wan6_iface="$2"
        ipv6_reload_network "$wan6_iface"
        ;;
    "cfg_to_v2")
        ipv6_old_cfg_to_v2
        ;;
    "cfg_v2_to_new")
        ipv6_cfg_v2_to_new
        ;;
    "autocheck")
        wan6_iface="$2"
        action="$3"
        ipv6_autocheck "$wan6_iface" "$action"
        ;;
    "set_firewall")
        enable="$2"
        ipv6_set_firewall "$enable"
        ;;
    "macvlan")
        action="$2"
        ipv6_macvlan "$action"
        ;;
     *)
        usage
        ;;
esac


