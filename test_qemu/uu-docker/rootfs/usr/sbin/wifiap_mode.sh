#!/bin/sh
# Copyright (C) 2014 Xiaomi

#
# $1 = opt. open/close
# usage:
#	wifiap_mode.sh open/close
#

wifiap_open() { return 0; }
wifiap_close() { return 0; }
util_plugin_restart() { return 0; }

. /lib/functions.sh
. /lib/miwifi/miwifi_core_libs.sh

usage() {
	echo "usage:"
	echo "	wifiap_mode.sh opt=open/close/check_gw"
	echo "	example1:  wifiap_mode.sh open"
	echo "	example2:  wifiap_mode.sh close"
	echo "	example2:  wifiap_mode.sh check_gw"
}

#$1 : log message
log()
{
	logger -t wifiap "$1"
}

#return value 1: gw ip unreachable;
#return value 0: gw ip exists
check_gw()
{
	local gw_ip

	gw_ip=$(uci get network.lan.gateway)
	log "current gateway ip $gw_ip"
	[ -z "$gw_ip" ] && return 0

	if arping "$gw_ip" -q -I br-lan -c 3; then
        bridgeap_logger "current gateway ip $gw_ip, gw ip exists."
        return 0
    else
        bridgeap_logger "current gateway ip $gw_ip, gw ip unreachable."
        return 1
    fi
}

# return value 1: not ap mode
# return value 0: ap mode;
check_apmode()
{
	local netmode

	netmode=$(uci get xiaoqiang.common.NETMODE)
	log "network apmode $netmode."

	[ "$netmode" = "wifiapmode" ] && return 0
	log "network apmode $netmode false."
	return 1
}

check_gw_stop()
{
	grep -v "/usr/sbin/wifiap_mode.sh check_gw" /etc/crontabs/root > /etc/crontabs/root.new
	mv /etc/crontabs/root.new /etc/crontabs/root
	/etc/init.d/cron restart
}

check_gw_start()
{
	grep -v "/usr/sbin/wifiap_mode.sh check_gw" /etc/crontabs/root > /etc/crontabs/root.new
	echo "*/1 * * * * /usr/sbin/wifiap_mode.sh check_gw" >> /etc/crontabs/root.new
	mv /etc/crontabs/root.new /etc/crontabs/root
	/etc/init.d/cron restart
}

_network_restart_finish_callback() {
	while true; do
		pgrep -f "/etc/init.d/network" > /dev/null 2>&1 || break;
		sleep 1
	done
	/usr/sbin/port_service restart
	phyhelper restart lan
}

_network_restart() {
	/etc/init.d/network restart
	_network_restart_finish_callback &
}

_add_alias_ip() {
	local alias_ip
	if [ -f "/usr/sbin/get_alias_ip" ]; then
		alias_ip=$(get_alias_ip)
		if [ -n "$alias_ip" ]; then
			uci -q batch <<-EOF >/dev/null
				set network.lan_alias=alias
				set network.lan_alias.interface='lan'
				set network.lan_alias.proto='static'
				set network.lan_alias.netmask='255.255.255.0'
				set network.lan_alias.ipaddr="$alias_ip"
				commit network
			EOF
		fi
	fi
}
_del_alias_ip() {
	local alias="$(uci -q get network.lan_alias)"
	if [ -n "$alias" ]; then
		uci -q batch <<-EOF >/dev/null
			del network.lan_alias
			commit network
		EOF
	fi
}

apcli_is_connect()
{
    local apcli=$(uci -q get xiaoqiang.common.active_apcli)
    [ -z "$apcli" ] && return 1

    if [ -n "$(iwconfig $apcli | sed -ne 's/.*Access Point:.*\(Not-Associated\).*$/\1/p')" ]; then
        return 1
    fi
    return 0
}

OPT=$1

[ $# -ne 1 ] && {
	usage
	exit 1
}

case $OPT in
	open)

		_add_alias_ip
		wifiap_open
		/usr/sbin/port_service restart
		/etc/init.d/ipv6 ip6_fw close
		/etc/init.d/firewall restart
		/etc/init.d/odhcpd stop
		/etc/init.d/miqos stop
		_network_restart
		#/etc/init.d/wan_check restart
		ubus call wan_check reset &
		/etc/init.d/trafficd restart
		/etc/init.d/xiaoqiang_sync restart
		/usr/sbin/shareUpdate -b
		/etc/init.d/xqbc restart

		# accelleration hook event
		network_accel_hook "wifiap" "open"

		util_plugin_restart
		[ -f /etc/init.d/minet ] && /etc/init.d/minet restart
		/etc/init.d/tbusd stop

		check_gw_start

		[ -f /etc/init.d/cab_meshd ] && /etc/init.d/cab_meshd stop
		[ -f /etc/init.d/miwifi-discovery ] && /etc/init.d/miwifi-discovery restart
		[ -f /etc/init.d/mosquitto ] && /etc/init.d/mosquitto restart
		[ -f /etc/init.d/xq_info_sync_mqtt ] && /etc/init.d/xq_info_sync_mqtt restart
		[ -f /etc/init.d/topomon ] && /etc/init.d/topomon restart
		[ -f /etc/init.d/guestwifi_separation ] && /etc/init.d/guestwifi_separation restart
		[ -f /etc/init.d/bridge_ipv6 ] && /etc/init.d/bridge_ipv6 restart
		[ -f /etc/init.d/qos2 ] && /etc/init.d/qos2 restart
		[ -f /etc/init.d/local_gw_security ] && /etc/init.d/local_gw_security restart

		return $?
	;;

	close)

		_del_alias_ip
		wifiap_close
		[ -f /etc/init.d/bridge_ipv6 ] && /etc/init.d/bridge_ipv6 stop
		/etc/init.d/ipv6 ip6_fw open
		/etc/init.d/firewall restart
		/etc/init.d/odhcpd start

		inittd=$(uci -q get xiaoqiang.common.INITTED)
		mesh_support=$(uci -q get misc.features.supportMesh)
		if [ "$mesh_support" -eq 1 ]; then
			support_meshv4=$(mesh_cmd support_mesh_version 4)
			if [ "$inittd" = "YES" ] && [ "$support_meshv4" = "1" ]; then
				/usr/sbin/mesh_connect.sh init_cap 2
			fi
		fi

		_network_restart
		#/etc/init.d/wan_check restart
		ubus call wan_check reset &
		/etc/init.d/trafficd restart
		/etc/init.d/xiaoqiang_sync stop
		/usr/sbin/shareUpdate -b
		/etc/init.d/dnsmasq enable
		/etc/init.d/dnsmasq restart
		/etc/init.d/xqbc restart
		/etc/init.d/miqos start
		/etc/init.d/tbusd start
		util_plugin_restart

		check_gw_stop

		# accelleration hook event
		network_accel_hook "wifiap" "close"

		[ -f /etc/init.d/minet ] && /etc/init.d/minet restart
		[ -f /etc/init.d/cab_meshd ] && /etc/init.d/cab_meshd restart
		[ -f /etc/init.d/miwifi-discovery ] && /etc/init.d/miwifi-discovery restart
		[ -f /etc/init.d/mosquitto ] && /etc/init.d/mosquitto restart
		[ -f /etc/init.d/xq_info_sync_mqtt ] && /etc/init.d/xq_info_sync_mqtt restart
		[ -f /etc/init.d/topomon ] && /etc/init.d/topomon restart
		[ -f /etc/init.d/guestwifi_separation ] && /etc/init.d/guestwifi_separation restart
		[ -f /etc/init.d/qos2 ] && /etc/init.d/qos2 restart
		[ -f /etc/init.d/local_gw_security ] && /etc/init.d/local_gw_security restart

		return $?
	;;

	check_gw)

		log "check apmode."
		check_apmode || exit 0

		log "check apcli_is_connect."
		apcli_is_connect || exit 0

		log "check gateway."
		check_gw && exit 0

		# in bridge ap mode and gateway unreachable, we had to run dhcp renew issue;
		# if can't renew ipaddr, script should  exit. otherwise, restart network && lan
		log "gateway changed, try dhcp renew."
		lan_ipaddr_ori=$(uci -q get network.lan.ipaddr)

		/usr/sbin/dhcp_apclient.sh start br-lan
		lan_ipaddr_now=$(uci -q get network.lan.ipaddr)
		[ "$lan_ipaddr_ori" = "$lan_ipaddr_now" ] && exit 0
		matool --method setKV --params "ap_lan_ip" "$lan_ipaddr_now"

		log "gateway changed, try lan restart"
		phyhelper restart lan
		log "gateway changed, lan ip changed from $lan_ipaddr_ori to $lan_ipaddr_now."
		_network_restart
		exit 0
	;;

	* )
		echo "usage:" >&2
	;;
esac
