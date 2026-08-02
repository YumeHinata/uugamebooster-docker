#!/bin/sh 

# mimesh upper abstract layer support

. /lib/mimesh/mimesh_public.sh
. /lib/miwifi/miwifi_core_libs.sh

nw_cfg="/tmp/log/nw_cfg"

# check bh white mac_list, return mac_list if valid
# $1 input type, 2g/5g
# $2 output mac_list after check
__check_bh_vap_mac_list()
{
	local mac_idx mac_list_t mac
	local type="$1"
	local macnum="`eval echo '$'{bh_macnum_"${type}"g}`"
	local maclist="`eval echo '$'{bh_maclist_"${type}"g}`"
	[ -n "${maclist}" ] && {
		for mac_idx in $(seq 1 ${macnum}); do
			mac="`echo $maclist | awk -F ',' '{print $jj}' jj="$mac_idx"`"
			mac="`echo $mac | sed 's/ //g' | sed 'y/abcdef/ABCDEF/'`"
			echo "$mac" | grep -q -o -E '^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$' && {
				mac_list_t="${mac_list_t}${mac_list_t:+","}${mac}"
			}
		done
	}
	eval "$2=$mac_list_t"
}

__init_wifi_cap()
{
	MIMESH_LOGI " setup wifi cfg on CAP "

	# detect 2g wifi-iface index
	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g_index=$(uci show wireless |grep -w "ifname=\'$ifname_2g\'" | cut -d '[' -f2 | cut -d ']' -f1)

	# detect 5g wifi-iface index
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g_index=$(uci show wireless |grep -w "ifname=\'$ifname_5g\'" | cut -d '[' -f2 | cut -d ']' -f1)

	local is_tri_band=$(mesh_cmd is_tri_band)
	if [ "$is_tri_band" = "1" ]; then
		# detect 5gh wifi-iface index
		local ifname_5gh=$(uci -q get misc.wireless.ifname_5GH)
		local iface_5gh_index=$(uci show wireless |grep -w "ifname=\'$ifname_5gh\'" | cut -d '[' -f2 | cut -d ']' -f1)
	fi

	# config wifi ap ifaces
	local ii=0
	local iface_list="$iface_2g_index $iface_5g_index $iface_5gh_index"
	for ii in ${iface_list}; do
		uci -q set wireless.@wifi-iface[$ii].wnm='1'
		uci -q set wireless.@wifi-iface[$ii].rrm='1'
		uci -q set wireless.@wifi-iface[$ii].miwifi_mesh='0'
		uci -q set wireless.@wifi-iface[$ii].backhaul=
	done

	local block_list_5g=$(uci -q get wireless.@wifi-iface[$iface_5g_index].channel_block_list)
	[ -n "$block_list_5g" ] || {
		uci -q set wireless.@wifi-iface[$iface_5g_index].channel_block_list='52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165'
	}

	[ -n "$iface_5gh_index" ] && {
		local block_list_5gh=$(uci -q get wireless.@wifi-iface[$iface_5gh_index].channel_block_list)
		[ -n "$block_list_5gh" ] || {
			uci -q set wireless.@wifi-iface[$iface_5gh_index].channel_block_list='52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165'
		}
	}

	__init_wifi_bh_ap $bh_ssid $bh_mgmt $bh_pswd
	uci commit wireless
}

# netmode: 1 setmode 0 clearmode
# mode: whc_cap/whc_re is used for trafficd tbus
__set_netmode()
{
	local swt="$1"
	local netmode=$(uci -q get xiaoqiang.common.NETMODE)

	# netmode
	if [ "$swt" -eq 0 ]; then
		uci -q delete xiaoqiang.common.NETMODE
		nvram set mode=Router
	else
		if [ "$2" = "cap" ]; then
			if [ "$netmode" = "wifiapmode" -o "$netmode" = "lanapmode" ]; then
				uci -q set xiaoqiang.common.CAP_MODE="ap"
			else
				uci -q set xiaoqiang.common.NETMODE="whc_cap"
			fi
		else
			local mode="whc_$2"
			uci -q set xiaoqiang.common.NETMODE="$mode"
			[ "$2" = "re" ] && nvram set mode=AP
		fi
	fi

	uci commit xiaoqiang
	nvram commit

	return 0
}

## network cfg init on RE
__init_network_re()
{
	MIMESH_LOGI " setup network cfg on $whc_role "

	[ -f "$nw_cfg" ] && {
		local ip="`cat $nw_cfg | awk -F ':' '/ip/{print $2}'`"
		[ -n "$ip" ] && {
			local subnet="`cat $nw_cfg | awk -F ':' '/subnet/{print $2}'`"
			local dns="`cat $nw_cfg | awk -F ':' '/dns/{print $2}'`"
			local router="`cat $nw_cfg | awk -F ':' '/router/{print $2}'`"
			local hostname="`cat $nw_cfg | awk -F ':' '/ap_hostname/{print $2}'`"
			local vendorinfo="`cat $nw_cfg | awk -F ':' '/vendorinfo/{print $2}'`"
			local netmask="${subnet:-255.255.255.0}"
			local mtu="${mtu:-1500}"
			local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)

			MIMESH_LOGI " @@@@@@ ============ mesh re set ip=$ip gw=$router."

			dns="${dns:-$router}"
			uci -q set xiaoqiang.common.ap_hostname=$hostname
			[ "$cap_mode" != "ap" ] && uci -q set xiaoqiang.common.vendorinfo="$vendorinfo"
			uci commit xiaoqiang

			uci -q set network.lan=interface
			uci -q set network.lan.type=bridge
			uci -q set network.lan.proto=dhcp
			uci -q set network.lan.ipaddr=$ip
			uci -q set network.lan.netmask=$netmask
			uci -q set network.lan.gateway=$router
			uci -q set network.lan.mtu=$mtu
			uci -q del network.lan.dns
			for d in $dns
			do
				uci -q add_list network.lan.dns=$d
			done

			/usr/sbin/ip_conflict.sh br-lan
		}
	}

	uci -q set network.lan.proto=dhcp
	uci commit network
	
	/usr/sbin/vasinfo_fw.sh off 2>/dev/null
	/etc/init.d/trafficd stop
	/etc/init.d/odhcpd stop

	ifdown vpn 2>/dev/null

	# workaround for lan.ipaddr in multiple init situation
	kill -SIGUSR1 `pidof udhcpc | xargs` 2>/dev/null  
}

# params: bh_ssid,bh_mgmt,bh_pswd
__init_wifi_bh_ap()
{
	local bh_ssid=$1
	local bh_mgmt=$2
	local bh_pswd=$3

	local bh_band=$(mesh_cmd backhaul get real_band)
	local lanmac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local mesh_version=$(mesh_cmd max_mesh_version)

	local mld_dev=
	local mlo_radios=
	local radio_sets=
	local bh_mlo_support=$(mesh_cmd bh_mlo_support)
	if [ "$bh_mlo_support" = "1" ]; then
		mlo_radios=$(uci -q get misc.mld.bh_ap_mlo)
		radio_sets=$(echo $mlo_radios | tr '[A-Z]' '[a-z]')
		[ -n "$mlo_radios" ] && mld_dev=$(uci -q get misc.mld.bh_ap)
	fi

	local sec_name=""
	[ -z "$radio_sets" ] && radio_sets="$bh_band"
	for radio in ${radio_sets}; do
		[ "$bh_mlo_support" = "1" ] && sec_name="bh_ap_${radio}" || sec_name="bh_ap"
		local radio_upcase=$(echo $radio | tr '[a-z]' '[A-Z]')
		local bh_device=$(uci -q get misc.wireless.if_$radio_upcase)
		local bh_ifname=$(uci get misc.backhauls.backhaul_${radio}_ap_iface)
		local dev_macaddr="$(cat /sys/class/net/${bh_device}/address)"
		local vap_macaddr=""
		if [ "$radio" = "5g" -o "$radio" = "5gh" ]; then
			channel_block_list="52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165"
			if [ -z "$dev_macaddr" ]; then
				dev_macaddr=$lanmac
			fi
			vap_macaddr="$(calcbssid -i2 -m $dev_macaddr)"
		fi

		uci -q batch <<-EOF >/dev/null
			set wireless.$sec_name=wifi-iface
			set wireless.$sec_name.device="$bh_device"
			set wireless.$sec_name.ifname="$bh_ifname"
			set wireless.$sec_name.network='lan'
			set wireless.$sec_name.mode='ap'
			set wireless.$sec_name.channel_block_list='$channel_block_list'
			set wireless.$sec_name.ssid="$bh_ssid"
			set wireless.$sec_name.encryption="$bh_mgmt"
			set wireless.$sec_name.key="$bh_pswd"
			set wireless.$sec_name.hidden='1'
			set wireless.$sec_name.backhaul='1'
			set wireless.$sec_name.backhaul_ap='1'
			set wireless.$sec_name.wds='1'
			set wireless.$sec_name.wps_pbc='1'
			set wireless.$sec_name.wps_pbc_enable='0'
			set wireless.$sec_name.wps_pbc_start_time='0'
			set wireless.$sec_name.wps_pbc_duration='120'
			set wireless.$sec_name.group='0'
			set wireless.$sec_name.athnewind='1'
			set wireless.$sec_name.mesh_ver='$mesh_version'
			set wireless.$sec_name.mesh_apmac="$lanmac"
			set wireless.$sec_name.macaddr='$vap_macaddr'
			set wireless.$sec_name.disabled='1'
		EOF
		uci -q set wireless.$bh_device.CSwOpts='0x31'
		if [ "$ax_enable" != "0" ] && [ -n "$mlo_radios" ]; then
			uci -q set wireless.$sec_name.mld="$mld_dev"
			uci -q set wireless.$sec_name.disabled=0
		else
			uci -q set wireless.$sec_name.mld=
			[ "$bh_band" = "$radio" ] && uci -q set wireless.$sec_name.disabled=0
		fi
	done
	if [ -n "$mld_dev" ]; then
		uci -q batch <<-EOF >/dev/null
			set wireless.$mld_dev=wifi-mld
			set wireless.$mld_dev.mld_macaddr="$(mld_macaddr bh_ap)"
			set wireless.$mld_dev.mld_ssid="$bh_ssid"
		EOF
	fi
	uci commit wireless
}

# params: bh_ssid,bh_mgmt,bh_pswd,mlo_str
__init_wifi_bh_sta()
{
	local bh_ssid=$1
	local bh_mgmt=$2
	local bh_pswd=$3

	local bh_band=$(mesh_cmd backhaul get real_band)
	local bh_band_upcase=$(echo "$bh_band" | tr '[a-z]' '[A-Z]')
	local lanmac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local mesh_version=$(mesh_cmd max_mesh_version)

	# calculate the final mlo sets
	local mlo=""
	local mld_dev=""
	local local_mlo=""
	local bh_mlo_support=$(mesh_cmd bh_mlo_support)
	local mesh_id=$(uci -q get xiaoqiang.common.NETWORK_ID)

	if [ "$bh_mlo_support" = "1" ]; then
		mld_dev=$(uci -q get misc.mld.bh_sta)
		local_mlo=$(uci -q get misc.mld.sta_mlo)
		radio_sets=$(echo $local_mlo | tr '[A-Z]' '[a-z]')

		#format: 2g@00:11:22:33:44:55,5g@00:11:22:33:44:55,5g2@00:11:22:33:44:55
		local scan_iface=$(uci -q get misc.wireless.ifname_${bh_band_upcase})
		local mesh_mld=$(cfg80211tool $scan_iface g_mesh_mld 0x$mesh_id | sed -ne 's/.*g_mesh_mld:\(.*\),.*$/\1/p')
		if [ -n "$mesh_mld" ] && [ "${mesh_mld##*@}" != "$mesh_mld" ]; then
			local result=$(mesh_cmd mlo_members "$mesh_mld" "scan" "cfg80211tool")
			[ -n "$result" ] && mlo=$result
		fi

		if [ -n "$mld_dev" ] && [ -n "$mlo" ]; then
			local tmp_mlo=" $mlo "
			if [ "${tmp_mlo##* $bh_band }" = "${tmp_mlo}" ]; then
				if [ "${tmp_mlo##* 5gh }" != "${tmp_mlo}" ]; then
					bh_band="5gh"
				elif [ "${tmp_mlo##* 5g }" != "${tmp_mlo}" ]; then
					bh_band="5g"
				elif [ "${tmp_mlo##* 2g }" != "${tmp_mlo}" ]; then
					bh_band="2g"
				fi
			fi
		fi
		mesh_cmd backhaul set real_band $bh_band
	fi

	# create bh_sta wireless config, all bh_sta disabled default
	[ -z "$radio_sets" ] && radio_sets="$bh_band"
	for radio in ${radio_sets}; do
		[ "$bh_mlo_support" = "1" ] && sec_name="bh_sta_${radio}" || sec_name="bh_sta"
		local radio_upcase=$(echo $radio | tr '[a-z]' '[A-Z]')
		local bh_device=$(uci -q get misc.wireless.if_$radio_upcase)
		local bh_ifname=$(uci get misc.backhauls.backhaul_${radio}_sta_iface)
		local dev_macaddr="$(cat /sys/class/net/${bh_device}/address)"
		local vap_macaddr=""
		if [ "$radio" = "5g" -o "$radio" = "5gh" ]; then
			channel_block_list="52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165"
			vap_macaddr="$(calcbssid -i1 -m $dev_macaddr)"
		fi

		uci -q batch <<-EOF >/dev/null
			set wireless.$sec_name=wifi-iface
			set wireless.$sec_name.device="$bh_device"
			set wireless.$sec_name.ifname="$bh_ifname"
			set wireless.$sec_name.network='lan'
			set wireless.$sec_name.mode='sta'
			set wireless.$sec_name.ssid="$bh_ssid"
			set wireless.$sec_name.encryption="$bh_mgmt"
			set wireless.$sec_name.key="$bh_pswd"
			set wireless.$sec_name.wds='1'
			set wireless.$sec_name.wps_pbc='1'
			set wireless.$sec_name.wps_pbc_enable='0'
			set wireless.$sec_name.wps_pbc_start_time='0'
			set wireless.$sec_name.wps_pbc_duration='120'
			set wireless.$sec_name.disabled='1'
			set wireless.$sec_name.backhaul='1'
			set wireless.$sec_name.group='0'
			set wireless.$sec_name.athnewind='1'
			set wireless.$sec_name.mesh_mlolink='1'
			set wireless.$sec_name.macaddr='$vap_macaddr'
		EOF
	done

	# to enable real bh_sta
	# if uplink node is mld, enable all affiliated stas
	local radio_sets=$(echo $mlo | tr '[A-Z]' '[a-z]')
	[ -z "$radio_sets" ] && radio_sets="$bh_band"
	for radio in ${radio_sets}; do
		[ "$bh_mlo_support" = "1" ] && sec_name="bh_sta_${radio}" || sec_name="bh_sta"
		uci -q set wireless.$sec_name.disabled="$eth_init"
		[ -n "$mlo" ] && uci -q set wireless.$sec_name.mld="$mld_dev"
	done

	# update new real band and bhsta mlo cfg
	if [ -n "$mld_dev" ]; then
		uci -q batch <<-EOF >/dev/null
			set wireless.$mld_dev=wifi-mld
			set wireless.$mld_dev.mld_macaddr="$(mld_macaddr bh_sta)"
			set wireless.$mld_dev.mld_ssid="$bh_ssid"
			set wireless.bh_sta_mlo=wifi-mlo
			set wireless.bh_sta_mlo.mlo="$mlo"
		EOF
	fi
	uci commit wireless
}

## son wireless cfg init on RE
__init_wifi_re()
{
	MIMESH_LOGI " setup wifi cfg on $whc_role "

	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local device_5g=$(uci -q get misc.wireless.if_5G)

	# wifi, do NOT auto create wifi vap by repacd, setup vap and key parameters by user define
	uci -q set wireless.$device_5g.CSwOpts='0x31'
	ifconfig wifi2 >/dev/null 2>&1 && export WIFI2_EXIST=1 || export WIFI2_EXIST=0

	# detect 5b wifi-iface index
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')
	local iface_5g_index=$(uci show wireless |grep -w "ifname=\'$ifname_5g\'" | cut -d '[' -f2 | cut -d ']' -f1)

	# detect 2g wifi-iface index
	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_2g\'" | awk -F"." '{print $2}')
	local iface_2g_index=$(uci show wireless |grep -w "ifname=\'$ifname_2g\'" | cut -d '[' -f2 | cut -d ']' -f1)

	local is_tri_band=$(mesh_cmd is_tri_band)
	if [ "$is_tri_band" = "1" ]; then
		# detect 5gh wifi-iface index
		local ifname_5gh=$(uci -q get misc.wireless.ifname_5GH)
		local iface_5gh=$(uci show wireless | grep -w "ifname=\'$ifname_5gh\'" | awk -F"." '{print $2}')
		local iface_5gh_index=$(uci show wireless |grep -w "ifname=\'$ifname_5gh\'" | cut -d '[' -f2 | cut -d ']' -f1)
	fi

	local ii=0
	local iface_list="$iface_2g_index $iface_5g_index $iface_5gh_index"
	local main_ssid main_mgmt main_pswd

	# config wifi ap ifaces
	for ii in ${iface_list}; do
		uci -q set wireless.@wifi-iface[$ii].miwifi_mesh='0'
		[ "$ii" -ne "$iface_5g_index" -a "$ii" -ne "$iface_2g_index" ] && continue
		if [ "$bsd" -eq 0 ]; then
			if [ "$ii" -eq "$iface_5g_index" ]; then
				main_ssid=$ssid_5g
				main_mgmt=$mgmt_5g
				main_pswd=$pswd_5g
			else
				main_ssid=$ssid_2g
				main_mgmt=$mgmt_2g
				main_pswd=$pswd_2g
			fi
		else
			main_ssid=$whc_ssid
			main_mgmt=$whc_mgmt
			main_pswd=$whc_pswd
		fi
		uci -q set wireless.@wifi-iface[$ii].ssid="$main_ssid"
		uci -q set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
		uci -q set wireless.@wifi-iface[$ii].key="$main_pswd"
		uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].rrm='1'
EOF
		case "$main_mgmt" in
			none)
				uci -q delete wireless.@wifi-iface[$ii].key
			;;
			mixed-psk|psk2)
			;;
			psk2+ccmp)
				uci -q set wireless.@wifi-iface[$ii].sae='1'
				uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
				uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
			;;
			ccmp)
				uci -q delete wireless.@wifi-iface[$ii].key
				uci -q set wireless.@wifi-iface[$ii].sae='1'
				uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
				uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
			;;
		esac
	done

	__init_wifi_bh_ap $bh_ssid $bh_mgmt $bh_pswd
	if [ "$mesh_type" != "apsta" ]; then
		__init_wifi_bh_sta $bh_ssid $bh_mgmt $bh_pswd
	 fi

	# set bsd
	[ "$bsd" -eq 1 ] && {
		uci -q set wireless.$iface_2g.bsd='1'
		uci -q set wireless.$iface_5g.bsd='1'
		[ -n "$iface_5gh" ] && {
			uci -q set wireless.$iface_5gh.bsd='1'
		}

		# hostap mlo setup
		local mld_dev="$(uci -q get misc.mld.hostap)"
		local mlo_enable=$(uci -q get wireless.$mld_dev.enable)
		[ "$ax_enable" != "0" -a "$mlo_enable" = "1" ] && {
			uci -q batch <<-EOF >/dev/null
				set wireless.$mld_dev=wifi-mld
				set wireless.$mld_dev.mld_macaddr="$(mld_macaddr hostap)"
				set wireless.$mld_dev.mld_ssid="$main_ssid"
			EOF
		}
	}
	uci -q set wireless.$iface_5g.channel_block_list='52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165'

	uci commit wireless
}

## check if wifi has config backhaul
# 2 : uninit
# 1: init and wifi cfg change (ssid + key)
# 0: init and wifi cfg NO change
export WIFI_UNINIT=2
export WIFI_INIT_CHANGE=1   #init change need a restore
export WIFI_INIT_NOCHANGE=0
# only call before next cap/re retry, thus we can save wifi up time
mimesh_preinit()
{
	local role="$1"
	MIMESH_LOGI "*preinit"

	ret=$WIFI_INIT_NOCHANGE

	local netmode=$(uci -q get xiaoqiang.common.NETMODE)
	if [ $ret -eq $WIFI_INIT_NOCHANGE ]; then
		if [ "$role" = "cap" -o "$role" = "CAP" ]; then
			[ "$netmode" = "whc_cap" ] || {
				[ "$netmode" = "wifiapmode" -o "$netmode" = "lanapmode" ] && {
					[ "`uci -q get xiaoqiang.common.CAP_MODE`" = "ap" ] || {
						ret=$WIFI_INIT_CHANGE
					}
				} || {
					ret=$WIFI_INIT_CHANGE
				}
			}
		fi
	fi

	MIMESH_LOGI "*preinit done, ret=$ret"
	return $ret
}

__init_cap()
{
	MIMESH_LOGI " __init_cap: continue..."

	__set_netmode 1 cap

	__init_wifi_cap

	if [ "$restart_network" != "0" ]; then
		/etc/init.d/network reconfig_switch
		ubus call network reload
		/sbin/wifi update
	fi

	return 0
}

init_re_network_mesh_v4()
{
	MIMESH_LOGD " init_re_network_mesh_v4: continue..."

	__set_netmode 1 re
	__init_network_re
	/etc/init.d/network reconfig_switch
	ubus call network reload
	(/etc/init.d/firewall stop;/etc/init.d/firewall disable) &
}

__init_re_mesh_v4()
{
	local lan_ports
	lan_ports=$(port_map port class lan)

	MIMESH_LOGD " __init_re_mesh_v4: continue..."

	__init_wifi_re
	/sbin/wifi update &

	whc_re_open

	network_accel_hook "whc_re" "open"

	/etc/init.d/ipv6 ip6_fw close

	/etc/init.d/dnsmasq restart
	/etc/init.d/timezone restart
	/etc/init.d/messagingagent.sh restart
	/etc/init.d/miio_client reload
	/etc/init.d/xq_info_sync_mqtt restart -b &
	/usr/sbin/port_service restart

	phyhelper restart "$lan_ports"

	return 0
}

__init_re()
{
	local lan_ports
	lan_ports=$(port_map port class lan)

	MIMESH_LOGD " __init_re: continue..."

	__init_wifi_re
	__set_netmode 1 re
	__init_network_re
	/etc/init.d/network reconfig_switch

	whc_re_open

	network_accel_hook "whc_re" "open"

	/etc/init.d/ipv6 ip6_fw close

	/usr/sbin/port_service restart
	/sbin/wifi update

	/etc/init.d/dnsmasq restart
	/etc/init.d/timezone restart
	/etc/init.d/messagingagent.sh restart
	/etc/init.d/miio_client reload
	/etc/init.d/xq_info_sync_mqtt restart -b &

	phyhelper restart "$lan_ports"

	return 0
}

# check if ssid & encryption & key changed
# 1: wifi cfg changed
# 0: wifi cfg NO change
__check_wifi_cfg_no_changed()
{
	local key word word_cur

	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_2g\'" | awk -F"." '{print $2}')
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')

	local ssid_5g_cur="`uci -q get wireless.$iface_5g.ssid`"
	local mgmt_5g_cur="`uci -q get wireless.$iface_5g.encryption`"
	local pswd_5g_cur="`uci -q get wireless.$iface_5g.key`"
	local ssid_2g_cur="`uci -q get wireless.$iface_2g.ssid`"
	local mgmt_2g_cur="`uci -q get wireless.$iface_2g.encryption`"
	local pswd_2g_cur="`uci -q get wireless.$iface_2g.key`"
	local key_lists="ssid_5g mgmt_5g pswd_5g ssid_2g mgmt_2g pswd_2g"
	for key in $key_lists; do
		if [ "$bsd" -eq 0 ]; then
			word="`eval echo '$'"$key"`"
		else
			word="`eval echo '$'"whc_${key:0:4}"`"
		fi
		word_cur="`eval echo '$'"${key}_cur"`"
		[ "$word" != "$word_cur" ] && {
			MIMESH_LOGI "      wifi init with cfg changed, [$word_cur]->[$word]"
			MIMESH_LOGI "      [$ssid_5g_cur][$mgmt_5g_cur][$pswd_5g_cur][$ssid_2g_cur][$mgmt_2g_cur][$pswd_2g_cur]->"
			[ "$bsd" -eq 0 ] && {
				MIMESH_LOGI "      [$ssid_5g][$mgmt_5g][$pswd_5g][$ssid_2g][$mgmt_2g][$pswd_2g]"
			} || {
				MIMESH_LOGI "      [$whc_ssid][$whc_mgmt][$whc_pswd]"
			}
			return 1
		}
	done

	return 0
}

mimesh_init_done()
{
	local role="$1"

	local mesh_version=$(uci -q get xiaoqiang.common.MESH_VERSION)
	[ -z "$mesh_version" ] && {
		uci -q set xiaoqiang.common.MESH_VERSION=$(mesh_cmd max_mesh_version)
		uci commit xiaoqiang
	}

	MIMESH_LOGI " config init done. postpone handle mi services."
	uci -q set xiaoqiang.common.INITTED=YES
	uci commit xiaoqiang

	# turn off web init redirect page
	/usr/sbin/sysapi webinitrdr set off &

	/usr/sbin/set_wps_state 2 &

	#xqled mesh_finish

	if [ "$role" = "re" ]; then
		(/etc/init.d/firewall stop;/etc/init.d/firewall disable) &
		/etc/init.d/meshd stop
		recover_mesh_power

		xqled mesh_finish
		MIMESH_LOGI "re change light status."

		local mesh_band=$(uci -q get misc.mesh.support_band)
		[ -z "$mesh_band" ] && mesh_band=$(uci -q get misc.backhauls.backhaul)
		[ -z "$mesh_band" ] && mesh_band="5g"
		for band in $mesh_band; do
			local bh_ifname=$(uci -q get misc.backhauls.backhaul_${band}_sta_iface)
			[ -z "$bh_ifname" ] && continue
			echo 0 > /sys/devices/virtual/net/$bh_ifname/brport/isolate_mode 2>&1
		done
	fi

	if [ "$role" = "cap" ]; then
		# for CAP, led blue on after init
		led_check

		# not restart firewall before web init finished
		local configured=$(uci -q get xiaoqiang.common.CONFIGURED)
		[ "$configured" = "YES" ] && /etc/init.d/firewall restart &
		[ "$restart_miwifi_discovery" = "1" ] && /etc/init.d/miwifi-discovery restart &

		MIMESH_LOGI "Device was initted! clear br-port isolate_mode!"
		echo 0 > /sys/devices/virtual/net/wl0/brport/isolate_mode 2>&1
		echo 0 > /sys/devices/virtual/net/wl1/brport/isolate_mode 2>&1
		echo 0 > /sys/devices/virtual/net/wl2/brport/isolate_mode 2>&1
	fi

	# /etc/init.d/wan_check restart
	ubus call wan_check reset &

	# trafficd move into dhcp_apclient.sh callback
	/etc/init.d/mosquitto restart &

	/etc/init.d/xq_info_sync_mqtt restart &
	/etc/init.d/dnsmasq restart &
	/etc/init.d/xqbc restart &
	/etc/init.d/tbusd restart &
	/etc/init.d/trafficd restart &
	/etc/init.d/xiaoqiang_sync restart &
	/etc/init.d/miwifi-roam restart &

	# moved to __init_re on RE
	if [ "$role" = "cap" ]; then
		/etc/init.d/messagingagent.sh restart
		/etc/init.d/miio_client reload
		/etc/init.d/topomon restart &
	fi

	# reload_config
	ubus call service event "{ \"type\": \"config.change\", \"data\": { \"package\": \"xiaoqiang\" }}"
	return 0
}

mimesh_init()
{
	#gpio_led l green 600 600 &

	### get whc keys
	#json_load "$params"
	export bsd=1
	export method="$(json_get_value "$1" method)"
	export params="$(json_get_value "$1" params)"
	
	local eth_init=$2
	[ -z "$2" ] && eth_init=0
	export eth_init="$eth_init"

	[ -z "$ax_enable" ] && {
		local dev_5g=$(uci -q get misc.wireless.if_5G)
		export ax_enable=$(uci -q get wireless.$dev_5g.ax)
	}

	local para_bsd="`json_get_value \"$params\" \"bsd\"`"
	[ "$para_bsd" = "0" ] && bsd=0
	MIMESH_LOGI " keys:<bsd:$bsd>"
	[ "$bsd" -eq 0 ] && key_list="whc_role ssid_2g mgmt_2g pswd_2g ssid_5g mgmt_5g pswd_5g" || key_list="whc_role whc_ssid whc_pswd whc_mgmt"

	key_list="$key_list bh_ssid bh_mgmt bh_pswd bh_macnum_5g bh_maclist_5g"

	for key in $key_list; do
		#echo $key
		eval "export $key=\"\""
		eval "$key=\"`json_get_value \"$params\" \"$key\"`\""

		[ -z "$key" ] && {
			MIMESH_LOGE " error whc_init, no $key exist"
			message="\" error whc_init, no $key exist\""
			return $ERR_PARAM_NON
		}
	done

	if [ "$bsd" -eq 0 ]; then
		[ -z "$ssid_2g" ] && ssid_2g="!@Mi-son" || ssid_2g="`printf \"%s\" \"$ssid_2g\" | base64 -d`"
		[ -z "$mgmt_2g" ] && mgmt_2g="mixed-psk"
		[ -z "$pswd_2g" ] && mgmt_2g="none" || pswd_2g="`printf \"%s\" \"$pswd_2g\" | base64 -d`"
		[ -z "$ssid_5g" ] && ssid_5g="!@Mi-son_5G" || ssid_5g="`printf \"%s\" \"$ssid_5g\" | base64 -d`"
		[ -z "$mgmt_5g" ] && mgmt_5g="mixed-psk"
		[ -z "$pswd_5g" ] && mgmt_5g="none" || pswd_5g="`printf \"%s\" \"$pswd_5g\" | base64 -d`"

		[ -z "$bh_ssid" ] && bh_ssid_5g="MiMesh_A1B2"
		[ -z "$bh_mgmt" ] && bh_mgmt_5g="psk2+ccmp"
		[ -z "$bh_pswd" ] && bh_mgmt_5g="none"
		[ -z "$bh_macnum_2g" -o "$bh_macnum_2g" -eq 0 ] && bh_maclist_2g=""
		[ -z "$bh_macnum_5g" -o "$bh_macnum_5g" -eq 0 ] && bh_maclist_5g=""
		MIMESH_LOGI " keys:<$whc_role>,<$bsd>,<$ssid_2g>,<$pswd_2g>,<$mgmt_2g>,<$ssid_5g>,<$pswd_5g>,<$mgmt_5g>,<$bh_ssid>,<$bh_pswd>,<$bh_mgmt>"
		MIMESH_LOGI " keys:<$bh_macnum_2g>,<$bh_maclist_2g>,<$bh_macnum_5g>,<$bh_maclist_5g>"

	else
		[ -z "$whc_ssid" ] && whc_ssid="!@Mi-son" || whc_ssid="`printf \"%s\" \"$whc_ssid\" | base64 -d`"
		[ -z "$whc_mgmt" ] && whc_mgmt="mixed-psk"
		[ -z "$whc_pswd" ] && whc_mgmt="none" || whc_pswd="`printf \"%s\" \"$whc_pswd\" | base64 -d`"

		[ -z "$bh_ssid" ] && bh_ssid_5g="MiMesh_A1B2"
		[ -z "$bh_mgmt" ] && bh_mgmt_5g="psk2"
		[ -z "$bh_pswd" ] && bh_mgmt_5g="none"
		[ -z "$bh_macnum_2g" -o "$bh_macnum_2g" -eq 0 ] && bh_maclist_2g=""
		[ -z "$bh_macnum_5g" -o "$bh_macnum_5g" -eq 0 ] && bh_maclist_5g=""
		MIMESH_LOGI " keys:<$whc_role>,<$bsd>,<$whc_ssid>,<$whc_pswd>,<$whc_mgmt>,<$bh_ssid>,<$bh_pswd>,<$bh_mgmt>"
		MIMESH_LOGI " keys:<$bh_macnum_2g>,<$bh_maclist_2g>,<$bh_macnum_5g>,<$bh_maclist_5g>"

	fi

	case "$whc_role" in
		cap|CAP)
			# check if wireless is not default, then recreate it for a safe multi calling
			mimesh_preinit "$whc_role"
			ret=$?
			[ $ret -eq $WIFI_INIT_NOCHANGE ] || {
				[ "$support_mesh_ver4" == "1" ] && export restart_xq_info_sync_mqtt=1
				__init_cap
				ret=$?
			}

			;;

		re|RE)
			[ "$mesh_type" = "apsta" ] && __init_re_mesh_v4 || __init_re
			ret=$?
			;;
		*)
			MIMESH_LOGE " invalid role $whc_role"
			message="\" error whc_init, invalid role $whc_role\""
			ret=$ERR_PARAM_INV
			;;
	esac

	[ "$ret" -ne 0 ] && {
		MIMESH_LOGE "    init $whc_role error!"
		#gpio_led l yellow 1000 1000 &
	}

	MIMESH_LOGI " --- "
	return 0
}
