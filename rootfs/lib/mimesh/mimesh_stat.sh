#!/bin/sh

# mimesh_stat: check stat

. /lib/mimesh/mimesh_public.sh

ERR_ROLE=10

__ts_get()
{
	local ts="`date +%Y%m%d-%H%M%S`:`cat /proc/uptime | awk '{print $1}'`"
	echo -n "timestamp:$ts"
}

# check device is CAP or RE
mimesh_is_cap()
{
	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	[ "whc_cap" = "$mode" ] && return 0 || {
		[ "lanapmode" = "$mode" ] && {
			[ "`uci -q get xiaoqiang.common.CAP_MODE`" = "ap" ] && return 0
		}
	}

	return $ERR_ROLE
}

mimesh_is_re()
{
	[ "`uci -q get xiaoqiang.common.NETMODE`" = "whc_re" ] && return 0 || return $ERR_ROLE

	return 0
}

_is_controller()
{
	[ "`uci -q get xiaoqiang.common.EASYMESH_ROLE`" = "controller" ] && return 0 || return $ERR_ROLE
	return 0
}

_is_agent()
{
	[ "`uci -q get xiaoqiang.common.EASYMESH_ROLE`" = "agent" ] && return 0 || return $ERR_ROLE
	return 0
}

# return CAP RE 
mimesh_get_stat()
{
	mimesh_is_cap && {
		echo -n "CAP"
		return 0
	}

	mimesh_is_re && {
		echo -n "RE"
		return 0
	}

	_is_controller && {
		echo -n "CONTROLLER"
		return 0
	}

	_is_agent && {
		echo -n "AGENT"
		return 0
	}

	echo -n "router"
	return 0;
}

mimesh_re_counts()
{
	local re_counts=0
	local role=$(mimesh_get_stat)
	local initted=$(uci -q get xiaoqiang.common.INITTED)

	if [ "$initted" != "YES" -o "$role" != "CAP" ]; then
		echo -n "0"
		return 0
	fi

	local hw_dump=/tmp/.hw_dump

	ubus call trafficd hw 2>>/dev/null > $hw_dump
	local re_list=$(cat $hw_dump | sed -n -r 's/.*(([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2})": \{/\1/p')
	local hw_data=$(cat $hw_dump)
	for re in $re_list; do
		local is_ap=$(echo $hw_data | jsonfilter -e "$['$re'].is_ap")
		local is_assoc=$(echo $hw_data | jsonfilter -e "$['$re'].assoc")
		local ageing_timer=$(echo $hw_data | jsonfilter -e "$['$re'].ageing_timer")

		if [ -n "$is_ap" -a "$is_ap" = "8" ] && [ "$is_assoc" = "1" ] && \
				[ -n "$ageing_timer" -a "$ageing_timer" -le 60 ]; then
			re_counts=$((re_counts + 1))
		fi
	done
	rm $hw_dump -rf

	echo -n "$re_counts"
	return 0
}

mimesh_get_gw_ip()
{
	local __NLAL_netw="$1"
	local __NLAL_gw_ip="`route -n  | grep "^0.0.0.0" | grep br-$__NLAL_netw | awk '{print $2}' | xargs`"
	[ -z "$__NLAL_gw_ip" ] && __NLAL_gw_ip="`uci -q get network.lan.gateway`"
	echo -n $__NLAL_gw_ip
	[ -n "$__NLAL_gw_ip" ]
}

# check RE ping CAP ret
# return 0: linkup
# return else: no link
mimesh_gateway_ping()
{
	local gw_ip=$(mimesh_get_gw_ip lan)

	if [ -n "$gw_ip" ]; then
		ping $gw_ip -c 1 -w 2 > /dev/null 2>&1
		[ $? -eq 0 ] && return 0
	else
		MIMESH_LOGI "  NO find valid gateway!"
	fi

	return 1
}

mimesh_re_check_slo_backup() {
	local bh_mlo_support=$(mesh_cmd bh_mlo_support)
	[ "$bh_mlo_support" != "1" ] && return 0

	local slo_backup_band=$(uci -q get misc.mld.slo_backup)
	[ -z "$slo_backup_band" ] && return 0

	local sta_mlo=$(uci -q get wireless.bh_sta_mlo.mlo)
	[ -z "$sta_mlo" ] && return 0

	local slo_backup_iface=$(uci -q get misc.backhauls.backhaul_${slo_backup_band}_sta_iface)
	if [ -e "/var/run/wpa_supplicantglobal" ]; then
		global_path="/var/run/wpa_supplicantglobal"
	elif [ -e "/var/run/wpa_supplicant/global" ]; then
		global_path="/var/run/wpa_supplicant/global"
	fi

	local failed_times=$(wpa_cli -g $global_path ifname=$slo_backup_iface status | grep "mlo_partner_failed_times=" | awk -F'=' '{print $2}')
	local max_failed_times=$(uci -q get misc.mld.mlo_failed_max_times)

	[ -z "$max_failed_times" ] && max_failed_times=6

	echo "$failed_times" > /tmp/mlo_failed_times

	if [ -n "$failed_times" -a $failed_times -ge $max_failed_times ]; then
		local band_list=$(uci -q get misc.mld.sta_mlo)
		[ -z "$band_list" ] && band_list="$bh_band"
		for band in $band_list; do
			local sec_name="bh_sta_$band"
			uci -q set wireless.$sec_name.mld=""
			if [ "$band" != "$slo_backup_band" ]; then
				uci -q set wireless.$sec_name.disabled="1"
			fi
		done
		uci -q set wireless.bh_sta_mlo=""
		local mld_dev="$(uci -q get misc.mld.bh_sta)"
		local main_iface="$(uci -q get wireless.$mld_dev.main_iface)"
		if [ -n "$main_iface" ]; then
			uci -q set wireless.$mld_dev.disabled="1"
			uci -q set wireless.$mld_dev.main_iface=""
			uci -q set wireless.$mld_dev.iface=""
		fi
		uci commit wireless
		wifi update

		[ -d "/var/run/topomon" ] || mkdir -p "/var/run/topomon"
		/usr/sbin/topomon_action.sh update_status force_slo_backup 1

		return 1
	fi

	return 0
}

# check RE assoc CAP ret
# return 0: associated
# return else: no assoc
mimesh_re_assoc_check()
{
	mimesh_gateway_ping

	return $?
}

mimesh_cap_bh_check()
{
	local bh_band=$(mesh_cmd backhaul get band)
	local iface_5g_bh=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	[ -z "$iface_5g_bh" ] && iface_5g_bh="wl5"
	cfg80211tool $iface_5g_bh get_backhaul | grep -wq "get_backhaul:1"

	return $?
}
