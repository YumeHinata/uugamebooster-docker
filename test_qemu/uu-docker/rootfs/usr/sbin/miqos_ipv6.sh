#/bin/sh

QOS_ID="miqos_id"
IPT_CMD="ip6tables -t mangle"

readonly LOCK_FILE="/tmp/miqos_ipv6.lock"
exec 300>$LOCK_FILE
flock -w 6 300 || {
    logger -t "miqos_ipv6.sh" "Get lock fialed, $0 run failed !"
    exit 1
}

. /lib/functions.sh

init_ipt_rule() {
    $IPT_CMD -N $QOS_ID >/dev/null 2>&1
    $IPT_CMD -C FORWARD -j $QOS_ID >/dev/null 2>&1 || $IPT_CMD -A FORWARD -j $QOS_ID
}

uninit_ipt_rule() {
    $IPT_CMD -C FORWARD -j $QOS_ID >/dev/null 2>&1 && $IPT_CMD -D FORWARD -j $QOS_ID
    $IPT_CMD -F $QOS_ID
    $IPT_CMD -X $QOS_ID
}

update_ipt_rule() {
    $IPT_CMD -F $QOS_ID

    config_load miqos
    function miqos_group_process() {
        local mac=""
        config_get mac $1 name
        [ "$mac" != "00" ] && add_ipt_rule $mac
    }

    config_foreach miqos_group_process group
}

add_ipt_rule() {
    local mac="$1"
    [ -z "$mac" ] && return

    local section_name=${mac//:/}
    uci -q get miqos.$section_name > /dev/null || return

    local ip="$(ubus call trafficd hw | jsonfilter -e "@['$mac']['ip_list'][0]['ip']")"
    [ -z "$ip" ] && return

    local max_grp_uplink=$(uci -q get miqos.$section_name.max_grp_uplink)
    local max_grp_downlink=$(uci -q get miqos.$section_name.max_grp_downlink)
    [ "$max_grp_uplink" = "0" -a "$max_grp_downlink" = "0" ] && return

    local id=${ip##*.}
    local mark="0x$(printf "%02x" $id)000000/0xff000000"

    $IPT_CMD -A $QOS_ID -m mac --mac-source $mac -j MARK --set-mark $mark
    $IPT_CMD -A $QOS_ID -m mac --mac-destination $mac -j MARK --set-mark $mark
}

del_ipt_rule() {
    local mac="$1"
    local match_str="$QOS_ID -m mac --mac-.* $mac -j MARK --set-xmark"
    local rules=$(ip6tables-save | grep "$match_str" | sed 's/-A/-D/g')

    echo "$rules" | while read -r rule; do
        [ -n "$rule" ] && $IPT_CMD $rule
    done
}

clear_ipv6_ct_rule() {
    echo "ipv6" > /proc/net/nf_conntrack
}

case $1 in
    "init")
        init_ipt_rule
        update_ipt_rule
        clear_ipv6_ct_rule
        ;;
    "uninit")
        uninit_ipt_rule
        ;;
    "update")
        update_ipt_rule
        clear_ipv6_ct_rule
        ;;
    "add")
        del_ipt_rule $2
        add_ipt_rule $2
        clear_ipv6_ct_rule
        ;;
    "del")
        del_ipt_rule $2
        ;;
    *)
        ;;
esac
