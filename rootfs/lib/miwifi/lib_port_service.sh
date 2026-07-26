#!/bin/sh

SERVICE=""             # /usr/sbin/port_service.sh <cmd> <service>, save "service" to $SERVICE
LIST_SERVICES=""       # the service which port_service will restart
AP_SERVICES=""         # the service which only used in ap mode
ROUTER_SERVICES=""     # the service which only used in router mode
NET_MODE=""            # the router's network mode
PS_UCI="port_service"  # the uci name of port_service

arch_ps_init_service()             { return 0; }
arch_ps_pre_stop_service()         { return 0; }
arch_ps_post_stop_service()        { return 0; }
arch_ps_pre_start_service()        { return 0; }
arch_ps_post_start_service()       { return 0; }
arch_ps_pre_wandt_start()          { return 0; }
arch_ps_post_wandt_start()         { return 0; }
arch_ps_setup_wan()                { return 0; }
arch_ps_reset_lan()                { return 0; }
arch_ps_rebuild_network()          { return 0; }
arch_ps_reload_firwall()           { return 0; }
arch_ps_transform_config()         { return 0; }
arch_ps_check_service()            { return 0; }
arch_ps_iptv_ctl()                 { return 0; }
arch_ps_setup_wan_ap()             { return 0; }
arch_ps_reset_lan_ap()             { return 0; }
. /lib/functions.sh
. /lib/miwifi/miwifi_functions.sh
. /lib/miwifi/arch/lib_arch_port_service.sh


ps_logger() {
    echo -e "[port_service] $*" > /dev/console
    return
}

ps_uci_set() {
    local section="$1"
    local key="$2"
    local value="$3"

    [ -z "$section" ] || [ -z "$key" ] && return

    uci batch <<-EOF
		set "$PS_UCI"."$section"."$key"="$value"
		commit "$PS_UCI"
	EOF
    return
}

ps_uci_get() {
    local section="$1"
    local key="$2"
    local value=""

    [ -z "$section" ] || [ -z "$key" ] && return

    value=$(uci -q get "$PS_UCI"."$section"."$key")
    [ -n "$value" ] && echo "$value"
    return
}

ps_init_service() {
    # when router reboot, must redetect
    [ "1" = "$(ps_uci_get wan wandt)" ] && ps_uci_set wan ports ""

    arch_ps_init_service
    return
}

ps_pre_start_service() {
    arch_ps_pre_start_service
    return
}

ps_post_start_service() {
    if [ -z "$NET_MODE" ] || [ "whc_cap" = "$NET_MODE" -o "controller" = "$NET_MODE" ]; then
        [ "1" != "$(ps_uci_get wan wandt)" ] && ps_wandt_ctl filter unload
    else
        ps_wandt_ctl filter unload
    fi

    [ "whc_re" = "$NET_MODE" -o "agent" = "$NET_MODE" ] && {
        # in re mode, the topomon must restart when user change the lag's config
        /etc/init.d/topomon restart
    }

    util_portmap_update

    [ -f /etc/init.d/wire_loop_detect ] && /etc/init.d/wire_loop_detect restart
    arch_ps_post_start_service
    return
}

ps_pre_stop_service() {
    # avoid lan device get uppper dhcp server's ip, when wan is in wandt mode
    [ "whc_cap" = "$NET_MODE" -o "controller" = "$NET_MODE" ] && list_contains LIST_SERVICES wan && ps_wandt_ctl filter load

    arch_ps_pre_stop_service
    return
}

ps_post_stop_service() {
    arch_ps_post_stop_service
    return
}

ps_check_service() {
    arch_ps_check_service "$@"
    return
}

ps_rebuild_network() {
    arch_ps_rebuild_network
    return
}

ps_reload_firewall() {
    arp_intercept() {
        local initted lan_ip lan_mac
        local rule_name="port_service_common"

        # clean all arptables rules
        arptables -F "$rule_name" > /dev/null 2>&1
        arptables -D FORWARD -j "$rule_name" > /dev/null 2>&1
        arptables -X "$rule_name" > /dev/null 2>&1

        # judge if need to add rules
        initted=$(uci -q get xiaoqiang.common.INITTED)
        [ -z "$initted" ] || return

        # if the router uninitted, force all lans only can get his br-lan's macaddr
        lan_ip=$(uci -q get network.lan.ipaddr)
        lan_mac=$(uci -q get network.lan.macaddr)
        [ -n "$lan_ip" ] && [ -n "$lan_mac" ] && {
            arptables -N "$rule_name"
            arptables -I FORWARD -j "$rule_name"
            arptables -I "$rule_name" --h-length 6 --h-type 1 --proto-type 0x800 --opcode 2 -s "$lan_ip" -j mangle --mangle-mac-s "$lan_mac"
        }
        return
    }

    arp_intercept
    arch_ps_reload_firwall
    return
}

ps_default_config() {
    local mode="$1" # "router" or "ap"

    for service in $ROUTER_SERVICES; do
        if [ "$service" = "wan" ] && [ "$mode" = "router" ]; then
            uci set "$PS_UCI"."$service".enable="1"
            uci set "$PS_UCI"."$service".ports=""
            uci set "$PS_UCI"."$service".wandt="1"
        else
            uci set "$PS_UCI"."$service".enable="0"
            uci set "$PS_UCI"."$service".ports=""
        fi
    done
    uci commit "$PS_UCI"
    return
}

ps_transform_config() {
    local mode="$1" # "router" or "ap"
    local service

    for service in $ROUTER_SERVICES; do
        list_contains AP_SERVICES "$service" && continue
        case "$mode" in
            "ap") # transform into ap modes
                    uci set "$PS_UCI"."$service".enable="0"
                ;;
            "router") # transform into router modes
                    wan_auto_selection=$(uci get misc.features.wan_auto_selection)
                    [ "$service" = "wan" ] && {
                        [ x"$wan_auto_selection" = x"0" ] && {
                            uci set "$PS_UCI".wan.wandt=0
                        } || {
                            uci set "$PS_UCI".wan.wandt=1
                            uci set "$PS_UCI".wan.ports=""
                        }
                        uci set "$PS_UCI".wan.enable=1
                    }
                ;;
        esac
    done
    uci commit "$PS_UCI"

    arch_ps_transform_config "$mode"
    return
}

ps_wandt_ctl() {
    local action="$1"
    local script="/usr/sbin/wan_detect.sh"

    [ ! -f "$script" ] || [ -z "$action" ] && return

    "$script" "$@"
    return
}

ps_iptv_ctl() {
    local action="$1"
    local script="/usr/sbin/media.sh"

    [ -z "$(port_map port service iptv)" ] && [ "$(ps_uci_get iptv_2 enable)" != "1" ] && return
    [ ! -x "$script" ] || [ -z "$action" ] && return

    "$script" iptv "$@"
    arch_ps_iptv_ctl "$@"
    ps_logger "iptv $action finish"

    return
}

ps_config_interface() {
    local ifname="$1"
    local section_name

    section_name="${ifname//./_}"
    uci -q get network."$section_name" > /dev/null 2>&1 && return
    uci batch <<-EOF
		set network."$section_name"=interface
		set network."$section_name".ifname="$ifname"
		commit network
	EOF
    return
}

ps_delete_interface() {
    local ifname="$1"
    local section_name

    section_name="${ifname//./_}"
    uci -q delete network."$section_name"
    uci commit network
    return
}

ps_guest_ctl() {

    gst_ebtable_stop() {
        ebtables -D FORWARD -j guest > /dev/null 2>&1
        ebtables -X guest > /dev/null 2>&1
    }

    gst_ebtable_start() {
        gst_ebtable_stop

        ebtables -N guest > /dev/null 2>&1
        ebtables -A FORWARD -j guest > /dev/null 2>&1

        local lan_ifnames=$(uci -q get network.guest.ifname)
        [ -z "$lan_ifnames" ] && return

        lan_ifnames=$lan_ifnames" "$(uci -q get misc.wireless.iface_guest_2g_ifname)" "$(uci -q get misc.wireless.iface_guest_5g_ifname)
        local uplink_ifname
        [ "$(uci -q get xiaoqiang.common.NETMODE)" = "whc_re" ] && {
            uplink_ifname="$(cat /var/run/topomon/port_name)"
            [ -n "$uplink_ifname" ] && {
                uplink_ifname="$uplink_ifname"."$(uci -q get port_service.guest.vlan)"
            }
        }
        [ -z "$uplink_ifname" ] && uplink_ifname="br-guest"

        for ifname in $lan_ifnames
        do
            [ "$ifname" = "$uplink_ifname" ] && continue;
            ebtables -A guest -i $ifname -o ! $uplink_ifname -j DROP
        done
    }

    local action="$1"
    local vid=$(uci -q get port_service.guest.vlan)
    local ports=$(port_map config get settings ports)
    local port ifname ifnames

    if [ "$action" = "start" ]; then
        [ "$(ps_uci_get guest enable)" != "1" ] && return
        for port in $ports; do
            [ "lan" != $(port_map config get "$port" service) ] && continue
            ifname=$(port_map config get "$port" ifname)
            ifname="${ifname}.${vid}"
            ps_config_interface $ifname
            list_contains ifnames $ifname || append ifnames $ifname
        done
        uci -q set network.guest.ifname="$ifnames"
        uci commit network
        ubus call network reload
        gst_ebtable_start
    elif [ "$action" = "stop" ]; then
        for port in $ports; do
            ifname=$(port_map config get "$port" ifname)
            ifname="${ifname}.${vid}"
            ps_delete_interface $ifname
        done
        uci -q del network.guest.ifname
        uci commit network
        ubus call network reload
        gst_ebtable_stop
    elif [ "$action" = "reload_firewall" ]; then
        gst_ebtable_stop
        gst_ebtable_start
    fi
    ps_logger "guest $action finish"
    return
}

ps_iptv_2_ctl() {
    local action="$1"
    local ports=""
    local ifnames="$(uci -q get network.iptv.ifname)"
    local vid=$(ps_uci_get iptv_2 vlan)

    if [ "$action" = "start" ]; then
        [ "$(ps_uci_get iptv_2 enable)" != "1" ] && return

        ports=$(ps_uci_get iptv_2 ports)
        [[ -z "$vid" || -z "$ports" ]] && return

        for port in $ports; do
            [ "lan" != $(port_map config get "$port" service) ] && continue
            ifname=$(port_map config get "$port" ifname)
            ifname="${ifname}.${vid}"
            ps_config_interface $ifname
            list_contains ifnames $ifname || append ifnames $ifname
        done
        uci -q set network.iptv.ifname="$ifnames"
        uci commit network
        ubus call network reload
    elif [ "$action" = "stop" ]; then
        for port in $(port_map config get settings ports); do
            ifname=$(port_map config get "$port" ifname)
            ifname="${ifname}.${vid}"
            ps_delete_interface $ifname
        done
    fi
    ps_logger "iptv_2 $action finish"

    return
}

ps_lag_ctl() {
    local action="$1"
    local script="/usr/sbin/lag.sh"

    [ -z "$(port_map port service lag)" ] && return
    [ ! -f "$script" ] || [ -z "$action" ] && return

    "$script" "$@"
    ps_logger "lag $action finish"
    return
}

ps_game_ctl() {
    local action="$1"
    local script="/usr/sbin/game.sh"

    [ -z "$(port_map port service game)" ] && return
    [ ! -x "$script" ] || [ -z "$action" ] && return

    "$script" "$@"
    ps_logger "game $action finish"
    return
}

ps_wan_ctl() {
    local action="$1"
    local service="$2"
    local wandt ports wandt_ports

    wan_start() {
        local service="$1"

        [ "eth" != "$(ps_uci_get "$service" type)" ] && return
        [ "1" != "$(ps_uci_get "$service" enable)" ] && return

        ports=$(ps_uci_get "$service" ports)
        wandt=$(ps_uci_get "$service" wandt)

        # wan detect only used for wan
        [ "wan" != "$service" ] && wandt="0"

        if [ "$wandt" = "1" ]; then
            # in wandt mode, wan's link_mode must set to auto
            ps_uci_set wan link_mode 0

            # config wandt
            wandt_ports=$(port_map port service lan)
            wandt_ports="${wandt_ports} ${ports}"

            ps_uci_set wandt_attr ports "$(echo "$wandt_ports"|xargs)"
            ps_uci_set wandt_attr enable "1"
            [ -z "$(ps_uci_get wandt_attr mac)" ] && {
                ps_uci_set wandt_attr mac "$(getmac wan)"
            }
            if [ "1" = "$(ps_uci_get wan wantag)" ]; then
                ps_uci_set wandt_attr vid "$(ps_uci_get wantag_attr vid)"
            else
                ps_uci_set wandt_attr vid ""
            fi

            # start wandt program
            arch_ps_pre_wandt_start
            ps_wandt_ctl filter open
            ps_wandt_ctl start
            arch_ps_post_wandt_start
            ps_logger "$service start wandt mode finish"
        else
            [ -n "$ports" ] && {
                ps_setup_wan "$service" "$ports"
                ps_logger "$service start fixed mode finish"
            }
            ps_wandt_ctl filter unload
        fi
        return
    }

    wan_stop() {
        local service="$1"

        [ "eth" != "$(ps_uci_get "$service" type)" ] && return

        [ "wan" = "$service" ] && {
            ps_wandt_ctl stop

            # redetect wan port
            [ "1" = "$(ps_uci_get wan wandt)" ] && ps_uci_set wan ports ""
        }

        [ -z "$(port_map port service "$service")" ] && return

        ps_reset_lan "$service"
        ps_logger "$service stop finish"
        return
    }

    list_contains ROUTER_SERVICES "$service" && wan_"$action" "$service"
    return
}

ps_setup_wan() {
    local service="$1"
    local wan_port="$2"
    local proto="$3"
    local old_wan_port wan_ifname wan_vid

    ps_logger "setup $* start"

    old_wan_port=$(port_map port service "$service")

    # config wan port link mode
    [ "$(port_map config get "$wan_port" type)" = "eth" ] && {
        phyhelper mode set "$wan_port" "$(ps_uci_get "$service" link_mode)"
    }

    # config wan port service
    port_map config set "$wan_port" service "$service"

    # config wan tag
    [ "1" = "$(ps_uci_get "$service" wantag)" ] && {
        wan_vid=$(ps_uci_get "${service}tag_attr" vid)
        [ -n "$wan_vid" ] && {
            wan_ifname=$(port_map iface port "$wan_port")
            port_map config set "$wan_port" dial_ifname "${wan_ifname}.${wan_vid}"
        }
    }

    # config wan proto
    [ "wan" = "$service" ] && [ -z "$(uci -q get network."$service".proto)" -o "none" == "$(uci -q get network."$service".proto)" ] && [ -n "$proto" ] && {
        uci batch <<-EOF
            set network."$service".proto="$proto"
            commit network
		EOF
    }

    # config wan network
    arch_ps_setup_wan "$service" "$wan_port" "$proto" "$old_wan_port"

    # reload services
    [ "wan" = "$service" ] && ps_iptv_ctl add_wan "$wan_port"
    [ -x /etc/init.d/wan_check ] && /etc/init.d/wan_check restart > /dev/null 2>&1
    [ -x /etc/init.d/miqos ] && /etc/init.d/miqos restart  > /dev/null 2>&1
    [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq restart > /dev/null 2>&1
    [ -x /etc/init.d/messagingagent.sh ] && /etc/init.d/messagingagent.sh restart > /dev/null 2>&1

    ps_logger "setup $* finish"
    return
}

ps_reset_lan() {
    local service="$1"
    local old_wan_port

    old_wan_port=$(port_map port service "$service")
    [ -z "$old_wan_port" ] && return

    ps_logger "reset $service $old_wan_port start"

    # reload services
    [ "wan" = "$service" ] && ps_iptv_ctl del_wan "$old_wan_port"

    # revert wan network
    arch_ps_reset_lan "$service" "$old_wan_port"

    # revert port service
    port_map config set "$old_wan_port" service lan

    # revert wan tag
    port_map config set "$old_wan_port" dial_ifname ""

    # revert port link mode
    [ "$(port_map config get "$old_wan_port" type)" = "eth" ] && {
        phyhelper mode set "$old_wan_port" 0
    }

    ps_logger "reset $service $old_wan_port finish"
    return
}

ps_setup_wan_ap() {
    local wan_port="$1"

    [ -z "$wan_port" ] && return

    port_map config set "$wan_port" service wan
    arch_ps_setup_wan_ap "$wan_port"
    ps_iptv_ctl add_wan "$wan_port"
    ps_logger "set ap wan $wan_port finish"
    return
}

ps_reset_lan_ap() {
    local old_wan_port

    old_wan_port=$(port_map port service "$service")
    [ -z "$old_wan_port" ] && return

    ps_iptv_ctl del_wan "$old_wan_port"
    arch_ps_reset_lan_ap "$old_wan_port"
    port_map config set "$old_wan_port" service lan
    ps_logger "del ap wan $old_wan_port finish"
    return
}

ps_setwan() {
    local wan_port="$1"
    local wan_proto="$2"

    [ -z "$wan_port" ] && return
    ps_uci_set wan ports "$wan_port"

    if [ "$NET_MODE" = "whc_cap" -o "$NET_MODE" = "controller" ]; then
        ps_setup_wan "wan" "$wan_port" "$wan_proto"
    elif [ "$NET_MODE" = "lanapmode" ]; then
        ps_setup_wan_ap "$wan_port"
    fi
    return
}

ps_delwan() {
    ps_uci_set wan ports ""

    if [ "$NET_MODE" = "whc_cap" -o "$NET_MODE" = "controller" ]; then
        ps_reset_lan "wan"
    elif [ "$NET_MODE" = "lanapmode" ]; then
        ps_reset_lan_ap
    fi
    return
}