#!/bin/sh

trap clean_up_exit TERM
. /lib/functions/network.sh

UCI_GET="uci -q get "
UCI_GET_TMP="uci -c /tmp -q get "
ODHCP6C_BIN="/usr/sbin/odhcp6c"
ODHCP6C_SCRIPT="/usr/sbin/ipv6check.script"
ODHCP6C_CMD="xxxxxx"
CHECK_STATUS=""
UP_STATUS=""
WAN_IFACE="wan"
WAN6_IFNAME=""

usage() {
    echo "$0 <ACTION> <WAN6_IFACE>"
}

loginfo() {
    msg="$@"
    [ -z "$msg" ] && return 0

    DATE="$(date)"
    logger -t "ipv6check[${$}]" "$msg"
}

clear_check_result() {
    uci -c /tmp -q batch <<EOF
        delete ipv6check.${WAN6_IFACE}
        commit ipv6check
EOF
}

update_check_status() {
    uci -c /tmp -q batch <<EOF
        set ipv6check.${WAN6_IFACE}.succeed="$1"
        commit ipv6check
EOF
}

start_odhcp6c() {
	if [ "$(bdata get CountryCode)" = "JP" ]; then
        ODHCP6C_CMD="$ODHCP6C_BIN -d -s $ODHCP6C_SCRIPT -g -p $ODHCP6C_PID_FILE -Ntry -P0 $WAN6_IFNAME"
	else
        ODHCP6C_CMD="$ODHCP6C_BIN -d -s $ODHCP6C_SCRIPT -p $ODHCP6C_PID_FILE -Ntry -P0 $WAN6_IFNAME"
	fi
    export INTERFACE="$WAN6_IFACE" && $ODHCP6C_CMD > /dev/null 2>&1
}

stop_odhcp6c() {
    for pid in $(pgrep -f "$ODHCP6C_CMD"); do
        kill -9 $pid
        sleep 1
    done

    rm -f $ODHCP6C_PID_FILE
}

clean_up_exit() {
   #stop_odhcp6c
   loginfo "recv TERM signal, exit"
   exit 0
}

wait_wan6_up() {
    local cnt=0
    local status="false"
    local wait_sec=30
    local uptime=$(cat /proc/uptime | cut -d'.' -f1)

    [ "$uptime" -le 120 ] && wait_sec=$((120 - $uptime + $wait_sec))

    loginfo "wait_wan6_up wait_sec:$wait_sec"
    while [ "$cnt" -le "$wait_sec" ]; do
        status=$(ifstatus "$WAN6_IFACE" | jsonfilter -e '@.up')
        [ "$status" = "true" ] && break;

        sleep 1
        let "cnt++"
    done

    UP_STATUS="$status"
}

#example
#prefixes: "2001:5:0:8::/62,43200,43200"
#ra_prefixes: "2001:5::/64,4294967295,4294967295,class=00000000,excluded=::/256"
#prefixes和ra_prefixes有多个条目的话会以空格分隔。
is_same_pd_pi() {
    local prefixes="$1"
    local ra_prefixes="$2"

    for prefix in $prefixes; do
        prefix=${prefix%%/*}
        for ra_prefix in $ra_prefixes; do
            ra_prefix=${ra_prefix%%/*}
            [ "$prefix" = "$ra_prefix" ] && {
                echo "true"
                return
            }
        done
    done
}

ipv6check_setmode() {
    local prefixes="$1"
    local ra_prefixes="$2"
    local automode_select
    local cur_mode=$($UCI_GET ipv6.$WAN6_IFACE.mode)
    local wan_proto=$($UCI_GET network.$WAN_IFACE.proto)

    [ -n "$prefixes" -a -n "$ra_prefixes" ] && {
        [ "$(is_same_pd_pi "$prefixes" "$ra_prefixes")" = "true" ] && prefixes=""
    }

    if [ -n "$prefixes" ]; then
        automode_select="native"
    else
        if [ "$wan_proto" = "pppoe" ]; then
            automode_select=$($UCI_GET ipv6.$WAN6_IFACE.automode_pppoe_backup)
            # 当prefixes为空，wan_proto为pppoe时，也设置成native模式，在dhcpv6.script中，会自动开启NAT6。
            [ -z "$automode_select" ] && automode_select="native"
        else
            automode_select=$($UCI_GET ipv6.$WAN6_IFACE.automode_backup)
            [ -z "$automode_select" ] && automode_select="pi_relay"
        fi
    fi

    loginfo "cur_mode:$cur_mode, automode_select:$automode_select"
    [ "$cur_mode" != "$automode_select" ] && {
        /usr/sbin/ipv6.lua setmode "$WAN6_IFACE" "$automode_select" &
    }
}

ipv6check_run(){
    local cnt=0
    local prefixes addresses ra_prefixes ra_addresses odhcp6c_pid check_result

    #clear_check_result

    #start_odhcp6c

    while [ "$cnt" -le 30 ]; do
        check_result="$(uci -c /tmp -q show ipv6check.$WAN6_IFACE)"
        check_result=${check_result// /;}
        check_result=${check_result//\'/}

        for entry in $check_result; do
            [ "${entry%%=*}" = "ipv6check.$WAN6_IFACE.PREFIXES" ] && prefixes="${entry#*=}"
            [ "${entry%%=*}" = "ipv6check.$WAN6_IFACE.ADDRESSES" ] && addresses="${entry#*=}"
            [ "${entry%%=*}" = "ipv6check.$WAN6_IFACE.RA_PREFIXES" ] && ra_prefixes="${entry#*=}"
            #[ "${entry%%=*}" = "ipv6check.$WAN6_IFACE.RA_ADDRESSES" ] && ra_addresses="${entry#*=}"
        done

        prefixes="${prefixes//;/ }" #IA_PD
        addresses="${addresses//;/ }" #IA_NA
        ra_prefixes="${ra_prefixes//;/ }" #PI: RA->Prefix information
        #ra_addresses="${ra_addresses//;/ }" #PI + EUI64
        [ -n "$ra_prefixes" ] && [ -n "$prefixes" -o -n "$addresses" ] && break

        let "cnt++"
        sleep 1

        [ "$cnt" -gt 5 ] && {
            odhcp6c_pid=$(pgrep -f "$ODHCP6C_CMD")
            [ -z "$odhcp6c_pid" ] && break
            kill -SIGALRM $odhcp6c_pid #send RS
        }
    done

    #stop_odhcp6c

    loginfo "prefixes:$prefixes"
    loginfo "addresses:$addresses"
    loginfo "ra_prefixes:$ra_prefixes"

    [ -z "$addresses" -a -z "$ra_prefixes" ] && {
        loginfo "ipv6 check failed."
        return
    }

    update_check_status 1
    ipv6check_setmode "$prefixes" "$ra_prefixes"
    CHECK_STATUS="success"
}

ipv6check_start() {
    while true; do
        wait_wan6_up
        [ "$UP_STATUS" = "false" ] && {
            loginfo "$WAN6_IFACE up is false, exit."
            break
        }

        network_flush_cache
        network_get_device WAN6_IFNAME "$WAN6_IFACE"
        [ -z "$WAN6_IFNAME" ] && {
            loginfo "$WAN6_IFACE ifname is null, exit."
            break
        }

        ipv6check_run
        [ "$CHECK_STATUS" = "success" ] && {
            loginfo "$WAN6_IFACE automode check succeed, exit."
            break
        }

        sleep 1
    done
}

ACTION="$1"
WAN6_IFACE=$(echo $2 | tr -d "\n\t ")  #去除空格、换行符和制表符
[ "${WAN6_IFACE:0:4}" != "wan6" ] && {
    loginfo "wan6 interface:$WAN6_IFACE invalid".
    usage
    exit 1
}

WAN6_ID=${WAN6_IFACE##*_}
[ "$WAN6_ID" != "$WAN6_IFACE" ] && {
    WAN_IFACE="${WAN_IFACE}_$WAN6_ID"
}
ODHCP6C_PID_FILE="/var/run/odhcp6c_ipv6check_${WAN6_IFACE}.pid"

case "$ACTION" in
    up)
        ipv6check_start
        ;;
    *)
        loginfo "ACTION:$ACTION is unknown"
        usage
        ;;
esac
