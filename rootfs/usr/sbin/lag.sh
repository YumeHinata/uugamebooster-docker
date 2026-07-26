#!/bin/sh
. /usr/share/libubox/jshn.sh
. /lib/miwifi/miwifi_functions.sh
readonly BOND_IFNAME="bond0"
readonly PSUCI="port_service"

log() {
    echo "[LAG] $*" >/dev/console
}

json_out() {
    json_init
    json_add_string code "$1"
    json_add_string reason "$2"
    if [ "$#" -eq 8 ]; then
        json_add_array info
        json_add_object
        json_add_string port "$3"
        json_add_string link "$4"
        json_add_string speed "$5"
        json_close_object
        json_add_object
        json_add_string port "$6"
        json_add_string link "$7"
        json_add_string speed "$8"
        json_close_object
        json_close_array
    fi
    json_dump
}

#        0： 聚合成功
#        1： 聚合失败，聚合口网线未接入
#        2： 聚合失败，聚合口协商速率不一致
#        3： 聚合失败，请检查对端是否开启LACP协议
#        4： 聚合未开启，请配置聚合
get_lag_status() {
    local idx=0
    local reason=""
    local lag_ports=""
    local speed=0
    local speed_sum=0
    local lag_speed=0
    local lag_duplex=""
    local lag_port_1_speed=0
    local lag_port_2_speed=0
    local lag_port_1_link="up"
    local lag_port_2_link="up"
    local lag_port_1 lag_port_2

    if [ ! -f "/proc/net/bonding/${BOND_IFNAME}" ]; then
        json_out 3 "未找到聚合口"
        return
    fi

    # check if all lag ports are up
    lag_ports=$(port_map port service lag 2>/dev/null)
    if [ -n "$lag_ports" ]; then
        for port in $lag_ports; do
            idx=$((idx + 1))
            eval lag_port_"${idx}"="$port"
            # get link status of port
            if phyhelper link port "$port" | grep "link:down" >/dev/null 2>&1; then
                eval lag_port_${idx}_link="down"
                [ -n "$reason" ] && reason="${reason}，"
                reason="${reason}网口${port}未连接"
            else
                # if link is up, check speed
                speed=$(phyhelper speed port "$port")
                speed_sum=$((speed_sum + speed))
                case "$speed" in
                10000)
                    speed="10G"
                    ;;
                5000)
                    speed="5G"
                    ;;
                2500)
                    speed="2.5G"
                    ;;
                1000)
                    speed="1G"
                    ;;
                100)
                    speed="100M"
                    ;;
                10)
                    speed="10M"
                    ;;
                *)
                    speed="0"
                    ;;
                esac
                eval lag_port_"${idx}"_speed="$speed"
            fi
        done
        if [ -n "$reason" ]; then
            json_out 1 "$reason" "$lag_port_1" "$lag_port_1_link" "$lag_port_1_speed" "$lag_port_2" "$lag_port_2_link" "$lag_port_2_speed"
            return
        fi
    else
        json_out 3 "获取聚合接口状态失败"
        return
    fi

    # check if all lag ports have the same speed
    if [ "$lag_port_1_speed" != "$lag_port_2_speed" ]; then
        reason="网口${lag_port_1}协商速率为${lag_port_1_speed}，网口${lag_port_2}协商速率为${lag_port_2_speed}"
        json_out 2 "$reason" "$lag_port_1" "$lag_port_1_link" "$lag_port_1_speed" "$lag_port_2" "$lag_port_2_link" "$lag_port_2_speed"
        return
    fi

    # speed sum of all lag ifaces should be same with speed of lag
    lag_speed=$(ethtool "${BOND_IFNAME}" | grep Speed | cut -d ' ' -f 2 | tr -cd "\[0-9\]" 2>/dev/null)
    if [ -z "$lag_speed" ]; then
        json_out 3 "获取聚合速率失败"
        return
    fi
    if [ "$speed_sum" != "$lag_speed" ]; then
        json_out 3 "请开启LACP协议" "$lag_port_1" "$lag_port_1_link" "$lag_port_1_speed" "$lag_port_2" "$lag_port_2_link" "$lag_port_2_speed"
        return
    fi

    lag_duplex=$(ethtool "${BOND_IFNAME}" | grep Duplex | cut -d ' ' -f 2 | tr -cd "\[A-z\]" 2>/dev/null)
    if [ "Full" != "$lag_duplex" ]; then
        json_out 3 "LACP协议不支持聚合半双工网口"
        return
    fi

    json_out 0 ""
    return
}

check_module() {
    local module="$1"
    grep "^$module" /proc/modules
    return $?
}

set_driver_values() {
    local bondif="$1"
    local varname="$2"
    local value="$3"

    [ -n "$value" ] && echo "$value" >/sys/class/net/"$bondif"/bonding/"$varname"
}

disable_lag() {
    local slave list_slave

    [ -f "/proc/net/bonding/${BOND_IFNAME}" ] || return
    list_slave=$(cat </proc/net/bonding/${BOND_IFNAME} | grep "Slave Interface" | cut -d ' ' -f 3)
    ubus call network.interface.lan remove_device "{\"name\":\"$BOND_IFNAME\"}" >/dev/null 2>&1
    for slave in $list_slave; do
        set_driver_values $BOND_IFNAME "slaves" "-$slave"
        ifconfig "$slave" up
    done
    echo "-$BOND_IFNAME" >/sys/class/net/bonding_masters
    log "Disable LAG"

    [ "1" = $(uci -q get misc.mesh.guest) ] && {
        local vid=$(uci -q get port_service.guest.vlan)
        local guest_ifname=$BOND_IFNAME.$vid
        if [ -d /sys/class/net/$guest_ifname ]; then
            ubus call network.interface.guest remove_device "{\"name\":\"$guest_ifname\"}"
            ip link del $guest_ifname
        fi
    }
    return
}

enable_lag() {
    local mode port list_port_lag slave slave_link_status
    local miimon ad_select lacp_rate xmit_hash_policy all_slaves_active

    list_port_lag=$(port_map port service lag)
    [ -z "$list_port_lag" ] && return

    # mode:
    #     0: XOR Mode
    #     1: 8023AD LCAP Passive Mode
    #     2: 8023AD LCAP Active Mode
    #
    # xmit_hash_policy:
    #    0: layer2
    #    1: layer3+4
    #    2: layer2+3
    #    3: encap2+3
    #    4: encap3+4
    mode=$(uci -q get $PSUCI.lag_attr.mode)
    case "$mode" in
    "0")
        mode="balance-xor"
        xmit_hash_policy=0
        miimon=100
        lacp_rate=1
        ;;

    "1")
        mode="802.3ad"
        all_slaves_active=0
        xmit_hash_policy=0
        ad_select=0
        ;;

    "2")
        mode="802.3ad"
        miimon=100
        ad_select=2
        lacp_rate=1
        xmit_hash_policy=1
        all_slaves_active=1
        ;;

    "3")
        mode="802.3ad"
        miimon=100
        ad_select=2
        lacp_rate=1
        xmit_hash_policy=3
        all_slaves_active=1
        ;;

    *)
        log "ERROR - $mode: Unsupported lag mode"
        return
        ;;
    esac

    # Show logs
    log "Enabling LAG"
    log "slave_port : $list_port_lag"
    log "mode : $mode"

    # Add bonding interface to system and set mode
    echo "+$BOND_IFNAME" >/sys/class/net/bonding_masters
    ifconfig $BOND_IFNAME down
    set_driver_values $BOND_IFNAME "mode" $mode
    [ -n "$miimon" ] && set_driver_values $BOND_IFNAME "miimon" "$miimon"
    [ -n "$ad_select" ] && set_driver_values $BOND_IFNAME "ad_select" "$ad_select"
    [ -n "$lacp_rate" ] && set_driver_values $BOND_IFNAME "lacp_rate" "$lacp_rate"
    [ -n "$xmit_hash_policy" ] && set_driver_values $BOND_IFNAME "xmit_hash_policy" "$xmit_hash_policy"
    [ -n "$all_slaves_active" ] && set_driver_values $BOND_IFNAME "all_slaves_active" "$all_slaves_active"

    # Add slaves
    for port in $list_port_lag; do
        slave=$(port_map config get "$port" ifname)
        slave_link_status="$(phyhelper link port "$port" | cut -d ' ' -f 2 | cut -d ':' -f 2)"
        ifconfig "$slave" down
        set_driver_values $BOND_IFNAME "slaves" "+$slave"
        util_iface_status_set "$slave" "$slave_link_status"
    done
    ifconfig $BOND_IFNAME up
    phyhelper restart "$list_port_lag"

    sleep 1
    ubus call network.interface.lan add_device "{\"name\":\"$BOND_IFNAME\"}"

    [ "1" = $(uci -q get port_service.guest.enable) ] && {
        local vid=$(uci -q get port_service.guest.vlan)
        local guest_ifname=$BOND_IFNAME.$vid
        ip link add link $BOND_IFNAME name $guest_ifname type vlan id $vid
        ip link set $guest_ifname up
        ubus call network.interface.guest add_device "{\"name\":\"$guest_ifname\"}"
    }
    return
}

start() {
    local linux_ver=""
    local flag_enable_lag=""

    flag_enable_lag=$(uci -q get $PSUCI.lag.enable)
    linux_ver=$(uname -r)

    if [ "$flag_enable_lag" = "1" ]; then
        [ -d /sys/module/bonding/ ] || insmod /lib/modules/"$linux_ver"/bonding.ko

        [ -f "/sys/class/net/bonding_masters" ] || {
            log "ERROR - bonding_masters does not exist"
            return
        }
        enable_lag
    else
        uci batch <<-EOF
            set "$PSUCI".lag.ports=""
            commit "$PSUCI"
		EOF
    fi
    return
}

stop() {
    disable_lag
    return
}

#******** main ********#
case "$1" in
start)
    start
    ;;
stop)
    stop
    ;;
restart)
    stop
    start
    ;;
status)
    get_lag_status
    ;;
*) ;;

esac
return 0
