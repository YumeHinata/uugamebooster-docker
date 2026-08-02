#!/bin/sh

arch_network_router_mode_init() { return; }
arch_network_re_mode_init()     { return; }
arch_network_ap_mode_init()     { return; }
arch_network_re_open()          { return; }

. /lib/miwifi/arch/lib_arch_accel.sh

_ecm_accel_mode_init() {
    _is_qos_enable && return
    [ "$(uci -q get ecm.global.acceleration_engine)" = "auto" ] && return

    uci -q batch <<EOF
        del ecm.global.service
        set ecm.global.acceleration_engine="auto"
        commit ecm
EOF

    /sbin/accelctrl restart
}

_ecm_enable_edma_loopback() {
    echo 1 > /sys/kernel/debug/qca-nss-ppe/stats/loopback_enable
}

_lan_mac_init() {
    lan_mac=$(getmac lan)
    [ -n "$lan_mac" ] && {
        ip link set dev eth0 address "$lan_mac"
        ip link set dev eth1 address "$lan_mac"
        uci -q batch <<EOF
            set network.eth0_dev.macaddr="$lan_mac"
            set network.eth1_dev.macaddr="$lan_mac"
            commit network
EOF

    }
}

arch_network_extra_init() {
    _lan_mac_init

    echo 1 > /sys/ssdk/dev_id

    _ecm_accel_mode_init
    _ecm_enable_edma_loopback
}
