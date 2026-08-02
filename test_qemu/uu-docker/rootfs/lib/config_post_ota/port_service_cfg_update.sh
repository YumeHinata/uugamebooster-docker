#!/bin/sh

uci -q get port_service.settings > /dev/null || {
    uci -q batch <<EOF
    set port_service.settings=common
    set port_service.settings.router_services="game lag iptv wan wan_2"
    set port_service.settings.ap_services="lag"
    set port_service.wantag_attr=attr
    set port_service.wantag_attr.vid='-1'
    set port_service.wantag_attr.priority='-1'
    set port_service.wantag_attr.profile='0'
    commit port_service
EOF
}

uci -q get port_map.settings.vlan_type > /dev/null || {
    uci -q batch <<EOF
    set port_map.settings.vlan_type="8021q"
    commit port_map
EOF
}
