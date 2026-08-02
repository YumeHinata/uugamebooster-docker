#!/bin/ash

uci -q get firewall_cpp.anti_attack > /dev/null || {
    uci set firewall_cpp.anti_attack=params
    uci commit firewall_cpp
}

uci -q get firewall.ipmacBind > /dev/null || {
    uci -q batch <<EOF
    set firewall.ipmacBind=include
    set firewall.ipmacBind.path='/lib/firewall.sysapi.loader ipmacBind'
    set firewall.ipmacBind.reload='1'
    set firewall.ipmacBind.enabled='1'
    set firewall.ipmacBind.status='off'
    commit firewall
EOF
}
