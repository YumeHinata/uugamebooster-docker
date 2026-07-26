#!/bin/sh
# Copyright (C) 2020 Xiaomi

. /lib/mimesh/mimesh_public.sh
. /lib/mimesh/mimesh_stat.sh
. /lib/mimesh/mimesh_init.sh

log(){
	logger -t "meshd connect: " -p9 "$1"
}
check_re_initted(){
	initted=`uci -q get xiaoqiang.common.INITTED`
	[ "$initted" == "YES" ] && { log "RE already initted. exit 0." ; exit 0; }
}
run_with_lock(){
	{
		log "$$, ====== TRY locking......"
		flock -x -w 60 1003
		[ $? -eq "1" ] && { log "$$, ===== GET lock failed. exit 1" ; exit 1 ; }
		log "$$, ====== GET lock to RUN."
		$@ 1003>&-
		log "$$, ====== END lock to RUN."
	} 1003<>/var/log/mesh_connect_lock.lock
}
usage() {
	echo "$0 re_start xx:xx:xx:xx:xx:xx"
	echo "$0 help"
	exit 1
}

eth_down() {
	local ifnames=$(uci -q get network.lan.ifname)
	local wan_ifname=$(uci -q get network.wan.ifname)
	for if_name in $ifnames
	do
		ifconfig $if_name down
	done
	ifconfig $wan_ifname down
}

eth_up() {
	local ifnames=$(uci -q get network.lan.ifname)
	local wan_ifname=$(uci -q get network.wan.ifname)
	for if_name in $ifnames
	do
		ifconfig $if_name up
	done
	ifconfig $wan_ifname up
}

bh_isolate_check() {
	local ifname="$1"
	local wait_time=10
	local bh_isolate=0
	if [ -n "$ifname" ]; then
		while [ "$wait_time" != "0" ]; do
			if [ -f /sys/devices/virtual/net/$ifname/brport/isolate_mode ]; then
				bh_isolate="$(cat /sys/devices/virtual/net/$ifname/brport/isolate_mode)"
				[ "$bh_isolate" = "1" ] && break
				echo 1 > /sys/devices/virtual/net/$ifname/brport/isolate_mode 2>>/dev/null
			fi
			wait_time=$((wait_time - 1))
			sleep 1
		done
	fi

}

set_network_id() {
	local bh_ssid=$1
	local bh_ifname=$2
	local pre_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local new_id=$(echo "$bh_ssid" | md5sum | cut -c 1-8)
	if [ -z "$pre_id" -o "$pre_id" != "$new_id" ]; then
		uci set xiaoqiang.common.NETWORK_ID="$new_id"
		uci commit xiaoqiang
	fi

	if [ -n "$bh_ifname" -a -n "$new_id" ]; then
		cfg80211tool "$bh_ifname" mesh_id "0x${new_id}" 2>>/dev/null
	fi
}

# statpoint to record if meshed
set_meshed_flag() {
	uci -q set xiaoqiang.common.MESHED="YES"
	uci commit xiaoqiang
}

cap_close_wps() {
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname=$(uci -q get misc.wireless.ifname_${bh_band_upcase})
	local device=$(uci -q get misc.wireless.if_${bh_band_upcase})
	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid wps_cancel
	iwpriv $ifname miwifi_mesh 3
	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid update_beacon
}

cap_disable_wps_trigger() {
	local ifname=$2
	local device=$1

	#uci set wireless.@wifi-iface[1].miwifi_mesh=3
	#uci commit wireless

	iwpriv $ifname miwifi_mesh 3
	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid update_beacon
}

wpa_supplicant_check() {
	local wpa_pid=$(ps | grep wpa_supplicant 2>>/dev/null | grep -v grep | awk '{print $1}')

	# wpa_supplicant not exist, setup
	if [ -z "$wpa_pid" ]; then
		if [ -f "/etc/init.d/qca-wpa-supplicant" ]; then
			/etc/init.d/qca-wpa-supplicant boot
		else
			wpa_supplicant -g /var/run/wpa_supplicantglobal -B -P /var/run/wpa_supplicant-global.pid
		fi
	fi
}

wpa_supplicant_if_add() {
	local ifname=$1
	local bridge=$2
	local driver="nl80211"

	[ -f "/var/run/wpa_supplicant-$ifname.lock" ] && rm /var/run/wpa_supplicant-$ifname.lock
	wpa_cli -g /var/run/wpa_supplicantglobal interface_add  $ifname /var/run/wpa_supplicant-$ifname.conf $driver /var/run/wpa_supplicant-$ifname "" $bridge
	touch /var/run/wpa_supplicant-$ifname.lock
}

wpa_supplicant_if_remove() {
	local ifname=$1

	[ -f "/var/run/wpa_supplicant-${ifname}.lock" ] && { \
		wpa_cli -g /var/run/wpa_supplicantglobal  interface_remove  ${ifname}
		rm /var/run/wpa_supplicant-${ifname}.lock
	}
}

re_clean_vap() {
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname=$(uci -q get misc.wireless.apclient_${bh_band_upcase})

	wpa_supplicant_if_remove $ifname
	wlanconfig $ifname destroy -cfg80211

	local lanip=$(uci -q get network.lan.ipaddr)
	if [ "$lanip" != "" ]; then
		ifconfig br-lan $lanip
	else
		ifconfig br-lan 192.168.31.1
	fi

	eth_up
	wifi
}

check_re_init_status_wifi() {
	local eth_init="$1"
	[ "$eth_init" = "1" ] && return

	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local device=$(uci -q get misc.wireless.if_${bh_band_upcase})

	radartool -n -i $device enable
	radartool -n -i $device ignorecac 0
	eth_up
}

check_re_init_status_v2() {
	for i in $(seq 1 60); do
		mimesh_re_assoc_check > /dev/null 2>&1
		[ $? = 0 ] && break
		sleep 2
	done

	check_re_init_status_wifi "$1"

	mimesh_init_done "re"
	/etc/init.d/meshd stop
	/etc/init.d/cab_meshd stop
	/etc/init.d/topomon restart &

	# statpoint to record if meshed
	set_meshed_flag
}

do_re_init_mesh_v4() {
	local local_nb_band=$(mesh_cmd backhaul get band)
	ifname=$(uci -q get misc.backhauls.backhaul_${local_nb_band}_sta_iface)

	export support_mesh_ver4=1
	export mesh_type="apsta"
	brctl delif br-lan "$ifname"
	init_re_network_mesh_v4 &

	sleep 1
	bh_isolate_check "$ifname"
}

do_re_init() {
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname=$(uci -q get misc.wireless.apclient_${bh_band_upcase})
	local device=$(uci -q get misc.wireless.if_${bh_band_upcase})
	#local ifname_2g=$(uci -q get misc.wireless.ifname_2G)

	# wps or apsta
	local mesh_type=${11}
	case "$mesh_type" in
		apsta) # mesh4.0
			do_re_init_mesh_v4
		;;
		*) # default to wps
			export mesh_type="wps"
			wpa_supplicant_if_remove $ifname
			wlanconfig $ifname destroy -cfg80211
		;;
	esac

	wpa_supplicant_check

	#local ssid_2g=$(printf "%s" $1 | base64 -d)
	local ssid_2g="$1"
	local pswd_2g=
	local mgmt_2g=$3
	#[ "$mgmt_2g" = "none" ] || pswd_2g=$(printf "%s" $2 | base64 -d)
	[ "$mgmt_2g" = "none" ] || pswd_2g="$2"
	#local ssid_5g=$(printf "%s" $4 | base64 -d)
	local ssid_5g="$4"
	local pswd_5g=
	local mgmt_5g=$6
	#[ "$mgmt_5g" = "none" ] || pswd_5g=$(printf "%s" $5 | base64 -d)
	[ "$mgmt_5g" = "none" ] || pswd_5g="$5"
	local bh_ssid=$(printf "%s" "$7" | base64 -d)
	local bh_pswd=$(printf "%s" "$8" | base64 -d)
	local bh_mgmt=$9

	#backup wifi config
	/sbin/wifi backup_cfg

	#local ssid=$(grep "ssid=\"" /var/run/wpa_supplicant-${ifname}.conf | awk -F\" '{print $2}')
	#local key=$(grep "psk=\"" /var/run/wpa_supplicant-${ifname}.conf | awk -F\" '{print $2}')

	set_network_id "$bh_ssid"

	touch /tmp/bh_maclist_5g
	local bh_maclist_5g=$(cat /tmp/bh_maclist_5g | sed 's/ /,/g')
	local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')

	export bsd=0
	do_re_init_json

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"RE\",\"bsd\":\"0\",\"ssid_2g\":\"${ssid_2g}\",\"pswd_2g\":\"${pswd_2g}\",\"mgmt_2g\":\"${mgmt_2g}\",\"ssid_5g\":\"${ssid_5g}\",\"pswd_5g\":\"${pswd_5g}\",\"mgmt_5g\":\"${mgmt_5g}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"${bh_mgmt}\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

	mimesh_init "$buff" "${10}"
	sleep 2
	check_re_init_status_v2 "${10}"
	exit 0
}

do_re_init_bsd() {
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname=$(uci -q get misc.wireless.apclient_${bh_band_upcase})
	local device=$(uci -q get misc.wireless.if_${bh_band_upcase})
	#local ifname_2g=$(uci -q get misc.wireless.ifname_2G)

	# wps or apsta
	local mesh_type=$8
	case "$mesh_type" in
		apsta) # mesh4.0
			do_re_init_mesh_v4
		;;
		*) # default to wps
			export mesh_type="wps"
			wpa_supplicant_if_remove $ifname
			wlanconfig $ifname destroy -cfg80211
		;;
	esac

	wpa_supplicant_check

	#local whc_ssid=$(printf "%s" $1 | base64 -d)
	local whc_ssid="$1"
	local whc_pswd=
	local whc_mgmt=$3
	#[ "$whc_mgmt" = "none" ] || whc_pswd=$(printf "%s" $2 | base64 -d)
	[ "$whc_mgmt" = "none" ] || whc_pswd="$2"
	local bh_ssid=$(printf "%s" "$4" | base64 -d)
	local bh_pswd=$(printf "%s" "$5" | base64 -d)
	local bh_mgmt=$6

	#backup wifi config
	/sbin/wifi backup_cfg

	#local ssid=$(grep "ssid=\"" /var/run/wpa_supplicant-${ifname}.conf | awk -F\" '{print $2}')
	#local key=$(grep "psk=\"" /var/run/wpa_supplicant-${ifname}.conf | awk -F\" '{print $2}')

	set_network_id "$bh_ssid"

	touch /tmp/bh_maclist_5g
	local bh_maclist_5g=$(cat /tmp/bh_maclist_5g | sed 's/ /,/g')
	local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')

	export bsd=1
	do_re_init_json

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"RE\",\"whc_ssid\":\"${whc_ssid}\",\"whc_pswd\":\"${whc_pswd}\",\"whc_mgmt\":\"${whc_mgmt}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"${bh_mgmt}\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

	mimesh_init "$buff" "$7"
	sleep 2
	check_re_init_status_v2 "$7"
	exit 0
}

do_re_init_json() {
	local jsonbuf=$(cat /tmp/extra_wifi_param 2>/dev/null)
	[ -z "$jsonbuf" ] && return

	#set max mesh version we can support
	local version_list=$(uci -q get misc.mesh.version)
	if [ -z "$version_list" ]; then
		log "version list is empty"
		return
	fi

	local max_version=1
	for version in $version_list; do
		if [ $version -gt $max_version ]; then
			max_version=$version
		fi
	done

	uci set xiaoqiang.common.MESH_VERSION="$max_version"
	uci commit

	local device_2g=$(uci -q get misc.wireless.if_2G)
	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local device_5g=$(uci -q get misc.wireless.if_5G)
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)

	local hidden_2g=$(json_get_value "$jsonbuf" "hidden_2g")
	local hidden_5g=$(json_get_value "$jsonbuf" "hidden_5g")
	local disabled_2g=$(json_get_value "$jsonbuf" "disabled_2g")
	local disabled_5g=$(json_get_value "$jsonbuf" "disabled_5g")
	local ax_2g=$(json_get_value "$jsonbuf" "ax_2g")
	local ax_5g=$(json_get_value "$jsonbuf" "ax_5g")
	local txpwr_2g=$(json_get_value "$jsonbuf" "txpwr_2g")
	local txpwr_5g=$(json_get_value "$jsonbuf" "txpwr_5g")
	local bw_2g=$(json_get_value "$jsonbuf" "bw_2g")
	local bw_5g=$(json_get_value "$jsonbuf" "bw_5g")
	local txbf_2g=$(json_get_value "$jsonbuf" "txbf_2g")
	local txbf_5g=$(json_get_value "$jsonbuf" "txbf_5g")
	local ch_2g=$(json_get_value "$jsonbuf" "ch_2g")
	local ch_5g=$(json_get_value "$jsonbuf" "ch_5g")
	local web_passwd=$(json_get_value "$jsonbuf" "web_passwd")
	local web_passwd256=$(json_get_value "$jsonbuf" "web_passwd256")
	local support160=$(json_get_value "$jsonbuf" "support160")
	local twt=$(json_get_value "$jsonbuf" "twt")

	local is_tri_band=$(mesh_cmd is_tri_band)
	if [ $is_tri_band -eq 1 ]; then
		# 有线组网时，需要此字段来识别回传频段
		local bh_band=$(json_get_value "$jsonbuf" "bh_band")
		local nbh_exist=$(echo "$jsonbuf" | grep "5g_nbh" | wc -l)
		local dev_type=$(json_get_value "$jsonbuf" "dev_type")

		local bw_5g_auto=$(json_get_value "$jsonbuf" "bw_5g_auto")
		[ "$bw_5g_auto" = "1" ] && bw_5g=0

		# cap is dual device, 5g1 & 5gh ssid&pswd from objs suffix is '_5g'
		if [ -z "$dev_type" -a $nbh_exist -lt 1 ] \
			|| [ "$dev_type" = "dual"  -o "$dev_type" = "dual-suite" ]; then
			if [ "$bsd" = "0" ]; then
				[ -n "$ssid_5g" ] && local ssid_5gh=$ssid_5g
				[ -n "$pswd_5g" ] && local pswd_5gh=$pswd_5g
				[ -n "$mgmt_5g" ] && local mgmt_5gh=$mgmt_5g
			else
				[ -n "$whc_ssid" ] && local ssid_5gh=$whc_ssid
				[ -n "$whc_pswd" ] && local pswd_5gh=$whc_pswd
				[ -n "$whc_mgmt" ] && local mgmt_5gh=$whc_mgmt
			fi
			[ -z "$ssid_5gh" ] && ssid_5gh="!@Mi-son" || ssid_5gh="$(printf \"%s\" \"$ssid_5gh\" | base64 -d)"
			[ -z "$mgmt_5gh" ] && mgmt_5gh="mixed-psk"
			[ -z "$pswd_5gh" ] && pswd_5gh="none" || pswd_5gh="$(printf \"%s\" \"$pswd_5gh\" | base64 -d)"
			local hidden_5gh=$hidden_5g
			local disabled_5gh=$disabled_5g
			local sae_pwd_5gh=$pswd_5gh

			local ax_5gh=$ax_5g
			local txpwr_5gh=$txpwr_5g
			local bw_5gh=$bw_5g
			local txbf_5gh=$txbf_5g

			if [ -z "$bh_band" ]; then
				local ch_5g_num=$ch_5g
				[ "$ch_5g" = "auto" ] && ch_5g_num=0

				if [ "$ch_5g_num" -gt 64 ]; then
					bh_band="5gh"
				elif [ "$ch_5g_num" -ge 36 -a "$ch_5g_num" -le 64 ]; then
					bh_band="5g"
				else
					# mesh initted by wired, bh_band as default
					# tri: 5g, tri-suite: 5gh
					bh_band=$(mesh_cmd backhaul get band)
				fi
			fi

			if [ "$bh_band" = "5gh" ]; then
				ch_5gh="$ch_5g"
				ch_5g=36
				[ "$bw_5g" = "160" ] && bw_5gh=0
			else # bh_band == 5g
				ch_5gh=149
			fi

			# tri-band re mesh with dual-band cap, bsd fixed to open
			local bsd_5g_nbh=1
		else
			# cap is tri-band device
			local cfg_suffix="5g_nbh"
			local ssid_5gh=$(json_get_value "$jsonbuf" "ssid_$cfg_suffix" | base64 -d)
			local mgmt_5gh=$(json_get_value "$jsonbuf" "mgmt_$cfg_suffix")
			local pswd_5gh=$(json_get_value "$jsonbuf" "pswd_$cfg_suffix" | base64 -d)
			local hidden_5gh=$(json_get_value "$jsonbuf" "hidden_$cfg_suffix")
			local disabled_5gh=$(json_get_value "$jsonbuf" "disabled_$cfg_suffix")
			local sae_5gh=$(json_get_value "$jsonbuf" "sae_$cfg_suffix")
			local sae_pwd_5gh=$(json_get_value "$jsonbuf" "sae_passwd_$cfg_suffix")
			local ieee80211w_5gh=$(json_get_value "$jsonbuf" "ieee80211w_$cfg_suffix")

			# cap is tri-suite
			if [ "$bh_band" = "5gh" ]; then
				local ax_5gh=$ax_5g
				local txpwr_5gh=$txpwr_5g
				local ch_5gh=$ch_5g
				local bw_5gh=$bw_5g
				local bsd_5gh=$bsd_5g
				local txbf_5gh=$txbf_5g
				ax_5g=$(json_get_value "$jsonbuf" "ax_$cfg_suffix")
				txpwr_5g=$(json_get_value "$jsonbuf" "txpwr_$cfg_suffix")
				ch_5g=$(json_get_value "$jsonbuf" "ch_$cfg_suffix")
				bw_5g=$(json_get_value "$jsonbuf" "bw_$cfg_suffix")
				bsd_5g=$(json_get_value "$jsonbuf" "bsd_$cfg_suffix")
				txbf_5g=$(json_get_value "$jsonbuf" "txbf_$cfg_suffix")
			else # cap is tri-router or ax9000
				local ax_5gh=$(json_get_value "$jsonbuf" "ax_$cfg_suffix")
				local txpwr_5gh=$(json_get_value "$jsonbuf" "txpwr_$cfg_suffix")
				local ch_5gh=$(json_get_value "$jsonbuf" "ch_$cfg_suffix")
				local bw_5gh=$(json_get_value "$jsonbuf" "bw_$cfg_suffix")
				local bsd_5gh=$(json_get_value "$jsonbuf" "bsd_$cfg_suffix")
				local txbf_5gh=$(json_get_value "$jsonbuf" "txbf_$cfg_suffix")
				[ -z "$bh_band" ] && bh_band="5g"
			fi
		fi
		mesh_cmd backhaul set band "$bh_band"

		local device_5gh=$(uci -q get misc.wireless.if_5GH)
		local ifname_5gh=$(uci -q get misc.wireless.ifname_5GH)
		local iface_5gh=$(uci show wireless | grep -w "ifname=\'$ifname_5gh\'" | awk -F"." '{print $2}')

		uci -q set wireless.$device_5gh.channel="$ch_5gh"
		uci -q set wireless.$device_5gh.ax="$ax_5gh"
		uci -q set wireless.$device_5gh.txpwr="$txpwr_5gh"
		uci -q set wireless.$device_5gh.txbf="$txbf_5gh"
		uci -q set wireless.$device_5gh.bw="$bw_5gh"
		uci -q set wireless.$device_5gh.CSwOpts='0x31'

		uci -q set wireless.$iface_5gh.ssid="$ssid_5gh"
		uci -q set wireless.$iface_5gh.encryption="$mgmt_5gh"
		uci -q set wireless.$iface_5gh.key="$pswd_5gh"
		case "$mgmt_5gh" in
			none)
				uci -q delete wireless.$iface_5gh.key
			;;
			mixed-psk|psk2)
				uci -q set wireless.$iface_5gh.key="$pswd_5gh"
			;;
			psk2+ccmp)
				uci -q set wireless.$iface_5gh.sae='1'
				uci -q set wireless.$iface_5gh.sae_password="$sae_pwd_5gh"
				uci -q set wireless.$iface_5gh.ieee80211w='1'
			;;
			ccmp)
				uci -q delete wireless.$iface_5gh.key
				uci -q set wireless.$iface_5gh.sae='1'
				uci -q set wireless.$iface_5gh.sae_password="$sae_pwd_5gh"
				uci -q set wireless.$iface_5gh.ieee80211w='2'
			;;
		esac
		[ -n "$ieee80211w_5gh" ] && uci -q set wireless.$iface_5gh.ieee80211w="$ieee80211w_5gh"
		uci -q set wireless.$iface_5gh.hidden="$hidden_5gh"
		uci -q set wireless.$iface_5gh.disabled="$disabled_5gh"
		uci -q set wireless.$iface_5gh.bsd="$bsd_5gh"
		uci -q set wireless.$iface_5gh.wnm='1'
		uci -q set wireless.$iface_5gh.rrm='1'
		uci -q set wireless.$iface_5gh.miwifi_mesh='0'
		uci -q set wireless.$iface_5gh.mesh_ver="$(mesh_cmd max_mesh_version)"
	fi

	[ "$ch_5g" != "auto" -a "$ch_5g" -gt 48 -a "$ch_5g" -le 140 ] && ch_5g="auto"
	[ "$ch_5g" != "auto" -a "$ch_5g" != "0" ] && uci set wireless.$device_5g.channel="$ch_5g"

	uci set wireless.$device_2g.channel="$ch_2g"

	uci set wireless.$device_5g.ax="$ax_5g"
	uci set wireless.$device_2g.ax="$ax_2g"

	uci set wireless.$device_5g.txpwr="$txpwr_5g"
	uci set wireless.$device_2g.txpwr="$txpwr_2g"

	uci set wireless.$device_5g.txbf="$txbf_5g"
	uci set wireless.$device_2g.txbf="$txbf_2g"

	uci set wireless.$device_2g.bw="$bw_2g"
	uci set wireless.$device_5g.bw="$bw_5g"

	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_2g\'" | awk -F"." '{print $2}')
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')

	uci set wireless.$iface_2g.hidden="$hidden_2g"
	uci set wireless.$iface_5g.hidden="$hidden_5g"

	[ -z "$disabled_2g" ] && disabled_2g=0
	uci set wireless.$iface_2g.disabled="$disabled_2g"
	uci set wireless.miot_2G.disabled="$disabled_2g"

	[ -z "$disabled_5g" ] && disabled_5g=0
	uci set wireless.$iface_5g.disabled="$disabled_5g"

	[ -z "$twt" ] && twt=0
	uci set wireless.$iface_2g.twt_responder="$twt"
	uci set wireless.$iface_5g.twt_responder="$twt"
	uci set wireless.$iface_5gh.twt_responder="$twt"

	enc_mode=$(/usr/sbin/check_encrypt_mode.lua 2>>/dev/null)
	if [ "$enc_mode" = "1" ] && [ -n "$web_passwd256" ]; then
		uci set account.common.admin="$web_passwd256"
		uci set account.legacy.admin="$web_passwd"
		uci commit account
	elif [ -n "$web_passwd" ]; then
		uci -q set account.legacy=
		uci set account.common.admin="$web_passwd"
		uci commit account
	fi

	local local_countrycode="$(nvram get CountryCode)"
	if [ "$local_countrycode" != "CN" ]; then
		local wifi_countrycode=$(json_get_value "$jsonbuf" "wifi_countrycode")
		if [ -n "$wifi_countrycode" ]; then
			uci set wireless.wifi0.country="$wifi_countrycode"
			uci set wireless.wifi1.country="$wifi_countrycode"
			uci set wireless.wifi2.country="$wifi_countrycode"
		fi
	fi

	if [ "$ax_2g" = "0" -o "$ax_5g" = "0" -o "$ax_5gh" = "0" ]; then
		export ax_enable=0
	else
		export ax_enable=1
	fi

	# basic_mlo
	local mlo_support=$(mesh_cmd mlo_support)
	if [ "$mlo_support" = "1" ]; then
		local hostap_mlo_enable=$(json_get_value "$jsonbuf" "mlo")
		if [ "$ax_enable" != "1" -o "$bsd" != "1" ]; then
			hostap_mlo_enable=0
		else
			hostap_mlo_enable=$(json_get_value "$jsonbuf" "mlo")
		fi

		if [ -n "$hostap_mlo_enable" ]; then
			__wifi_hostap_mlo_setup $hostap_mlo_enable
		fi
	fi
	# vap_mlo
	local mlo_vap_support=$(uci -q get misc.features.mlo_vap_support)
	if [ "$mlo_vap_support" = "1" ]; then
		local mlo_enable=
		local mlo_ssid=
		local mlo_hidden=
		local mlo_enc=
		local mlo_pwd=
		if [ "$ax_enable" != "1" ]; then
			mlo_enable="0"
		else
			mlo_enable=$(json_get_value "$jsonbuf" "mlo_enable")
		fi
		mlo_ssid=$(json_get_value "$jsonbuf" "mlo_ssid")
		mlo_hidden=$(json_get_value "$jsonbuf" "mlo_hidden")
		mlo_enc=$(json_get_value "$jsonbuf" "mlo_enc")
		mlo_pwd=$(json_get_value "$jsonbuf" "mlo_pwd")

		if [ -n "$mlo_vap_enable" ]; then
			__wifi_mlo_vap_setup "$mlo_enable" "$mlo_ssid" "$mlo_hidden" "$mlo_enc" "$mlo_pwd"
		fi
	fi

	#iot wifi iface
	local iot_dev_support=$(uci -q get misc.features.iot_dev)
	if [ "$iot_dev_support" = "1" ]; then
		for band in "2g" "5g"
		do
			local iot_ssid=$(json_get_value "$jsonbuf" "iot${band}_ssid"|base64 -d)
			local iot_disabled=$(json_get_value "$jsonbuf" "iot${band}_disabled")
			local iot_wifi5=$(json_get_value "$jsonbuf" "iot${band}_wifi5")
			local iot_encryption=$(json_get_value "$jsonbuf" "iot${band}_enc")
			local iot_pwd=""

			uci -q set wireless.iot_${band}.ssid="$iot_ssid"
			uci -q set wireless.iot_${band}.disabled="$iot_disabled"
			uci -q set wireless.iot_${band}.iotwifi5mode="$iot_wifi5"
			uci -q set wireless.iot_${band}.encryption="$iot_encryption"

			if [ "$iot_encryption" != "none" ]; then
				iot_pwd=$(json_get_value "$jsonbuf" "iot${band}_pwd"|base64 -d)
			fi
			case "$iot_encryption" in
				none)
					uci -q delete wireless.iot_${band}.sae
					uci -q delete wireless.iot_${band}.ieee80211w
				;;
				mixed-psk|psk2)
					uci -q set wireless.iot_${band}.key="$iot_pwd"
					uci -q delete wireless.iot_${band}.sae
					uci -q delete wireless.iot_${band}.ieee80211w
					uci -q delete wireless.iot_${band}.sae_password
				;;
				psk2+ccmp)
					uci -q set wireless.iot_${band}.sae='1'
					uci -q set wireless.iot_${band}.sae_password="$iot_pwd"
					uci -q set wireless.iot_${band}.key="$iot_pwd"
					uci -q set wireless.iot_${band}.ieee80211w='1'
				;;
				ccmp)
					uci -q delete wireless.iot_${band}.key
					uci -q set wireless.iot_${band}.sae='1'
					uci -q set wireless.iot_${band}.sae_password="$iot_pwd"
					uci -q set wireless.iot_${band}.ieee80211w='2'
				;;
			esac
		done
	fi

	uci commit wireless

	#cap_mode
	local cap_mode=$(json_get_value "$jsonbuf" "cap_mode")
	uci set xiaoqiang.common.CAP_MODE="$cap_mode"

	local cap_ip=$(json_get_value "$jsonbuf" "cap_ip")
	[ -n "$cap_ip" ] && uci -q set xiaoqiang.common.CAP_IP="$cap_ip"

	local cap_mesh_ver=$(json_get_value "$jsonbuf" "mesh_version")
	[ -n "$cap_mesh_ver" ] && uci -q set xiaoqiang.common.CAP_MESH_VER="$cap_mesh_ver"

	if [ "$cap_mode" = "ap" ]; then
		local vendorinfo=$(json_get_value "$jsonbuf" "vendorinfo")
		uci set xiaoqiang.common.vendorinfo="$vendorinfo"
	fi
	uci commit xiaoqiang

	# nfc
	local nfc_support=$(uci -q get misc.nfc.nfc_support)
	if [ "$nfc_support" = "1" ]; then
		local nfc_enable=$(json_get_value "$jsonbuf" "nfc_enable")
		if [ -n "$nfc_enable" ]; then
			if [ -z "$(uci -q show nfc)" ]; then
				touch /etc/config/nfc
				uci -q add nfc.nfc=nfc
			fi
			uci -q set nfc.nfc.nfc_enable="$nfc_enable"
			uci commit nfc
		fi
	fi

	local tz_index=$(json_get_value "$jsonbuf" "tz_index")
	local timezone=$(json_get_value "$jsonbuf" "timezone")
	local lang=$(json_get_value "$jsonbuf" "lang")
	local CountryCode=$(json_get_value "$jsonbuf" "CountryCode")

	if [ -n "$timezone" ]; then
		uci set system.@system[0].timezone=$timezone
		[ -n "$tz_index" ] && uci set system.@system[0].timezoneindex=$tz_index
		uci commit system
		/etc/init.d/timezone restart
	fi

	if [ "$local_countrycode" != "CN" ] \
			&& [ -n "$CountryCode" -a "$CountryCode" != "CN" ]; then

		uci set luci.main.lang=$lang
		uci commit luci

		nvram set CountryCode=$CountryCode
		nvram commit

		local srv_region=
		local srv_section=
		local srv_name=
		local srv_domain=

		srv_region=$(uci get "country_mapping.$CountryCode.region")
		srv_section="server_${srv_region}"

		for srv_name in "S" "APP" "API" "STUN" "BROKER"; do
			if [ -n "$srv_region" ]; then
				srv_domain=$(uci get "server_mapping.$srv_section.$srv_name")
			else
				#if region not exist, try to use remote config
				srv_domain=$(json_get_value "$jsonbuf" "server_${srv_name}")
			fi

			uci set "miwifi.server.$srv_name=$srv_domain"
		done

		uci commit miwifi
	fi
}

cac_ctrl() {
	local cmd="$1"
	local device_5g=$(uci -q get misc.wireless.if_5G)

	case "$cmd" in
		enable)
			radartool -i $device_5g enable
			;;
		disable)
			radartool -i $device_5g disable
			;;
	esac
}

__init_cap_mode_version4() {
	local mode="$1"
	[ -z "$mode" ] && return

	local support_mesh_ver4=$(mesh_cmd support_mesh_version 4)
	[ "$support_mesh_ver4" != "1" ] && return

	case "$mode" in
		1)
			# 单只装在第一次添加re时，由miwifi-discovery初始化并生效，mode=1
			export restart_miwifi_discovery=0
			export restart_network=1
		;;
		2)
			# web初始化，同步创建好回程ap
			export meshsuite=1
			export restart_network=0
			export restart_miwifi_discovery=1
			#disable bh_ap
			if [ -f "/usr/sbin/mesh_bh_enable" ] && [ -z "$(uci -q get xiaoqiang.common.bhap_enable)" ]; then
				uci -q set xiaoqiang.common.bhap_enable=0
				uci commit xiaoqiang
			fi
		;;
		*)
			return
		;;
	esac
	export support_mesh_ver4=1
	export restart_xq_info_sync_mqtt=1

	# update bh_band
	mesh_cmd backhaul set band "$fac_band"

	local bh_band=$(mesh_cmd backhaul get band)
	local bh_band_upcase=$(echo $bh_band | tr '[a-z]' '[A-Z]')
	local bh_device=$(uci -q get misc.wireless.if_${bh_band_upcase})
	local bh_ifname=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)

	local bhap_sec="bh_ap"
	local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
	[ "$bh_mlo_support" = "1" ] && bhap_sec="bh_ap_${bh_band}"

	local bh_ssid=$(uci -q get wireless.${bhap_sec}.ssid)
	local bh_pswd=$(uci -q get wireless.${bhap_sec}.key)
	[ -z "$bh_ssid" ] && bh_ssid="MiMesh_$(head -n10 /dev/urandom | md5sum | cut -c1-9)"
	[ -z "$bh_pswd" ] && bh_pswd="$(head -n10 /dev/urandom | md5sum | cut -c1-17)"

	set_network_id "$bh_ssid" "$bh_ifname"

	local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)
	if [ "$mesh_support_dfs" != "1" ]; then
		local channel=$(uci -q get wireless.$bh_device.channel)
		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
				uci set wireless.$bh_device.channel='auto'
				uci commit wireless
				;;
			*) ;;
		esac
	fi

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"bsd\":\"0\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\"}}"
	mimesh_init "$buff"
	mimesh_init_done "cap"
	/usr/sbin/topomon_action.sh cap_init
}

# $1有两种含义：
#   1: 初始化mesh配置并生效
#   2：初始化mesh配置，但不做生效操作
#   0或者不传参：不做mesh初始化
init_cap_mode() {
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')
	uci set wireless.$iface_5g.miwifi_mesh=0

	local ifname_5gh=$(uci -q get misc.wireless.ifname_5GH)
	local iface_5gh=$(uci show wireless | grep -w "ifname=\'$ifname_5gh\'" | awk -F"." '{print $2}')
	[ -n "$iface_5gh" ] && uci set wireless.$iface_5gh.miwifi_mesh=0
	uci commit wireless

	/etc/init.d/meshd stop
	__init_cap_mode_version4 "$1"
}

cap_delete_vap() {
	local ifname=$(uci -q get misc.wireless.mesh_ifname_5G)

	local hostapd_pid=$(ps | grep "hostapd\ /var/run/hostapd-${ifname}.conf" | awk '{print $1}')

	[ -z "$hostapd_pid" ] || kill -9 $hostapd_pid

	rm -f /var/run/hostapd-${ifname}.conf

	local wds_ext=$(cfg80211tool "$ifname" get_wds_ext | awk -F':' '{print $2}')
	if [ -n "$wds_ext" -a "$wds_ext" = "1" ]; then
		ifconfig "$ifname" down
		iw "$ifname" del
	else
		wlanconfig $ifname destroy -cfg80211
	fi
}

cap_clean_vap() {
	local ifname=$1
	local name=$(echo $2 | sed s/[:]//g)

	#networking failed statpoints
	if which sp_log_info.sh >/dev/null; then
		sp_log_info.sh -k mesh.re.conn.fail -m "SYNC_FAILED:1"
	fi

	cap_delete_vap
	echo "failed" > /tmp/${name}-status
}

check_cap_init_status_v2() {
	local bh_band=$(mesh_cmd backhaul get band)
	local bh_band_upcase=$(echo $bh_band | tr '[a-z]' '[A-Z]')
	local ifname=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	local device_5g=$(uci -q get misc.wireless.if_${bh_band_upcase})
	local re_5g_mac=$2
	local is_cable=$5
	local re_mesh_ver=$6
	local re_5g_obssid=$7
	[ -z "$is_cable" ] && is_cable=0

	local meshed=$(uci -q get xiaoqiang.common.MESHED)
	for i in $(seq 1 60)
	do
		mimesh_cap_bh_check > /dev/null 2>&1
		if [ $? = 0 ]; then
			if [ "$meshed" != "YES" ] || [ "$support_mesh_ver4" != "1" ]; then
				mimesh_init_done "cap"
				sleep 2
			fi
			init_done=1
			break
		fi
		sleep 2
	done

	if [ $init_done -eq 1 ]; then
		# statpoint to record if meshed
		set_meshed_flag

		for i in $(seq 1 90)
		do
			local assoc_count1=$(iwinfo $ifname a | grep -i -c $3)
			local assoc_count2=$(iwinfo $ifname a | grep -i -c $4)
			local assoc_count3=0
			if [ $(expr $i % 5) -eq 0 ]; then
				assoc_count3=$(ubus call trafficd hw | grep -iwc $re_5g_mac)
			fi
			if [ $is_cable == "1" -o $assoc_count1 -gt 0 -o $assoc_count2 -gt 0 -o $assoc_count3 -gt 0 ]; then
				/sbin/cap_push_backhaul_whitelist.sh
				(sleep 30; /sbin/cap_push_backhaul_whitelist.sh) &
				/usr/sbin/topomon_action.sh cap_init
				echo "success" > /tmp/$1-status
				radartool -i $device_5g enable
				exit 0
			fi
			#for ax9000 mesh2.0(here re_mesh_ver was 3)
			if [ "$re_mesh_ver" -gt "2" ]; then
				[ -n "$re_5g_obssid" -a "00:00:00:00:00:00" != "$re_5g_obssid" ] && {
					local re_obsta_mac1=$(calcbssid -i 1 -m $re_5g_obssid)
					local re_obsta_mac2=$(calcbssid -i 2 -m $re_5g_obssid)
					local assoc_count4=$(iwinfo $ifname a | grep -i -c $re_obsta_mac1)
					local assoc_count5=$(iwinfo $ifname a | grep -i -c $re_obsta_mac2)
					local assoc_count6=0
					if [ $(expr $i % 5) -eq 0 ]; then
						assoc_count6=$(ubus call trafficd hw | grep -iwc $re_5g_obssid)
					fi
					if [ $is_cable == "1" -o $assoc_count4 -gt 0 -o $assoc_count5 -gt 0 -o $assoc_count6 -gt 0 ]; then
						/sbin/cap_push_backhaul_whitelist.sh
						(sleep 30; /sbin/cap_push_backhaul_whitelist.sh) &
						/usr/sbin/topomon_action.sh cap_init
						echo "success" > /tmp/$1-status
						radartool -i $device_5g enable
						exit 0
					fi
				}
			fi
			sleep 2
		done
	fi

	#networking failed statpoints
	if which sp_log_info.sh >/dev/null; then
		sp_log_info.sh -k mesh.re.conn.fail -m "UNSPEC_FAILED:1"
	fi

	echo "failed" > /tmp/$1-status
	radartool -i $device_5g enable
	exit 1
}

do_cap_init_bsd() {
	local name=$(echo $1 | sed s/[:]//g)
	local is_cable=$8
	[ -z "$is_cable" ] && is_cable=0

	#ap添加mesh2.0 re不用做cap的初始化动作，只更新状态
	local product=$(uci -q get misc.features.product)
	if [ "$product" == "ap" -o "$product" == "ac" ]; then
		echo "syncd" > /tmp/${name}-status
		#删掉临时创建的wps接口
		cap_delete_vap
		return
	fi

	#For ethernet mesh, enable backhaul ap
	[ -f /usr/sbin/mesh_bh_enable ] && {
		/usr/sbin/mesh_bh_enable
	}

	local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)
	local bh_band=$(mesh_cmd backhaul get band)
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')

	local ifname_ap_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_ap_2g\'" | awk -F"." '{print $2}')

	local whc_ssid=$(uci -q get wireless.$iface_2g.ssid)
	local whc_pswd=$(uci -q get wireless.$iface_2g.key)
	local whc_mgmt=$(uci -q get wireless.$iface_2g.encryption)

	local ifname_5g=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)

	local bh_ssid=$(printf "%s" "$6" | base64 -d)
	local bh_pswd=$(printf "%s" "$7" | base64 -d)
	local init_done=0

	local device_5g=$(uci -q get misc.wireless.if_${bh_band_upcase})

	local channel=$(uci -q get wireless.$device_5g.channel)
	local bw=$(uci -q get wireless.$device_5g.bw)

	local re_bssid=$1
	local obssid_jsonbuf=
	local obssid=
	local re_mesh_ver=
	[ -f "/var/run/scanrelist" ] && {
		obssid_jsonbuf=$(cat /var/run/scanrelist | grep -i "$re_bssid")
		obssid=$(json_get_value "$obssid_jsonbuf" "obssid")
		re_mesh_ver=$(json_get_value "$obssid_jsonbuf" "mesh_ver")
	}
	[ -z "$re_mesh_ver" ] && re_mesh_ver=2

	echo "syncd" > /tmp/${name}-status

	set_network_id "$bh_ssid" "$ifname_5g"

	cap_delete_vap

	export support_mesh_ver4=$(mesh_cmd support_mesh_version 4)

	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)

	if [ "whc_cap" != "$mode" ] && [ "$mode" != "lanapmode" -o "$cap_mode" != "ap" ]; then
		local bh_maclist_5g=
		local bh_macnum_5g=0

		if [ "$whc_mgmt" == "ccmp" ]; then
			whc_pswd=$(uci -q get wireless.$iface_2g.sae_password)
		fi

		whc_ssid=$(printf "%s" "$whc_ssid" | base64 | xargs)
		whc_pswd=$(printf "%s" "$whc_pswd" | base64 | xargs)

		if [ "$mesh_support_dfs" != "1" ] && [ "$bh_band" = "5g" ]; then
			case "$channel" in
				52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
					uci set wireless.$device_5g.channel='auto'
					uci commit wireless
					;;
				*) ;;
			esac
		fi

		#ignore CAC on first init
		radartool -i $device_5g disable

		local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"whc_ssid\":\"${whc_ssid}\",\"whc_pswd\":\"${whc_pswd}\",\"whc_mgmt\":\"${whc_mgmt}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

		mimesh_init "$buff"
	fi

	check_cap_init_status_v2 $name $1 $3 $5 $is_cable $re_mesh_ver $obssid
}

do_cap_init() {
	local name=$(echo $1 | sed s/[:]//g)
	local is_cable=$8
	[ -z "$is_cable" ] && is_cable=0

	#ap添加mesh2.0 re不用做cap的初始化动作，只更新状态
	local product=$(uci -q get misc.features.product)
	if [ "$product" == "ap" -o "$product" == "ac" ]; then
		echo "syncd" > /tmp/${name}-status
		#删掉临时创建的wps接口
		cap_delete_vap
		return
	fi

	#For ethernet mesh, enable backhaul ap
	[ -f /usr/sbin/mesh_bh_enable ] && {
		/usr/sbin/mesh_bh_enable
	}

	local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)
	local bh_band=$(mesh_cmd backhaul get band)
	local bh_band_upcase=$(echo $bh_band | tr '[a-z]' '[A-Z]')

	local ifname_ap_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_ap_2g\'" | awk -F"." '{print $2}')
	local ifname_ap_5g=$(uci -q get misc.wireless.ifname_${bh_band_upcase})
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_ap_5g\'" | awk -F"." '{print $2}')
	local device_5g=$(uci -q get misc.wireless.if_${bh_band_upcase})

	local ssid_2g=$(uci -q get wireless.$iface_2g.ssid)
	local pswd_2g=$(uci -q get wireless.$iface_2g.key)
	local mgmt_2g=$(uci -q get wireless.$iface_2g.encryption)
	local ssid_5g=$(uci -q get wireless.$iface_5g.ssid)
	local pswd_5g=$(uci -q get wireless.$iface_5g.key)
	local mgmt_5g=$(uci -q get wireless.$iface_5g.encryption)

	local ifname_5g=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)

	local bh_ssid=$(printf "%s" "$6" | base64 -d)
	local bh_pswd=$(printf "%s" "$7" | base64 -d)
	local init_done=0

	local channel=$(uci -q get wireless.$device_5g.channel)
	local bw=$(uci -q get wireless.$device_5g.bw)

	local re_bssid=$1
	local obssid_jsonbuf=
	local obssid=
	local re_mesh_ver=
	[ -f "/var/run/scanrelist" ] && {
		obssid_jsonbuf=$(cat /var/run/scanrelist | grep -i "$re_bssid")
		obssid=$(json_get_value "$obssid_jsonbuf" "obssid")
		re_mesh_ver=$(json_get_value "$obssid_jsonbuf" "mesh_ver")
	}
	[ -z "$re_mesh_ver" ] && re_mesh_ver=2

	echo "syncd" > /tmp/${name}-status

	set_network_id "$bh_ssid" "$ifname_5g"

	cap_delete_vap

	export support_mesh_ver4=$(mesh_cmd support_mesh_version 4)

	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)

	if [ "whc_cap" != "$mode" ] && [ "$mode" != "lanapmode" -o "$cap_mode" != "ap" ]; then
		local bh_maclist_5g=
		local bh_macnum_5g=0

		if [ "$mgmt_2g" == "ccmp" ]; then
			pswd_2g=$(uci -q get wireless.$iface_2g.sae_password)
		fi

		if [ "$mgmt_5g" == "ccmp" ]; then
			pswd_5g=$(uci -q get wireless.$iface_5g.sae_password)
		fi

		ssid_2g=$(printf "%s" "$ssid_2g" | base64 | xargs)
		pswd_2g=$(printf "%s" "$pswd_2g" | base64 | xargs)
		ssid_5g=$(printf "%s" "$ssid_5g" | base64 | xargs)
		pswd_5g=$(printf "%s" "$pswd_5g" | base64 | xargs)

		if [ "$mesh_support_dfs" != "1" ] && [ "$bh_band" = "5g" ]; then
			case "$channel" in
				52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
					uci set wireless.$device_5g.channel='auto'
					uci commit wireless
					;;
				*) ;;
			esac
		fi

		#ignore CAC on first init
		radartool -i $device_5g disable

		local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"bsd\":\"0\",\"ssid_2g\":\"${ssid_2g}\",\"pswd_2g\":\"${pswd_2g}\",\"mgmt_2g\":\"${mgmt_2g}\",\"ssid_5g\":\"${ssid_5g}\",\"pswd_5g\":\"${pswd_5g}\",\"mgmt_5g\":\"${mgmt_5g}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

		mimesh_init "$buff"
	fi

	check_cap_init_status_v2 $name $1 $3 $5 $is_cable $re_mesh_ver $obssid
}

do_re_dhcp() {
	local bridge="br-lan"
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname=$(uci -q get misc.wireless.apclient_${bh_band_upcase})
	local model=$(uci -q get misc.hardware.model)
	[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)

	#tcpdump -i wl11 port 47474 -w /tmp/aaa &
	brctl addif br-lan ${ifname}

	ifconfig br-lan 0.0.0.0

	#udhcpc on br-lan, for re init time optimization
	udhcpc -q -p /var/run/udhcpc-${bridge}.pid -s /usr/share/udhcpc/mesh_dhcp.script -f -t 15 -i $bridge -x hostname:MiWiFi-${model}

	exit $?
}

re_start_wps() {
	local bh_band=$(mesh_cmd backhaul get band)
	local bh_band_upcase=$(echo $bh_band | tr '[a-z]' '[A-Z]')
	local ifname=$(uci -q get misc.wireless.apclient_${bh_band_upcase})
	local ifname_5G=$(uci -q get misc.wireless.ifname_${bh_band_upcase})
	local device=$(uci -q get misc.wireless.${ifname}_device)
	local channel="$2"

	eth_down

	wpa_supplicant_check

	wpa_supplicant_if_remove $ifname
	wlanconfig $ifname destroy -cfg80211

	#case "$channel" in
	#	52|56|60|64|100|104|108|112|116|120|124|128|132|136|140) channel=36
	#		;;
	#	*) ;;
	#esac
	#cfg80211tool $ifname_5G channel $channel
	sleep 2

	local dev_macaddr="$(cat /sys/class/net/${device}/address)"
	local vap_macaddr="$(calcbssid -i1 -m $dev_macaddr)"

	wlanconfig $ifname create wlandev $device wlanmode sta -bssid $vap_macaddr -cfg80211
	iw dev $device interface add $ifname type __ap
	iw dev $ifname set 4addr on >/dev/null 2>&1
	iwpriv ${ifname} wds 1
	iwpriv ${ifname} athnewind 1
	cfg80211tool $ifname channel $channel

	rm -f /var/run/wpa_supplicant-${ifname}.conf
	echo -e "ctrl_interface=/var/run/wpa_supplicant\nctrl_interface_group=0\nupdate_config=1" | tee /var/run/wpa_supplicant-${ifname}.conf

	wpa_supplicant_if_add $ifname "br-lan"
	sleep 1

	wpa_cli -p /var/run/wpa_supplicant-$ifname -i $ifname wps_pbc "$1"

	for i in $(seq 1 60)
	do
		status=$(wpa_cli -p /var/run/wpa_supplicant-$ifname -i ${ifname} status | grep ^wpa_state= | cut -f2- -d=)
		if [ "$status" == "COMPLETED" ]; then
			#do_re_init $ifname $1
			exit 0
		fi
		sleep 2
	done

	eth_up

	wpa_supplicant_if_remove $ifname
	rm -f /var/run/wpa_supplicant-${ifname}.conf
	wlanconfig $ifname destroy -cfg80211
	#wifi

	exit 1
}

cap_create_vap() {
	local ifname="$2"
	local device="$1"
	local channel="$3"
	local wifi_mode="$4"
	local re_mesh_ver="$5"
	local is_tri_band=$(mesh_cmd is_tri_band)
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname_5G=$(uci -q get misc.wireless.ifname_${bh_band_upcase})
	local macaddr=$(cat /sys/class/net/br-lan/address)
	local uuid=$(echo "$macaddr" | sed 's/://g')
	local ssid="wps_$(head -n10 /dev/urandom | md5sum | cut -c1-16)"
	local key=$(openssl rand -base64 8 | md5sum | cut -c1-32)
	local model=$(uci -q get misc.hardware.model)
	[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)

	cp -f /usr/share/mesh/hostapd-template.conf /var/run/hostapd-${ifname}.conf

	local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)
	if [ "$mesh_support_dfs" != "1" ] && [ -n "$re_mesh_ver" -a "$re_mesh_ver" -lt 3 ]; then
		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
				channel=36
				if [ "$wifi_mode" = "11AHE160" -o "$wifi_mode" = "11ACVHT160" ]; then
					[ "$wifi_mode" = "11AHE160" ] && wifi_mode="11AHE80" || wifi_mode="11ACVHT80"
					cfg80211tool $ifname_5G mode $wifi_mode
					sleep 1
				fi
				;;
			*) ;;
		esac
	fi

	local wds_ext=$(cfg80211tool "$ifname_5G" get_wds_ext | awk -F':' '{print $2}')
	if [ -n "$wds_ext" -a "$wds_ext" = "1" ]; then
		echo -e "wds_sta=1" >> /var/run/hostapd-${ifname}.conf
	fi

	echo -e "interface=$ifname" >> /var/run/hostapd-${ifname}.conf
	echo -e "model_name=$model" >> /var/run/hostapd-${ifname}.conf
	[ -z "$channel" ] || echo -e "channel=$channel" >> /var/run/hostapd-${ifname}.conf
	echo -e "wpa_passphrase=$key" >> /var/run/hostapd-${ifname}.conf
	echo -e "ssid=$ssid" >> /var/run/hostapd-${ifname}.conf
	echo -e "uuid=87654321-9abc-def0-1234-$uuid" >> /var/run/hostapd-${ifname}.conf
	echo -e "ctrl_interface=/var/run/hostapd-$device" >> /var/run/hostapd-${ifname}.conf

	wlanconfig $ifname create wlandev $device wlanmode ap -cfg80211
	iw dev $device interface add $ifname type __ap

	[ -z "$channel" ] || cfg80211tool $ifname channel $channel
	[ -z "$wifi_mode" ] || cfg80211tool $ifname mode $wifi_mode

	for i in $(seq 1 10)
	do
		sleep 2
		local acs_state_son=$(iwpriv $ifname get_acs_state | cut -f2- -d ':')
		local acs_state_main=$(iwpriv $ifname_5G get_acs_state | cut -f2- -d ':')
		if [ $acs_state_son -eq 0 -a $acs_state_main -eq 0 ]; then
			break
		fi
	done

	hostapd /var/run/hostapd-${ifname}.conf &
}

cap_start_wps() {
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname=$(uci -q get misc.wireless.mesh_ifname_5G)
	local device=$(uci -q get misc.wireless.if_${bh_band_upcase})
	local status_file=$(echo $1 | sed s/[:]//g)
	local ifname_5G=$(uci -q get misc.wireless.ifname_${bh_band_upcase})
	local wifi_mode=$(cfg80211tool "$ifname_5G" get_mode | awk -F':' '{print $2}')
	local channel=$(iwinfo "$ifname_5G" f | grep \* | awk '{print $5}' | sed 's/)//g')
	local re_bssid=$1
	local obssid_jsonbuf=$(cat /var/run/scanrelist | grep -i "$re_bssid")
	local obssid=$(json_get_value "$obssid_jsonbuf" "obssid")
	local re_mesh_ver=$(json_get_value "$obssid_jsonbuf" "mesh_ver")
	[ -z "$re_mesh_ver" ] && re_mesh_ver=2
	local obsta_mac="00:00:00:00:00:00"
	[ -n "$obssid" -a "00:00:00:00:00:00" != "$obssid" ] && obsta_mac=$(calcbssid -i 1 -m $obssid)

	echo "init" > /tmp/${status_file}-status
	radartool -n -i $device ignorecac 1
	radartool -n -i $device disable
	sleep 2
	cap_create_vap "$device" "$ifname" "$channel" "$wifi_mode" "$re_mesh_ver"
	sleep 2

	iwpriv $ifname miwifi_mesh 2
	iwpriv $ifname miwifi_mesh_mac $1
	iwpriv $ifname mesh_ver $re_mesh_ver

	cfg80211tool $ifname maccmd_sec 3
	#cfg80211tool $ifname addmac_sec $2
	#[ -n "$obsta_mac" -a "00:00:00:00:00:00" != "$obsta_mac" ] && cfg80211tool $ifname addmac_sec $obsta_mac
	cfg80211tool $ifname maccmd_sec 0

	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid update_beacon
	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid wps_pbc

	for i in $(seq 1 60)
	do
		wps_status=$(hostapd_cli -i ${ifname} -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid wps_get_status | grep 'Last\ WPS\ result:' | cut -f4- -d ' ')
		pbc_status=$(hostapd_cli -i ${ifname} -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid wps_get_status | grep 'PBC\ Status:' | cut -f3- -d ' ')
		if [ "$wps_status" == "Success" ]; then
			if [ "$pbc_status" == "Disabled" ]; then
				echo "connected" > /tmp/${status_file}-status
				cap_disable_wps_trigger  $device $ifname

				radartool -n -i $device enable
				radartool -n -i $device ignorecac 0

				exit 0
			fi
		fi
		sleep 2
	done

	#networking failed statpoints
	if which sp_log_info.sh >/dev/null; then
		sp_log_info.sh -k mesh.re.conn.fail -m "CONNECT_FAILED:1"
	fi

	#cap_close_wps
	cap_delete_vap
	echo "failed" > /tmp/${status_file}-status

	radartool -n -i $device enable
	radartool -n -i $device ignorecac 0

	local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)
	if [ "$mesh_support_dfs" != "1" ] && [ "$re_mesh_ver" -lt 3 ]; then
		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
				cfg80211tool $ifname_5G channel $channel
				if [ "$wifi_mode" = "11AHE160" -o "$wifi_mode" = "11ACVHT160" ]; then
					cfg80211tool $ifname_5G mode $wifi_mode
				fi
				;;
			*) ;;
		esac
	fi

	exit 1
}

__wifi_hostap_mlo_setup()
{
    local enable=$1
    [ -z "$enable" ] && enable=0
    [ -z "$(uci -q show misc.mld)" ] && return

    local mld_radios="$(uci -q get misc.mld.hostap_mlo | tr , " " | tr '[a-z]' '[A-Z]')"
    if [ -n "$mld_radios" ]; then
        local mld_ssid=
        local mld_dev="$(uci -q get misc.mld.hostap)"
        for radio in $mld_radios; do
            local ifname=$(uci -q get misc.wireless.ifname_$radio)
            local iface=$(uci show wireless | grep -w "ifname=\'$ifname\'" | awk -F"." '{print $2}')
            if [ "$enable" = "1" ]; then
                uci -q set wireless.$iface.mld="$mld_dev"
                [ -z "$mld_ssid" ] && mld_ssid="$(uci -q get wireless.$iface.ssid)"
            else
                uci -q set wireless.$iface.mld=
            fi
        done

        uci -q set wireless.$mld_dev.mld_ssid="$mld_ssid"
        if [ "$enable" = "1" ]; then
            uci -q set wireless.$mld_dev.mlo_enable=1
        else
            uci -q set wireless.$mld_dev.mlo_enable=0
        fi
    fi
}

# for vap_mlo
__wifi_mlo_vap_setup()
{
	local mlo_enable=$1
	local mlo_ssid=$2
	local mlo_hidden=$3
	local mlo_enc=$4
	local mlo_pwd=$5
	local disabled=

	[ -z "$(uci -q show misc.mld)" ] && return

	[ -z "$mlo_enable" ] && mlo_enable="0"
	[ -z "$mlo_hidden" ] && mlo_hidden="0"
	[ -z "$mlo_enc" ] && mlo_enc="ccmp"
	[ "$mlo_enable" = '1' ] && disabled='0' || disabled='1'

	local mld_radios="$(uci -q get misc.mld.hostap_mlo | tr , " " | tr '[a-z]' '[A-Z]')"
	if [ -n "$mld_radios" ]; then
		local mld_dev="$(uci -q get misc.mld.hostap)"
		for radio in $mld_radios; do
			local ifname=$(uci -q get misc.wireless.ifname_mlo_$radio)
			local iface=$(uci show wireless | grep -w "ifname=\'$ifname\'" | awk -F"." '{print $2}')
			# set vap's cfg
			uci -q set wireless.$iface.disabled="$disabled"
			uci -q set wireless.$iface.mld="$mld_dev"
			uci -q set wireless.$iface.ssid="$mlo_ssid"
			uci -q set wireless.$iface.hidden="$mlo_hidden"
			uci -q set wireless.$iface.encryption="ccmp"
			if [ "$mlo_enc" = "ccmp" ]; then
				uci -q set wireless.$iface.owe="0"
				uci -q set wireless.$iface.sae="1"
				uci -q set wireless.$iface.key=""
				uci -q set wireless.$iface.sae_password="$mlo_pwd"
				uci -q set wireless.$iface.ieee80211w="2"
			elif [ "$mlo_enc" = "owe" ]; then
				uci -q set wireless.$iface.owe="1"
				uci -q set wireless.$iface.sae=""
				uci -q set wireless.$iface.key=""
				uci -q set wireless.$iface.sae_password=""
				uci -q set wireless.$iface.ieee80211w="2"
			fi
		done

		# set hostap's cfg
		uci -q set wireless.$mld_dev.mlo_enable="$mlo_enable"
		uci -q set wireless.$mld_dev.mlo_ssid="$mlo_ssid"
		uci -q set wireless.$mld_dev.mlo_hidden="$mlo_hidden"
		uci -q set wireless.$mld_dev.mlo_enc="$mlo_enc"
		uci -q set wireless.$mld_dev.mlo_pwd="$mlo_pwd"
	fi
}

# backup: wireless,network,dhcp
re_connect_backup_cfg() {
	[ -d "/var/run/mesh_backup" ] && return
	mkdir -p /var/run/mesh_backup
	cp /etc/config/wireless /var/run/mesh_backup/
	cp /etc/config/network /var/run/mesh_backup/
	cp /etc/config/dhcp /var/run/mesh_backup/
	cp /etc/config/xiaoqiang /var/run/mesh_backup/
}

# restore: wireless,network,dhcp
re_connect_restore_cfg() {
	[ -d "/var/run/mesh_backup" ] || return
	cp /var/run/mesh_backup/* /etc/config/
	rm /var/run/mesh_backup -rf >>/dev/null
}

# called while init_sync failed
re_connect_clean() {
	local bh_band=$(mesh_cmd backhaul get band)
	local ifname=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)

	ifconfig $ifname down
	wpa_supplicant_if_remove $ifname
	wlanconfig $ifname destroy -cfg80211
	ubus call network.interface.lan remove_device "{\"name\":\"$ifname\"}"

	# restore config
	re_connect_restore_cfg
	wifi update &

	local lanip=$(uci -q get network.lan.ipaddr)
	if [ "$lanip" != "" ]; then
		ifconfig br-lan $lanip
	else
		ifconfig br-lan 192.168.31.1
	fi
	eth_up

	ubus call network reload
	/etc/init.d/dnsmasq restart
	/etc/init.d/meshd start
	/etc/init.d/cab_meshd start
}

freq2band() {
	local freq=$1

	if [ $freq -le 2472 ]; then
		local channel=$(((freq - 2412)/5 + 1))
		local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
		[ $channel -gt 0 -a $channel -lt 10 ] && channel="0$channel"
		local match=$(iwlist $ifname_2g ch 2>>/dev/null | grep "\<Channel $channel\>")
		[ -n "$match" ] && echo "2g" && return
	else
		local channel="Channel $(((freq - 5000)/5))"
		local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
		local ifname_5gh=$(uci -q get misc.wireless.ifname_5GH)
		local bh_ap_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
		local bh_ap_5gh=$(uci -q get misc.backhauls.backhaul_5gh_ap_iface)

		if [ -n "$ifname_5g" ]; then
			local match=$(iwlist $ifname_5g ch 2>>/dev/null | grep "\<$channel\>")
			[ -n "$match" ] && echo "5g" && return
		fi
		if [ -n "$bh_ap_5g" ]; then
			local match=$(iwlist $bh_ap_5g ch 2>>/dev/null | grep "\<$channel\>")
			[ -n "$match" ] && echo "5g" && return
		fi

		if [ -n "$ifname_5gh" ]; then
			local match=$(iwlist $ifname_5gh ch 2>>/dev/null 2>>/dev/null | grep "\<$channel\>")
			[ -n "$match" ] && echo "5gh" && return
		fi
		if [ -n "$bh_ap_5gh" ]; then
			local match=$(iwlist $bh_ap_5gh ch 2>>/dev/null 2>>/dev/null | grep "\<$channel\>")
			[ -n "$match" ] && echo "5gh" && return
		fi
	fi
}

check_bhsta_is_connected() {
	local bhsta_list=""
	local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
	local cur_band="$(mesh_cmd backhaul get real_band)"
	local slo_backup=0

	# mlo check
	if [ "$bh_mlo_support" = "1" ]; then
		local mlo_members=$(uci -q get wireless.bh_sta_mlo.mlo)
		for mem in $mlo_members; do
			local tmp_ifname=$(uci -q get misc.backhauls.backhaul_${mem}_sta_iface)
			[ -z "$tmp_ifname" ] && continue
			[ -z "$bhsta_list" ] && bhsta_list="$tmp_ifname" || bhsta_list="$bhsta_list $tmp_ifname"
		done
	fi

	# connect status check
	[ -z "$bhsta_list" ] && bhsta_list="$(uci -q get misc.backhauls.backhaul_${cur_band}_sta_iface)"
	for i in $(seq 1 60); do
		if [ "$slo_backup" = "0" ]; then
			mimesh_re_check_slo_backup
			slo_backup="$?"
		fi
		if [ "$slo_backup" = "1" ]; then
			local slo_backup_band=$(uci -q get misc.mld.slo_backup)
			bhsta_list=$(uci -q get misc.backhauls.backhaul_${slo_backup_band}_sta_iface)
			slo_backup=2
		fi
		for sta in $bhsta_list; do
			local status=$(wpa_cli -p /var/run/wpa_supplicant-$sta -i ${sta} status | grep ^wpa_state= | cut -f2- -d=)
			[ "$status" == "COMPLETED" ] && return 1
		done
		sleep 1
	done
	return 0
}

re_connect_sp_log() {
	local connType="mlo" 
	local sta_mlo=$(uci -q get wireless.bh_sta_mlo.mlo)
	local mlo_failed_times=0
	local ifname2G=$(uci -q get misc.wireless.ifname_2G)
	local ifname5G=$(uci -q get misc.wireless.ifname_5G)
	local bh_2g_ifname=$(uci -q get wireless.bh_sta_2g.ifname)
	local bh_5g_ifname=$(uci -q get wireless.bh_sta_5g.ifname)
	local bh_2g_up=`ifconfig $bh_2g_ifname > /dev/null 2>&1;echo $?`
	local bh_5g_up=`ifconfig $bh_5g_ifname > /dev/null 2>&1;echo $?`
	local bh_2g_rssi=0
	local bh_5g_rssi=0

	[ -z "$sta_mlo" ] && {
		connType="slo"
	}

	[ -f "/tmp/mlo_failed_times" ] && {
		mlo_failed_times=`cat /tmp/mlo_failed_times`
	}

	local chutil_5G=`cfg80211tool $ifname5G get_chutil|cut -d":" -f 2`
	local chutil_2G=`cfg80211tool $ifname2G get_chutil|cut -d":" -f 2`

	[ "$bh_2g_up" == "0" ] && {
		bh_2g_rssi=`iwconfig ${bh_2g_ifname}|grep "Signal"| awk -F 'Signal level=' '{print $2}' | awk '{print $1}' | sed 's/dBm//'`
	}

	[ "$bh_5g_up" == "0" ] && {
		bh_5g_rssi=`iwconfig ${bh_5g_ifname}|grep "Signal"| awk -F 'Signal level=' '{print $2}' | awk '{print $1}' | sed 's/dBm//'`
	}

	sp_log_info.sh -k mesh.re.conn.info -m "$connType,$mlo_failed_times,$chutil_2G,$chutil_5G,$bh_2g_rssi,$bh_5g_rssi"
}

re_connect() {
	local ssid="$1"
	local passwd="$2"
	local mgmt="$3"
	local uplink_ip="$4"
	local ch_freq="$5"
	local cap_band="$6"
	local proto=''
	local mimesh_freq=''
	local key_mgmt='NONE'
	local channel=''

	local main_band=$(freq2band $ch_freq)
	[ -z "$main_band" ] && main_band="5g"
	[ -z "$cap_band" ] && cap_band="$main_band"

	local ifname=$(uci -q get misc.backhauls.backhaul_${cap_band}_sta_iface)
	local cap_band_upcase=$(echo $cap_band | tr '[a-z]' '[A-Z]')
	local device=$(uci -q get misc.wireless.if_${cap_band_upcase})
	local ap_ifname=$(uci -q get misc.wireless.ifname_${cap_band_upcase})
	local mesh_bhap_ifaces=$(mesh_cmd mesh_iface bh_ap)
	[ -z "$mesh_bhap_ifaces" ] && mesh_bhap_ifaces="$ap_ifname"

	log "re to connect bssid:$bssid ssid:$ssid mgmt:$mgmt freq:$ch_freq"

	/etc/init.d/meshd stop
	/etc/init.d/cab_meshd stop

	wpa_supplicant_check

	radartool -n -i $device ignorecac 1
	radartool -n -i $device disable

	eth_down
	re_connect_backup_cfg

	if [ -n "$ch_freq" ] && [ "$cap_band" = "$main_band" ]; then
		eval 'export mimesh_freq_${ifname}="mimesh_freq=$ch_freq"'
	fi

	for tmp_ifname in $mesh_bhap_ifaces; do
		set_network_id "$ssid" "$tmp_ifname"
	done
	mesh_cmd backhaul set real_band "$cap_band"
	mesh_cmd backhaul set band "$main_band"
	__init_wifi_bh_sta "$ssid" "$mgmt" "$passwd"

	wifi update

	__re_dhcp() {
		local bridge=$1
		local ifname=$2
		local model=$(uci -q get misc.hardware.model)
		[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)

		local mlo_list=$(uci -q get wireless.bh_sta_mlo.mlo)
		if [ -n "$mlo_list" ]; then
			for band in $mlo_list; do
				local tmp_ifname=$(uci -q get misc.backhauls.backhaul_${band}_sta_iface)
				ubus call network.interface.lan add_device "{\"name\":\"$tmp_ifname\"}"
			done
		else
			ubus call network.interface.lan add_device "{\"name\":\"$ifname\"}"
		fi
		ifconfig br-lan 0.0.0.0

		#udhcpc on br-lan, for re init time optimization
		udhcpc -q -p /var/run/udhcpc-${bridge}.pid -s /usr/share/udhcpc/mesh_dhcp.script -f -t 15 -i $bridge -x hostname:MiWiFi-${model}

		return $?
	}

	# check bh_sta if connected
	check_bhsta_is_connected
	local connect_ok="$?"

	# check gw if ok
	local gw_ok=0
	if [ $connect_ok -eq 1 ]; then
		if __re_dhcp "br-lan" $ifname; then
			for i in $(seq 1 30)
			do
				if ping $uplink_ip -c 1 -w 4 > /dev/null 2>&1; then
					re_connect_sp_log
					exit 0
				fi
				sleep 1
			done
		fi
	fi

	re_connect_clean
	radartool -i $device enable
	radartool -n -i $device ignorecac 0
	exit 1
}

channel_modify()
{
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname_5G=$(uci -q get misc.wireless.ifname_${bh_band_upcase})
	local channel=$(iwinfo "$ifname_5G" f | grep \* | awk '{print $5}' | sed 's/)//g')
	local wifi_mode=$(cfg80211tool "$ifname_5G" get_mode | awk -F':' '{print $2}')
	local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)

	if [ "$mesh_support_dfs" != "1" ]; then
		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
				cfg80211tool $ifname_5G channel 36
				if [ "$wifi_mode" = "11AHE160" -o "$wifi_mode" = "11ACVHT160" ]; then
					cfg80211tool $ifname_5G mode $wifi_mode
				fi
				exit 0
				;;
			*) ;;
		esac
	fi
	exit 1
}

do_init_mesh_hop()
{
	local hop="$1"
	local bh_band_upcase=$(mesh_cmd backhaul get band | tr '[a-z]' '[A-Z]')
	local ifname_5G=$(uci -q get misc.wireless.ifname_${bh_band_upcase})

	[ -z "$hop" ] && hop=0
	cfg80211tool $ifname_5G mesh_hop "$hop"
}

setup_scaniface()
{
	local band=$(echo $1 | tr '[a-z]' '[A-Z]')
	local ifname="$2"
	local channel=36
	local mode="11AHE80"
	local device=$(uci -q get misc.wireless.if_${band})

	[ -z "$band" -o -z "$ifname" ] && echo "" && exit 0
	[ "$band" = "5gh" ] && channel=149
	[ "$band" = "2g" ] && channel=6
	cap_create_vap "$device" "$ifname" "$channel" "$mode"
	sleep 2

	echo "$ifname"
}

clean_scaniface()
{
	local ifname="$1"
	[ -z "$ifname" ] && return

	local hostapd_pid=$(ps | grep "hostapd\ /var/run/hostapd-${ifname}.conf" | awk '{print $1}')
	[ -z "$hostapd_pid" ] || kill -9 $hostapd_pid
	rm -f /var/run/hostapd-${ifname}.conf
	wlanconfig $ifname destroy -cfg80211
}

set_mesh_status()
{
	local re_mac="$1"
	local status="$2"
	echo "$status" > /tmp/${re_mac}-status
}

ap_pruduct_wifi()
{
	local op=$1
	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local option_2g=$(uci show wireless | grep ifname | grep -w $ifname_2g | awk -F '.' '{print $2}')
	local option_5g=$(uci show wireless | grep ifname | grep -w $ifname_5g | awk -F '.' '{print $2}')

	if [ "$op" == "set_ssid" ]; then
		local ssid=$2
		uci -q set wireless.$option_2g.ssid="$ssid"
		uci -q set wireless.$option_2g.disabled='0'
		uci -q set wireless.$option_2g.hidden='0'
		uci -q set wireless.$option_5g.ssid="$ssid"
		uci -q set wireless.$option_5g.disabled='0'
		uci -q set wireless.$option_5g.hidden='0'
		uci commit wireless
		wifi update
	elif [ "$op" == "get_ssid" ]; then
		echo "$(uci -q get wireless.$option_2g.ssid)"
	elif [ "$op" == "get_status" ]; then
		local disabled_5g=$(uci -q get wireless.$option_5g.disabled)
		local disabled_2g=$(uci -q get wireless.$option_2g.disabled)
		local userswitch_5g=$(uci -q get wireless.$option_5g.userswitch)
		local userswitch_2g=$(uci -q get wireless.$option_2g.userswitch)
		if [ "$disabled_5g" = "1" -o "$userswitch_5g" = "0" ] || [ "$disabled_2g" = "1" -o "$userswitch_2g" = "0" ]; then
			echo "0"
		else
			echo "1"
		fi

	fi
}

set_meshd_scan()
{
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	/usr/sbin/meshd -s -i $ifname_5g | grep mac > /tmp/active_scan_relist
}

case "$1" in
	re_connect)
	shift 1
	re_connect "$@"
	;;
	cac_ctrl)
	shift 1
	cac_ctrl "$@"
	;;
	channel_modify)
	channel_modify
	;;
	re_connect_clean)
	re_connect_clean
	;;
	init_mesh_hop)
	shift 1
	do_init_mesh_hop "$@"
	;;
	re_start)
	re_start_wps "$2" "$3"
	;;
	cap_start)
	cap_start_wps "$2" "$3"
	;;
	cap_close)
	cap_close_wps
	;;
	init_cap)
	shift 1
	init_cap_mode "$@"
	;;
	cap_init)
	run_with_lock do_cap_init "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	;;
	cap_init_bsd)
	do_cap_init_bsd "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	;;
	re_init)
	run_with_lock do_re_init "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}"
	;;
	re_init_bsd)
	do_re_init_bsd "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	;;
	re_dhcp)
	do_re_dhcp
	;;
	cap_create)
	cap_create_vap "$2" "$3"
	;;
	cap_clean)
	cap_clean_vap "$2" "$3"
	;;
	re_clean)
	re_clean_vap
	;;
	re_init_json)
	do_re_init_json "$2"
	;;
	setup_scaniface)
	setup_scaniface "$2" "$3"
	;;
	clean_scaniface)
	clean_scaniface "$2"
	;;
	meshed)
	set_meshed_flag
	;;
	mesh_status)
	set_mesh_status "$2" "$3"
	;;
	ap_pruduct_wifi)
	ap_pruduct_wifi "$2" "$3"
	;;
	meshd_scan)
	set_meshd_scan
	;;
	*)
	usage
	;;
esac
