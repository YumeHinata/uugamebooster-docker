#!/bin/sh
# Copyright (C) 2015 Xiaomi

readonly NETWORK_NAME="guest"
guest_ip="192.168.33.1"
guest_netmask="255.255.255.0"
network_ifname=""
network_device=""


guest_usage() {
	echo "$0:"
	echo "    open: start guest wifi, delete all config"
	echo "         $0  open guest_ssid encryption_type password"
	echo "    close: stop guest wifi, delete all config"
	echo "    enable:  enable guest wifi, need start first"
	echo "    disable: disable guest wifi, need start first"
}

guest_ip_make() {

	local new_ip=$(/usr/sbin/ip_conflict.sh guest-wifi $guest_ip $guest_netmask)

	[ "$new_ip" != "0.0.0.0" ] && guest_ip=$new_ip
}

guest_add() {
	local ssid="$1"
	local encryption="$2"  #mixed-psk
	local key="$3"  #12345678
	[ -z "$1" ] && ssid="xiaomi_guest"
	[ -z "$2" ] && { encryption="none"; key=""; }

	guest_ip_make

	#wifi
	local guest_2G=$(uci -q get wireless.${NETWORK_NAME}_2G)
	if [ -z "$guest_2G" ]; then
		uci -q batch <<-EOF >/dev/null
			set wireless.${NETWORK_NAME}_2G=wifi-iface
			set wireless.${NETWORK_NAME}_2G.ifname=$network_ifname_2G
			set wireless.${NETWORK_NAME}_2G.network=$NETWORK_NAME
			set wireless.${NETWORK_NAME}_2G.encryption=$encryption
			set wireless.${NETWORK_NAME}_2G.device=$network_device_2G
			set wireless.${NETWORK_NAME}_2G.key=$key
			set wireless.${NETWORK_NAME}_2G.mode=ap
			set wireless.${NETWORK_NAME}_2G.ap_isolate=1
			set wireless.${NETWORK_NAME}_2G.closingTime=0
			set wireless.${NETWORK_NAME}_2G.ssid=$ssid
			set wireless.${NETWORK_NAME}_2G.disabled=0
			commit wireless
		EOF
	else
		uci -q batch <<-EOF >/dev/null
			set wireless.${NETWORK_NAME}_2G.ap_isolate=1
			commit wireless
		EOF
	fi

	local guest_5G=$(uci -q get wireless.${NETWORK_NAME}_5G)
	if [ -z "$guest_5G" ]; then
		uci -q batch <<-EOF >/dev/null
			set wireless.${NETWORK_NAME}_5G=wifi-iface
			set wireless.${NETWORK_NAME}_5G.ifname=$network_ifname_5G
			set wireless.${NETWORK_NAME}_5G.network=$NETWORK_NAME
			set wireless.${NETWORK_NAME}_5G.encryption=$encryption
			set wireless.${NETWORK_NAME}_5G.device=$network_device_5G
			set wireless.${NETWORK_NAME}_5G.key=$key
			set wireless.${NETWORK_NAME}_5G.mode=ap
			set wireless.${NETWORK_NAME}_5G.ap_isolate=1
			set wireless.${NETWORK_NAME}_5G.closingTime=0
			set wireless.${NETWORK_NAME}_5G.ssid=$ssid
			set wireless.${NETWORK_NAME}_5G.disabled=0
			commit wireless
		EOF
	else
		uci -q batch <<-EOF >/dev/null
			set wireless.${NETWORK_NAME}_5G.ap_isolate=1
			commit wireless
		EOF
	fi

	#network
	local guest_network=$(uci -q get network.${NETWORK_NAME})
	if [ -z "$guest_network" ]; then
		uci -q batch <<-EOF >/dev/null
			set network.${NETWORK_NAME}=interface
			set network.${NETWORK_NAME}.ifname=" "
			set network.${NETWORK_NAME}.bridge_empty=1
			set network.${NETWORK_NAME}.type=bridge
			set network.${NETWORK_NAME}.proto=static
			set network.${NETWORK_NAME}.ipaddr=$guest_ip
			set network.${NETWORK_NAME}.netmask=$guest_netmask
			commit network
		EOF
	else
		#clean guestwifi ifname="eth0.3" for history fault
		uci -q batch <<-EOF >/dev/null
			set network.${NETWORK_NAME}.ifname=" "
			commit network
		EOF
	fi

	#dhcp
	local guest_dhcp=$(uci -q get dhcp.${NETWORK_NAME})
	[ -z "$guest_dhcp" ] && {
		uci -q batch <<-EOF >/dev/null
			set dhcp.${NETWORK_NAME}=dhcp
			set dhcp.${NETWORK_NAME}.interface=$NETWORK_NAME
			set dhcp.${NETWORK_NAME}.start=100
			set dhcp.${NETWORK_NAME}.limit=150
			set dhcp.${NETWORK_NAME}.leasetime=12h
			set dhcp.${NETWORK_NAME}.force=1
			add_list dhcp.${NETWORK_NAME}.dhcp_option_force="43,XIAOMI_ROUTER"
			commit dhcp
		EOF
	}

	#firewall
	local guest_firewall=$(uci -q get firewall.${NETWORK_NAME}_forward)
	[ -z "$guest_firewall" ] && {
		uci -q batch <<-EOF >/dev/null
			set firewall.guest=include
			set firewall.guest.type='script'
			set firewall.guest.path='/lib/firewall.sysapi.loader guest'
			set firewall.guest.enabled='1'
			set firewall.guest.reload='1'
			commit firewall
		EOF
	}
}

guest_delete() {
	uci -q batch <<-EOF >/dev/null
		delete firewall.guest

		delete wireless.${NETWORK_NAME}_2G
		delete wireless.${NETWORK_NAME}_5G
		delete network.${NETWORK_NAME}
		delete dhcp.${NETWORK_NAME}

		commit firewall
		commit wireless
		commit network
		commit dhcp
	EOF
}

_firewall_restart() {
	/usr/sbin/sysapi guest "$1"
}

guest_start() {
	local ssid="$1"
	local encryption="$2"  #mixed-psk
	local key="$3"  #12345678

	guest_add "$ssid" "$encryption" "$key"

	ubus call network reload
	/sbin/wifi update
	/etc/init.d/dnsmasq restart
	_firewall_restart set
	/etc/init.d/xq_info_sync_mqtt restart
	return 0
}

guest_stop() {
	guest_delete

	ubus call network reload
	/sbin/wifi update
	/etc/init.d/dnsmasq restart
	_firewall_restart clean
	/etc/init.d/xq_info_sync_mqtt restart
	return 0
}


network_ifname_2G=$(uci -q get misc.wireless.ifname_guest_2G)
[ -z "$network_ifname_2G" ] && exit 1
network_ifname_5G=$(uci -q get misc.wireless.ifname_guest_5G)
[ -z "$network_ifname_5G" ] && exit 1
network_device_2G=$(uci -q get misc.wireless.if_2G)
[ -z "$network_device_2G" ] && exit 1
network_device_5G=$(uci -q get misc.wireless.if_5G)
[ -z "$network_device_5G" ] && exit 1

OPT=$1
case $OPT in
	open)
		guest_start "$2" "$3" "$4"
		return $?
	;;
	close)
		guest_stop
		return $?
	;;
	* )
		guest_usage
		return 0
	;;
esac



