#!/bin/sh

###################################################
#    Author: hanjiayan
#    Date: 2021/3/25
#
#   when you use this functin, you should define these
#    functions in /lib/network/network_func_lib.sh
#    1. wandt_setup_wan : Wan type and port found, setup wan
#    2. wandt_setup_wan : Divide the lan ports
#    3. wandt_default_wan : set default wan config
#    4. wandt_check_link: check port link status
#
###################################################


wandt_setup_wan() {
    local wan_proto="$1"
    local wan_port="$2"

    [ -z "$wan_port" ] && [ -z "$wan_proto" ] && return

    [ "1" = "$(uci -q get ipv6.wan6.automode)" ] && /usr/sbin/ipv6.sh autocheck wan6 clear_result &
    port_service setwan "$wan_port" "$wan_proto"
    wandt_filter_kmod close
    return
}

wandt_reset_lan() {
    [ -z "$(uci -q get port_service.wan.ports)" ] && return
    wandt_filter_kmod open
    port_service delwan
    return
}

wandt_check_link() {
    local res=""

    res=$(phyhelper link service wan | grep "up")
    [ -n "$res" ] && echo "up" || echo "down"
    return
}

wandt_redetect_wan() {
    local time=""
    local param="$1"
    local wan_status=""

    case "$param" in
    normal)
        ubus call wan_detect redetect "{\"force\":0}" &
        ;;
    force)
        ubus call wan_detect redetect "{\"force\":1}" &
        ;;
    force_all)
        uci -q batch <<-EOF
            del network.wan.proto
            commit network
		EOF
        ubus call wan_detect redetect "{\"force\":1}"
        ;;
    wait)
        time="$2"
        [ -z "$time" ] && return

        sleep "$time"
        wan_status=$(ubus call network.interface.wan status | grep \"up\" | grep true)
        [ -z "$wan_status" ] && ubus call wan_detect redetect "{\"force\":1}" &
        ;;
    esac
    return
}

wandt_prog_control() {
    local cmd="$1"
    local ports="$2"
    local wan_detect_pid=""
    local wait_kill_times="6"

    [ "$cmd" != "start" ] && [ "$cmd" != "stop" ] && return

    # stop first, kill wan_detect process
    wan_detect_pid=$(pgrep -x /usr/sbin/wan_detect)
    [ -n "$wan_detect_pid" ] && {
        log "wandt: stop wan_detect process"

        kill -9 "$wan_detect_pid"

        while true; do
            wan_detect_pid=$(pgrep -x /usr/sbin/wan_detect)
            [ -z "$wan_detect_pid" ] && break;

            sleep 1
            wait_kill_times=$((wait_kill_times - 1))
            [ "$wait_kill_times" = "0" ] && break;
        done
    }

    # start wan_detect process
    [ "$cmd" = "start" ] && {
        log "wandt: start wan_detect process"
        /usr/sbin/wan_detect &
    }
    return
}

wandt_start() {
    wandt_prog_control start
    return
}

wandt_stop() {
    wandt_prog_control stop
    return
}

wandt_filter_static() {
    local cmd="$1"
    local wandt_enable wan_proto wan_ipaddr wan_gateway

    ipstr2int() {
        local ip="$1"
        local index num
        local res=0

        for index in 1 2 3 4; do
            num=$(echo "$ip" | cut -d '.' -f "$index")
            let "res=res<<8"
            let res+=num
        done
        echo "$res"
    }

    [ "$cmd" = "open" ] && {
        [ -n "$rule_exist" ] && return
        wandt_enable=$(uci -q get port_service.wandt_attr.enable)
        [ "$wandt_enable" = "1" ] || return

        wan_proto=$(uci -q get network.wan.proto)
        [ "$wan_proto" = "static" ] || return

        wan_ipaddr=$(uci -q get network.wan.ipaddr)
        wan_gateway=$(uci -q get network.wan.gateway)
        [ -z "$wan_ipaddr" ] || [ -z "$wan_gateway" ] && return

        echo "$(ipstr2int "$wan_ipaddr")"  > /sys/module/wandt_filter/parameters/wf_ip
        echo "$(ipstr2int "$wan_gateway")" > /sys/module/wandt_filter/parameters/wf_gw
    }

    [ "$cmd" = "close" ] && {
        echo 0 > /sys/module/wandt_filter/parameters/wf_ip
        echo 0 > /sys/module/wandt_filter/parameters/wf_gw
    }
    return
}

wandt_filter_kmod() {
    local action="$1"
    local wait_insmod_times="6"

    case "$action" in
    load)
        [ -d "/sys/module/wandt_filter" ] || {
            linux_ver=$(uname -r)
            insmod /lib/modules/"$linux_ver"/wandt_filter.ko

            while true; do
                [ -d "/sys/module/wandt_filter" ] && break;

                sleep 1
                wait_insmod_times=$((wait_insmod_times - 1))
                [ "$wait_insmod_times" = "0" ] && break;
            done
        }
        echo 1 > /sys/module/wandt_filter/parameters/wf_switch
        ;;

    unload)
        [ -d "/sys/module/wandt_filter" ] && {
            echo 0 > /sys/module/wandt_filter/parameters/wf_switch
            rmmod wandt_filter.ko
        }
        ;;

    open)
        [ -d "/sys/module/wandt_filter" ] || return
        wandt_filter_static open
        echo 1 > /sys/module/wandt_filter/parameters/wf_switch
        ;;

    close)
        [ -d "/sys/module/wandt_filter" ] || return
        wandt_filter_static close
        echo 0 > /sys/module/wandt_filter/parameters/wf_switch
        ;;
    esac
    return
}

wandt_usage(){
    echo "USAGE: $0 <probe|setup_wan|reset_lan> [wan_type] [interface] [timeout]"
    echo "    probe: <interface> <wan_type> [timeout]"
    echo "    setup_wan: <interface> <wan_type>"
    echo "    reset_lan: "
    echo "    check_link: <port_index>"
    echo "        wan_type: 0 for pppoe| 1 for dhcp"
}

log() {
    logger -p local0.info -t wandt "$*"
}

OPT="$1"
shift
case "$OPT" in
    "start")
        wandt_start "$@"
        ;;

    "stop")
        wandt_stop
        ;;

    "setup_wan")
        [ $# -ne 2 ] && {
            usage
            exit 1
        }
        wandt_setup_wan "$@"
        ;;

    "reset_lan")
        wandt_reset_lan
        ;;

    "check_link")
        wandt_check_link
        ;;

    "redetect_wan")
        wandt_redetect_wan "$@"
        ;;

    "clear_v6_dect")
        ubus call wan_detect clear_v6dect &
        ;;

    "filter")
        wandt_filter_kmod "$@"
        ;;
    *)
        ;;
esac

exit 0
