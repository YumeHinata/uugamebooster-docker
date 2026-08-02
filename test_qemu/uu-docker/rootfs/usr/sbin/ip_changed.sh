#!/bin/sh
# restart some services depends on lanip, while lanip changed

. /lib/functions.sh

LOG() {
	logger -t ip_changed.sh -p info "$@"
}

usage() {
	printf "usage:\n"
	printf "\tip_changed.sh lan : lan ip changed, reload related services\n"
	printf "\tip_changed.sh wan : wan ip changed, reload related services\n"
	printf "\tip_changed.sh guest : guest ip changed, reload related services\n"
	printf "\tip_changed.sh miot : miot ip changed, reload related services\n"
	printf "\tip_conflict.sh : print this message\n"
}

ip_aton() {
	echo $1 | awk '{c=256;split($0,str,".");print str[4]+str[3]*c+str[2]*c^2+str[1]*c^3}'
}

ip_ntoa() {
	local a1=$(($1 & 0xFF))
	local a2=$((($1 >> 8) & 0xFF))
	local a3=$((($1 >> 16) & 0xFF))
	local a4=$((($1 >> 24) & 0xFF))
	echo "$a4.$a3.$a2.$a1"
}

is_same_subnet() {
	local ip1=$1
	local netmask1=$2
	local ip2=$3
	local netmask2=$4

	# default to the same subnet
	[ -z "$netmask2" ] && echo 1 && return

	local ip1_int=$(ip_aton $ip1)
	local netmask1_int=$(ip_aton $netmask1)
	local ip2_int=$(ip_aton $ip2)
	local netmask2_int=$(ip_aton $netmask2)

	[ $(($ip1_int & $netmask1_int)) -eq $(($ip2_int & $netmask1_int)) ] && echo 1 && return
	[ $(($ip1_int & $netmask2_int)) -eq $(($ip2_int & $netmask2_int)) ] && echo 1 && return

	echo 0
}

redhcp_eth_stas() {
	/sbin/phyhelper restart lan
}

redhcp_wifi_stas() {
	/sbin/wifi kickmacs &
}

redhcp_all_stas() {
	redhcp_eth_stas
	redhcp_wifi_stas
}

lan_changed() {
	LOG "lanip range changged, reload related service, net_mode=$NETMODE"
	local old_ip="$1"
	local old_netmask="$2"
	local new_ip="$3"
	local new_netmask="$4"
	local same_subnet=

	[ -n "$new_netmask" ] && {
		same_subnet=$(is_same_subnet $old_ip $old_netmask $new_ip $new_netmask)
		[ "$same_subnet" = "1" ] && [ "$old_ip" = "$new_ip" ] && return
		LOG "old: $old_ip/$old_netmask ---> new: $new_ip/$new_netmask"
	}

	case "$NETMODE" in
		whc_cap)
			sleep 4
			/etc/init.d/network restart 2>/dev/null
			/etc/init.d/dnsmasq restart 2>/dev/null
			/usr/sbin/dhcp_apclient.sh restart 2>/dev/null
			/etc/init.d/trafficd restart 2>/dev/null
			/etc/init.d/minet restart 2>/dev/null
			[ -x "/etc/init.d/mosquitto" ] && /etc/init.d/mosquitto restart 2>/dev/null
			[ -x "/etc/init.d/xq_info_sync_mqtt" ] && /etc/init.d/xq_info_sync_mqtt restart 2>/dev/null
			/usr/sbin/shareUpdate -b 2>/dev/null
			[ -x "/usr/sbin/port_service" ] && /usr/sbin/port_service restart
			/usr/sbin/topomon_action.sh cap_init
			;;
		whc_re)
			/etc/init.d/xqbc restart 2>/dev/null
			[ -x "/etc/init.d/xq_info_sync_mqtt" ] && /etc/init.d/xq_info_sync_mqtt restart 2>/dev/null
			#/etc/init.d/topomon restart 2>/dev/null
			/etc/init.d/messagingagent.sh restart 2>/dev/null
			[ "$same_subnet" = "0" ] && redhcp_all_stas
			;;
		lanapmode)
			is_easymesh=$(uci -q get misc.mesh.easymesh)
			/etc/init.d/xqbc restart 2>/dev/null
			if [ "$is_easymesh" = "1" ]; then
				if [ "$ROLE" = "controller" ]; then
					/usr/sbin/topomon_action.sh cap_init
				fi
			else
				if [ "$CAP_MODE" = "ap" ]; then
					/etc/init.d/mosquitto restart 2>/dev/null
					[ -x "/etc/init.d/xq_info_sync_mqtt" ] && /etc/init.d/xq_info_sync_mqtt restart 2>/dev/null
					/usr/sbin/topomon_action.sh cap_init
				fi
			fi
			[ "$same_subnet" = "0" ] && redhcp_all_stas
			;;
		wifiapmode)
			/etc/init.d/xqbc restart 2>/dev/null
			[ "$same_subnet" = "0" ] && redhcp_all_stas
			;;
		*) # router
			sleep 4
			/etc/init.d/network restart 2>/dev/null
			/etc/init.d/dnsmasq restart 2>/dev/null
			/usr/sbin/dhcp_apclient.sh restart 2>/dev/null
			/etc/init.d/trafficd restart 2>/dev/null
			/etc/init.d/minet restart 2>/dev/null
			[ -x "/etc/init.d/mosquitto" ] && /etc/init.d/mosquitto restart 2>/dev/null
			/usr/sbin/shareUpdate -b 2>/dev/null
			;;
	esac

	# for any NETMODE
	[ -x "/etc/init.d/miio_client" ] && /etc/init.d/miio_client restart

    mesh_support=$(uci -q get misc.features.supportMesh)
    if [ $mesh_support -eq 1 ]; then
	# for Mesh4.0
	if [ "$(mesh_cmd support_mesh_version 4)" ] && [ "$NETMODE" != "wifiapmode" ]; then
		ubus call miwifi-discovery ip_changed 2>>/dev/null
	fi
    fi
}

wan_changed() {
	LOG "wan ip changged, reload related service, net_mode=$NETMODE"

	# maybe handle wanlan conflict here
	# /usr/sbin/ip_conflict.sh newlanip
}

guest_changed() {
	LOG "guest ip changged, reload related service, net_mode=$NETMODE"
	local guest_2g_iface=$(uci -q get wireless.guest_2G.ifname)
	local guest_5g_iface=$(uci -q get wireless.guest_5G.ifname)
	local guest_5gh_iface=$(uci -q get wireless.guest_5GH.ifname)
	local guest_iflist="$guest_2g_iface $guest_5g_iface $guest_5gh_iface"

	/etc/init.d/xq_info_sync_mqtt restart

	redhcp_eth_stas
	for iface in $guest_iflist; do
		/sbin/wifi kickmacs $iface
	done
}

miot_changed() {
	LOG "miot ip changged, reload related servicem, net_mode=$NETMODE"
	local miot_2g_iface=$(uci -q get wireless.miot_2G.ifname)

	redhcp_eth_stas
	/sbin/wifi kickmacs $miot_2g_iface
}

NETMODE=$(uci -q get xiaoqiang.common.NETMODE)
CAP_MODE=$(uci -q get xiaoqiang.common.CAP_MODE)
ROLE=$(uci -q get xiaoqiang.common.EASYMESH_ROLE)

CMD=$1
shift
case "$CMD" in
	lan)
		lan_changed "$@"
		;;
	wan)
		wan_changed
		;;
	guest)
		guest_changed
		;;
	miot)
		miot_changed
		;;
	*)
		usage
		;;
esac
