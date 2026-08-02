#!/bin/sh

arch_pm_extra_rebuild_map() {
    local lag_enable=$(uci -q get port_service.lag.enable)
    local lag_ports=$(uci -q get port_service.lag.ports)
    local port_2_base_iface=$(uci -q get port_map.2.base_iface)

    if [ "$lag_enable" = "1" ] && [ "$lag_ports" = "1 2" -o "$lag_ports" = "3 4" ]; then
        [ "eth1" = "$port_2_base_iface" ] && return
        uci -q batch <<-EOF
            set port_map."1".cpu_port="5"
            set port_map."1".ifname="eth0.1"
            set port_map."1".base_iface="eth0"
            set port_map."2".cpu_port="0"
            set port_map."2".ifname="eth1.2"
            set port_map."2".base_iface="eth1"
            set port_map."3".cpu_port="5"
            set port_map."3".ifname="eth0.3"
            set port_map."3".base_iface="eth0"
            set port_map."4".cpu_port="0"
            set port_map."4".ifname="eth1.4"
            set port_map."4".base_iface="eth1"
            set port_map.settings.last_vlan_type=""
            commit port_map
	EOF
    else
        [ "eth0" = "$port_2_base_iface" ] && return
        uci -q batch <<-EOF
            set port_map."1".cpu_port="5"
            set port_map."1".ifname="eth0.1"
            set port_map."1".base_iface="eth0"
            set port_map."2".cpu_port="5"
            set port_map."2".ifname="eth0.2"
            set port_map."2".base_iface="eth0"
            set port_map."3".cpu_port="0"
            set port_map."3".ifname="eth1.3"
            set port_map."3".base_iface="eth1"
            set port_map."4".cpu_port="0"
            set port_map."4".ifname="eth1.4"
            set port_map."4".base_iface="eth1"
            set port_map.settings.last_vlan_type=""
            commit port_map
	EOF
    fi
}

