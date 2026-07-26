#!/bin/ash

arch_wlan_ch_usage()    { return 0; }
arch_mesh_bh_rssi()     { return 0; }
arch_sys_thermal_data()    { return 0; }
arch_wlan_ax_tx_mu_data() { return 0; }
arch_wlan_ax_rx_mu_data() { return 0; }

[ -f "/lib/miwifi/arch/lib_arch_sp_colls.sh" ] && . /lib/miwifi/arch/lib_arch_sp_colls.sh

hotplug_check_down() {
	local iface=$1
	local wan_port
	local zone_name

	# Filter original network interface
	if ! echo "$iface" | grep -qsE "^eth"; then
		return
	fi

	wan_port=$(uci -q get network.wan.ifname)
	wan2_port=$(uci -q get network.wan_2.ifname)
	zone_name=lan

	if [ "${iface/_/.}" = "$wan_port" ]; then
		zone_name=wan
	elif [ "${iface/_/.}" = "$wan2_port" ]; then
		zone_name=wan2
	fi

	if which sp_log_info.sh >/dev/null; then
		sp_log_info.sh -k net.phy.down -m "$zone_name:1"
	fi
}

net_phy_link() {
	local status=$(phyhelper dump)
	echo "$status" | awk '{print $1 $4}' | sed 's/Speed://i'
	echo "$status" | awk '$7=="wan" || $7=="wan_2" {print toupper($7 $4)}' | sed 's/Speed//i' | tr -d _
}

wlan_ch_usage() {
	arch_wlan_ch_usage
}

mesh_bh_rssi() {
	arch_mesh_bh_rssi
}

sys_thermal_data() {
	arch_sys_thermal_data
}

wlan_ax_tx_mu_data() {
	arch_wlan_ax_tx_mu_data
}

wlan_ax_rx_mu_data() {
	arch_wlan_ax_rx_mu_data
}

