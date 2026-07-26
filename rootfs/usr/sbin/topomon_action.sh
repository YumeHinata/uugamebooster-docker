#!/bin/sh

. /lib/functions.sh

XQWHC_WIFI_LOCK="/var/run/xqwhc_wifi.lock"
TOPOMON_ACTION_FILE_LOCK="/tmp/lock/topomon_action_file.lock"
TOPOMON_STATUS_DIR="/var/run/topomon"

# bit mapping for backhauls represent
BACKHAUL_BMP_2g=0
BACKHAUL_BMP_5g=1
BACKHAUL_BMP_5gh=2
BACKHAUL_BMP_resv=2
BACKHAUL_BMP_eth=3
BACKHAUL_QA_BMP_GOOD=1
BACKHAUL_QA_BMP_POOR=0

RSSI_THRESHOLD_FAR=-70
RSSI_THRESHOLD_NEAR=-50

ROLE_CAP=0
ROLE_RE=1

log(){
	logger -t "topomon action: " -p9 "$1"
}
topomon_action_file_lock()
{
	[ "$1" = "lock" ] && {
		arg="-w"
	} || {
		arg="-u"
	}

	lock "$arg" ${TOPOMON_ACTION_FILE_LOCK}_$2
}

cfg80211tool()
{
	[ -f /usr/sbin/cfg80211tool ] && /usr/sbin/cfg80211tool "$@"
}

wpa_cli()
{
	[ -f /usr/sbin/wpa_cli ] && /usr/sbin/wpa_cli "$@"
}

hostapd_cli()
{
	[ -f /usr/sbin/hostapd_cli ] && /usr/sbin/hostapd_cli "$@"
}

function int2ip()
{
	local hex=$1
	local a=$((hex>>24))
	local b=$((hex>>16&0xff))
	local c=$((hex>>8&0xff))
	local d=$((hex&0xff))

	echo "$a.$b.$c.$d"
}
 
function ip2int()
{
	local ip=$1
	local a=$(echo $ip | awk -F'.' '{print $1}')
	local b=$(echo $ip | awk -F'.' '{print $2}')
	local c=$(echo $ip | awk -F'.' '{print $3}')
	local d=$(echo $ip | awk -F'.' '{print $4}')

	echo "$(((a << 24) + (b << 16) + (c << 8) + d))"
}

__setkv()
{
	matool --method setKV --params "$1" "$2" >/dev/null 2>&1 || {
		log " matool setkv $1 $2 failed!"
	}
}

bhtype_2_xquci() {
	[ -z "$1" ] && return
	local bh_type=$1
	local uci_bh_type=$(uci -q get xiaoqiang.common.EASYMESH_CONNECT_MODE)
	if [ "${bh_type}" == "wireless" -a "${uci_bh_type}" != "wifi" ]; then
		uci set xiaoqiang.common.EASYMESH_CONNECT_MODE='wifi'
		uci commit xiaoqiang
		[ -x "/etc/init.d/mapd" ] && /etc/init.d/mapd restart
	fi

	if [ "${bh_type}" == "wired" -a "${uci_bh_type}" != "wired" ]; then
		uci set xiaoqiang.common.EASYMESH_CONNECT_MODE='wired'
		uci commit xiaoqiang
		#切换有线组网需要放开BH接口AP MESH LIMIT
		BACKHAUL_BSS_5G=$(uci -q get wireless.backhaul_5g.ifname)
		[ -z "$BACKHAUL_BSS_5G" ] && BACKHAUL_BSS_5G="wl5"
		cfg80211tool "$BACKHAUL_BSS_5G" mesh_aplimit 9
		[ -x "/etc/init.d/mapd" ] && /etc/init.d/mapd restart
	fi
}

topomon_update_status() {
	local option="$1"
	local value="$2"

	if [ -n $option -a -d $TOPOMON_STATUS_DIR ]; then
		local status_file="${TOPOMON_STATUS_DIR}/${option}"
		topomon_action_file_lock lock "$option"
		if [ -z $value ]; then
			unlink $status_file
		else
			echo -e $value > $status_file
		fi
		topomon_action_file_lock unlock "$option"

		[ "$option" = "port_name" ] && {
			port_service reloadfw guest > /dev/null 2>&1
		}
	fi
}

topomon_current_status() {
	local option="$1"
	if [ -n $option ]; then
		local status_file="${TOPOMON_STATUS_DIR}/${option}"
		if [ -f $status_file ]; then
			topomon_action_file_lock lock "$option"
			cat $status_file
			topomon_action_file_lock unlock "$option"
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

ezmesh_recovery_11ax()
{
	local controller_feature=$(uci -q get xiaoqiang.common.CONTROLLER_FEATURE)
	if [ -n "$controller_feature" -a "$controller_feature" != "xiaomi" ]; then
		local FRONTHAUL_AP_5G=$(uci -q get misc.wireless.ifname_5G)
		[ -z "$FRONTHAUL_AP_5G" ] && FRONTHAUL_AP_5G="wl0"
		local wifimode=$(uci -q get wireless.$FRONTHAUL_AP_5G.wifimode)
		local bw=$(uci -q get wireless.wifi1.bw)
		[ "$wifimode" == "11axa" ] && {
			local real_mode=$(iwpriv $FRONTHAUL_AP_5G get_mode | awk -F ':' '{print $2}')
			if [ "$real_mode" == "11ACVHT80" -a "$bw" == 0 ]; then
				iwpriv $FRONTHAUL_AP_5G mode 11AHE80
				iwpriv $FRONTHAUL_AP_5G mode 11AHE160
			elif [ "$real_mode" == "11ACVHT160" ]; then
				iwpriv $FRONTHAUL_AP_5G mode 11AHE160
			elif [ "$real_mode" == "11ACVHT80" ]; then
				iwpriv $FRONTHAUL_AP_5G mode 11AHE80
			fi
		}
	fi
}

__topomon_wifi_if_down() {
	local sta_iface=$1
	local network_id=
	if [ -n "$sta_iface" ]; then
		network_id=`wpa_cli -p /var/run/wpa_supplicant-$sta_iface list_network | grep CURRENT | awk '{print $1}'`
		if [ -z  $network_id ]; then
			network_id=0
		fi
		log "Interface $sta_iface Brought down with network id $network_id"
		wpa_cli -p /var/run/wpa_supplicant-$sta_iface disable_network $network_id
		ezmesh_recovery_11ax
	fi
}

__topomon_wifi_if_up() {
	local sta_iface=$1
	local network_id=
	local bh_band=$(mesh_cmd backhaul get real_band)
	local bh_ap_ifname=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	local mesh_id=$(uci -q get xiaoqiang.common.NETWORK_ID)

	if [ -n "$sta_iface" ]; then
		if [ -n "$bh_ap_ifname" ] && [ -n "$mesh_id" ]; then
			cfg80211tool $bh_ap_ifname mesh_id "0x${mesh_id}"
		fi

		ifconfig $sta_iface > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			network_id=`wpa_cli -p /var/run/wpa_supplicant-$sta_iface list_network | grep DISABLED | awk '{print $1}'`
			if [ -z  $network_id ]; then
				network_id=0
			fi
			log "Interface $sta_iface Brought up with network id $network_id"
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface enable_network $network_id
		else
			local wifi_iface=$(uci show wireless | grep ".ifname=\'$sta_iface\'" | awk -F"." '{print $2}')
			uci set wireless.$wifi_iface.disabled=0
			uci commit wireless
			wifi update
			wpa_cli -i $sta_iface -p /var/run/wpa_supplicant-$sta_iface enable 0
		fi
	fi
}

topomon_wifi_mld_down() {
	local mlo_sets=$(uci -q get wireless.bh_sta_mlo.mlo)
	for radio in ${mlo_sets}; do
		local sta_iface=$(uci -q get misc.backhauls.backhaul_${radio}_sta_iface)
		__topomon_wifi_if_down "$sta_iface"
	done
}

topomon_wifi_mld_up() {
	local mesh_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local mlo_sets=$(uci -q get wireless.bh_sta_mlo.mlo)

	for radio in ${mlo_sets}; do
		local sta_iface=$(uci -q get misc.backhauls.backhaul_${radio}_sta_iface)
		local ap_iface=$(uci -q get misc.backhauls.backhaul_${radio}_ap_iface)
		cfg80211tool $ap_iface mesh_id "0x${mesh_id}"
		__topomon_wifi_if_up "$sta_iface"
	done
}

topomon_wifi_if_down() {
	if [ -z "$(uci -q get wireless.bh_sta_mlo.mlo)" ]; then
		__topomon_wifi_if_down "$1"
	else
		topomon_wifi_mld_down
	fi
}

topomon_wifi_if_up() {
	if [ -z "$(uci -q get wireless.bh_sta_mlo.mlo)" ]; then
		__topomon_wifi_if_up "$1"
	else
		topomon_wifi_mld_up
	fi
}

set_backhaul_ap_aplimit() {
	local bh_wlan_iface="$1"
	local hop_count="$2"

	local is_ezmesh=$(uci -q get misc.mesh.easymesh)
	[ "$is_ezmesh" == "1" ] && {
		#和第三方设备组网:无法获取hop_count, 这里逻辑不需要设置aplimit
		local controller_feature=$(uci -q get xiaoqiang.common.CONTROLLER_FEATURE)
		local vendor_info=$(uci -q get xiaoqiang.common.vendorinfo | grep miwifi)
		if [ -n "$controller_feature" -a "$controller_feature" != "xiaomi" ]; then
			return
		fi
	}

	[ -z "$bh_wlan_iface" -o -z "$hop_count" ] && return

	if [ $hop_count = "0" ]; then
		cfg80211tool $bh_wlan_iface mesh_aplimit 3
	elif [ $hop_count = "1" ]; then
		cfg80211tool $bh_wlan_iface mesh_aplimit 2
	else
		cfg80211tool $bh_wlan_iface mesh_aplimit 0
		local bh_band_upcase=$(mesh_cmd backhaul get real_band | tr '[a-z]' '[A-Z]')
		local device_5g=$(uci -q get misc.wireless.if_${bh_band_upcase})
		hostapd_cli -i $bh_wlan_iface -p /var/run/hostapd-${device_5g} list_sta | while read line;do sleep 1;cfg80211tool $bh_wlan_iface kickmac $line;done
	fi
}

mlo_uplink_bssid_check() {
	local mlo_sets="$1"
	local mlo_members="$2"
	local is_different=0

	[ -z "$mlo_sets" -o -z "$mlo_members" ] && return

	mlo_sets="${mlo_sets},"
	for mem in $mlo_members; do
		local tmp_iface=$(uci -q get wireless.bh_sta_$mem.ifname)
		local tmp_bssid=$(echo $mlo_sets|eval "sed -ne 's/.*\($mem@\)\([^,]*\),.*/\2/p'")

		iwconfig $tmp_iface 2>/dev/null | grep -q -i $tmp_bssid
		if [ "$?" != "0" ]; then
			# uplink apmld is different
			is_different=1
			break
		fi

		wpa_cli -p /var/run/wpa_supplicant-$tmp_iface set_network 0 bssid $tmp_bssid
	done

	if [ "$is_different" = "1" ]; then
		# disable && config
		for mem in $mlo_members; do
			local tmp_iface=$(uci -q get wireless.bh_sta_$mem.ifname)
			local tmp_bssid=$(echo $mlo_sets|eval "sed -ne 's/.*\($mem@\)\([^,]*\),.*/\2/p'")
			wpa_cli -p /var/run/wpa_supplicant-$tmp_iface disable_network 0
			wpa_cli -p /var/run/wpa_supplicant-$tmp_iface set_network 0 bssid $tmp_bssid
		done

		#enable
		for mem in $mlo_members; do
			local tmp_iface=$(uci -q get wireless.bh_sta_$mem.ifname)
			wpa_cli -p /var/run/wpa_supplicant-$tmp_iface enable_network 0
		done
	fi
}

topomon_set_connect_bssid() {
	local sta_iface=$1
	local restart=$2
	local new_bssid=$(topomon_current_status "best_bssid")
	local cur_bh_band=$(mesh_cmd backhaul get real_band)
	local curr_bh_type=$(topomon_current_status "bh_type")
	local easymesh_support=$(mesh_cmd easymesh_support)

	if [ -n "$sta_iface" -a -n $new_bssid ]; then
		local new_bh_band=
		local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
		local force_slo_backup=$(topomon_current_status "force_slo_backup")
		[ -z "$force_slo_backup" ] && force_slo_backup=0
		if [ "$bh_mlo_support" = "1" -a "$force_slo_backup" != "1" ]; then
			local cur_mlo_members=$(uci -q get wireless.bh_sta_mlo.mlo)
			# apmld format: 2g@bssid_2g,5g@bssid_5g,5gh@bssid_5gh
			if [ "${new_bssid##*@}" != "${new_bssid}" ]; then
				local mlo_members=
				local scan_retry=3
				while [ $scan_retry -gt 0 ]; do
					mlo_members=$(mesh_cmd mlo_members "$new_bssid" "scan" "cfg80211tool")
					if [ -z "$mlo_members" ]; then
						scan_retry=$(( scan_retry - 1 ))
						sleep 3
					else
						break
					fi
				done

				log "topomon_set_connect_bssid: new_bssid=$new_bssid, mlo_members=$mlo_members"

				# best uplink node support mlo, but rssi or other metrics not good
				[ -z "$mlo_members" ] && return

				# best uplink node support mlo, do mlo update
				# check cac is ready?
				if ! topomon_cac_status_multi_check "$mlo_members"; then
					log "Change to $new_bssid later, cac currently!"
					return
				fi

				local bh_band=$(mesh_cmd backhaul get real_band)
				[ "$mlo_members" != "$cur_mlo_members" ] && __bh_band_mld_unset
				__bh_band_mld_setup "$mlo_members"
				for mem in $mlo_members; do
					uci set wireless.bh_sta_${mem}.uplink_changed=1
				done
				uci commit wireless
				/sbin/wifi update

				# check if connected the correct uplink apmld
				mlo_uplink_bssid_check "$new_bssid" "$mlo_members"

				for mem in $mlo_members; do
					uci delete wireless.bh_sta_${mem}.uplink_changed
				done
				uci commit wireless

				return
			elif [ "${new_bssid##*#}" != "${new_bssid}" ]; then
				#format: bssid#band, band include: 2g, 5g, 5gh
				local tmp_bssid=$(echo $new_bssid | awk -F# '{print $1}')
				local tmp_band=$(echo $new_bssid | awk -F# '{print $2}')

				if [ -n "$tmp_bssid" ]; then
					new_bssid=$tmp_bssid
					new_bh_band=$tmp_band
					topomon_update_status "best_bssid" $new_bssid
				fi
			fi

			# check cac is ready?
			if ! topomon_cac_status_multi_check "$new_bh_band"; then
				log "Change to $new_bssid later!"
				return
			fi

			# new bssid is non-mld ap, do __bh_band_mld_unset
			if [ -n "$cur_mlo_members" ] || [ -n "$new_bh_band" ]; then
				__bh_band_mld_unset
				if [ -n "$new_bh_band" ]; then
					uci -q set wireless.bh_sta_${new_bh_band}.disabled="0"
					sta_iface=$(uci -q get misc.backhauls.backhaul_${new_bh_band}_sta_iface)
					mesh_cmd backhaul set real_band $new_bh_band
				else
					uci -q set wireless.bh_sta_${cur_bh_band}.disabled="0"
					sta_iface=$(uci -q get misc.backhauls.backhaul_${cur_bh_band}_sta_iface)
				fi
				uci commit wireless
				/sbin/wifi update
			fi
		fi

		if [ "$bh_mlo_support" = "1" -a "$force_slo_backup" = "1" ]; then
			local slo_backup_band=$(uci -q get misc.mld.slo_backup)
			local tmp_bssid=$(echo $new_bssid | awk -F"$slo_backup_band@" '{print $2}' | cut -d',' -f 1)
			[ -n "$tmp_bssid" ] && new_bssid=$tmp_bssid
		fi

		local current_network_id=
		[ "$easymesh_support" = "1" ] && {
			current_network_id=$(wpa_cli -p /var/run/wpa_supplicant-$sta_iface list_network | grep CURRENT | awk '{print $1}')
		}
		[ -z "$current_network_id" ] && current_network_id=0

		if [ "$restart" -gt 0 ]; then
			# Restart the network with configured BSSID
			log "Bringing down/up $sta_iface due to bssid config & restart!($new_bssid)"
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface disable_network $current_network_id
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface set_network $current_network_id bssid $new_bssid
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface enable_network $current_network_id
		else
			# Just configure the BSSID
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface set_network $current_network_id bssid $new_bssid
		fi
	fi
}

topomon_re_push() {
	# role
	__setkv "whc_role" "$ROLE_RE"

	# self wanmac
	__setkv "re_whc_wanmac" "`getmac wan`"

	# upnode mac
	local upnode=$(topomon_current_status "uplink_mac")
	[ -n "$upnode" -a "$upnode" != "00:00:00:00:00:00" ] && __setkv "re_whc_upnode" "$upnode"

	# RE backhauls
	local bh_bmp=$(topomon_current_status "backhauls")
	local qa_bmp=$(topomon_current_status "backhauls_qa")
	[ -n "$bh_bmp" ] && {
		__setkv "re_whc_backhauls" "$bh_bmp"
		__setkv "re_whc_backhauls_qa" "$qa_bmp"
		[ "$bh_bmp" == "$((1<<BACKHAUL_BMP_eth))" ] && {
			__setkv "wan_port_rate" "$(topomon_current_status 'eth_link_rate')"
		}
	}

	# CAP devid from tbus
	local cap_devid=$(uci -q get bind.info.remoteID)
	[ -n "$cap_devid" ] && __setkv "re_whc_cap_devid" "$cap_devid"

	log " RE push: up $upnode, bh:qa $bh_bmp:$qa_bmp, capdevid $cap_devid"
}

topomon_cap_push() {
	# role
	__setkv "whc_role" "$ROLE_CAP"

	local re_list=""
	[ -e /tmp/xq_whc_quire ] && {
		while read -r LINE
		do
			[ -z "$LINE" ] && continue
			local status=$(parse_json "$LINE" return 2>/dev/null)
			if [ "$status" = "success" ]; then
				local re_devid="`parse_json "$LINE" devid`"
				local re_mac="`parse_json "$LINE" wanmac`"

				local bmp=$(parse_json "$LINE" backhauls)
				[ -z "$bmp" ] && bmp=0
				local locale=$(parse_json "$LINE" locale)
				local initted=$(parse_json "$LINE" initted)
				local ip=$(parse_json "$LINE" ip)

				local re_node="{\"devid\":\"$re_devid\",\"wanmac\":\"$re_mac\",\"backhauls\":\"$bmp\",\"locale\":\"$locale\",\"initted\":\"$initted\",\"ip\":\"$ip\"},"

				log "   re node:$re_node"
				[ "0" = "$initted" ] && {
					log "     re node NOT init-done, ignore push it!"
					continue
				}

				append re_list "$re_node"
			fi

		done < /tmp/xq_whc_quire

		re_list=${re_list%,}
	}
	[ -n "$re_list" ] && __setkv "cap_whc_relist" "[$re_list]" || __setkv "cap_whc_relist" "[]"
}

topomon_link_update() {
	local bh_type="$1"
	local current_qa=$(topomon_current_status "backhauls_qa")
	local now_qa=
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	if [ "$bh_type" = "1" ]; then
		#eth backhaul, link quality is always good
		now_qa="$((1<<BACKHAUL_BMP_eth))"
		topomon_update_status "backhauls" "$((1<<BACKHAUL_BMP_eth))"
	elif [ "$bh_type" = "2" ]; then
		local rssi=0
		local bh_sta_iface=

		local bh_mlo_support=$(mesh_cmd bh_mlo_support)
		local bhsta_mlo=$(uci -q get wireless.bh_sta_mlo.mlo)
		# wireless backhaul connected by mlo
		if [ "$bh_mlo_support" = "1" ] && [ -n "$bhsta_mlo" ]; then
			local best_rssi=
			local backhauls_bmp=0
			for band in $bhsta_mlo; do
				eval "band_bmp=\${BACKHAUL_BMP_$band}"
				backhauls_bmp=$(( backhauls_bmp|(1<<band_bmp) ))
				bh_sta_iface=$(uci -q get misc.backhauls.backhaul_${band}_sta_iface)
				rssi=$(iwconfig $bh_sta_iface | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}')
				if [ -z "$best_rssi" ] \
						|| [ -n "$rssi" -a "$rssi" -gt "$best_rssi" ]; then
					best_rssi=$rssi
				fi
			done
			rssi=$best_rssi
			topomon_update_status "backhauls" "$backhauls_bmp"
		else
			eval "band_bmp=\${BACKHAUL_BMP_$bh_band}"
			topomon_update_status "backhauls" "$((1<<band_bmp))"
			bh_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
			rssi=$(iwconfig $bh_sta_iface | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}')
		fi

		if [ $rssi -ge $RSSI_THRESHOLD_NEAR ]; then
			now_qa="$((1<<BACKHAUL_QA_BMP_GOOD))"
		elif [ $rssi -ge $RSSI_THRESHOLD_FAR ]; then
			now_qa="$((1<<BACKHAUL_QA_BMP_POOR))"
		else
			now_qa="0"
		fi
	fi

	[ "$current_qa" = "$now_qa" ] && return

	topomon_update_status "backhauls_qa" $now_qa
	topomon_re_push
}

topomon_topo_update() {
	local bh_type="$1"
	local port_name="$2"
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local int_ip=0
	local uplink_rate=0
	local hop_count=0
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local backhaul_type=
	local uplink_mac=
	local device_5g=$(uci -q get misc.wireless.if_5G)
	local bh_ap_running=$(ifconfig $bh_wlan_iface | grep -wc "RUNNING")
	local bh_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
	local bh_sta_is_running="1"
	local curr_cap_ip=$(topomon_current_status "cap_ip")
	local easymesh_support=$(mesh_cmd easymesh_support)
	local is_wired_backhual=0
	[ "$(uci -q get wireless.meshbhmode.mode)" = "wired" ] && is_wired_backhual=1

	if [ "$bh_type" = "wired" ]; then
		uplink_mac=$3
		int_ip=$4
		uplink_rate=$5
		hop_count=$6
		topomon_update_status "bh_type" $bh_type
		eth_link_rate=$(phyhelper speed iface "$port_name")
		[ $uplink_rate -gt $eth_link_rate ] && uplink_rate=$eth_link_rate
		topomon_update_status "eth_link_rate" $uplink_rate
		topomon_update_status "hop_count" $hop_count
		cfg80211tool $bh_wlan_iface mesh_ethmode 1
		cfg80211tool $bh_wlan_iface mesh_capip $int_ip
		cfg80211tool $bh_wlan_iface mesh_ulrate $uplink_rate
		cfg80211tool $bh_wlan_iface mesh_hop $hop_count
		backhaul_type=1
		ubus call xq_info_sync_mqtt topo_changed
	elif [ "$bh_type" = "wireless" ]; then
		cfg80211tool $bh_wlan_iface mesh_ethmode 0
		backhaul_type=2
		topomon_update_status "bh_type" $bh_type
		bh_sta_is_running=$(ifconfig $bh_sta_iface | grep -wc "RUNNING")
		if [ $bh_sta_is_running = "1" ]; then
			int_ip=$(cfg80211tool $bh_wlan_iface g_mesh_capip | awk -F":" '{print $2}')
			uplink_rate=$(cfg80211tool $bh_wlan_iface g_mesh_ulrate | awk -F":" '{print $2}')
			hop_count=$(cfg80211tool $bh_wlan_iface g_mesh_hop | awk -F":" '{print $2}')
			uplink_mac=$(cfg80211tool $bh_wlan_iface g_mesh_ulmac | cut -f2-7 -d":")
			topomon_update_status "eth_link_rate" $uplink_rate
			topomon_update_status "hop_count" $hop_count
			ubus call xq_info_sync_mqtt topo_changed
		else
			#set hop 255 before connected to uplink node
			hop_count=255
			topomon_update_status "hop_count" $hop_count
			wpa_cli -p /var/run/wpa_supplicant-$bh_sta_iface set_network 0 bssid any
		fi
	else
		hop_count=255
		topomon_update_status "bh_type" $bh_type
		cfg80211tool $bh_wlan_iface mesh_hop $hop_count
		topomon_update_status "hop_count" $hop_count
		uplink_mac=$(topomon_current_status "uplink_mac")
		[ -z $uplink_mac ] && uplink_mac=0
		local curr_bh_type=$(topomon_current_status "bh_type")
		[ "$curr_bh_type" = "wireless" ] && backhaul_type=2 || backhaul_type=1
		local curr_cap_ip=$(topomon_current_status "cap_ip")
		int_ip=$(ip2int $curr_cap_ip)
		if [ "$is_wired_backhual" = "1" ]; then
			bh_sta_is_running=0
		else
			wpa_cli -p /var/run/wpa_supplicant-$bh_sta_iface set_network 0 bssid any
		fi
	fi

	[ "$easymesh_support" = "1" ] && bhtype_2_xquci ${bh_type}
	set_backhaul_ap_aplimit $bh_wlan_iface $hop_count

	local mac_bin=$(echo $uplink_mac | sed s'/://'g)
	local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x$mac_bin)
	echo "$lan_mac $info" > /proc/enid/response_info

	if [ $bh_sta_is_running = "1" ]; then
		local str_ip=$(int2ip $int_ip)
		topomon_update_status "uplink_mac" $uplink_mac
		topomon_update_status "cap_ip" $str_ip
		uci -q set xiaoqiang.common.CAP_IP=$str_ip
		uci commit xiaoqiang
		topomon_update_status "port_name" $port_name

		if [ "$bh_type" != "isolated" ]; then
			topomon_link_update $backhaul_type
			topomon_re_push
			local current_uplink_mac=$(topomon_current_status "uplink_mac")
			[ "$current_uplink_mac" != "$uplink_mac" ] && ubus call xq_info_sync_mqtt topo_changed
		fi
	fi

	local new_cap_ip=$(int2ip $int_ip)
	if [ "$curr_cap_ip" != "$new_cap_ip" ]; then
		log " CAPIP changed $curr_cap_ip -> $new_cap_ip, redhcpc"
		trigger_dhcp_new_ip
	fi
}

__is_mlo_bhlink() {
	local bh_sta_mlo="$(uci -q get wireless.bh_sta_mlo.mlo)"

	[ -z "$bh_sta_mlo" ] && return 1
	for band in $bh_sta_mlo; do
		local wf_sec="bh_sta_$band"
		local disabled="$(uci -q get wireless.$wf_sec.disabled)"
		local mld="$(uci -q get wireless.$wf_sec.mld)"

		if [ "$disabled" = "1" ] || [ -z "$mld" ]; then
			# not mlo bhlink
			return 1
		fi
	done
	return 0
}

topomon_check_best_bssid() {
	local sta_iface=$1
	local bh_mlo_supp=$(mesh_cmd bh_mlo_support)
	local curr_bh_type=$(topomon_current_status "bh_type")
	local force_slo_backup=$(topomon_current_status "force_slo_backup")
	[ -z "$force_slo_backup" ] && force_slo_backup=0

	# current bh_sta support mlo
	if [ "$bh_mlo_supp" = "1" -a "$force_slo_backup" != "1" ]; then
		local bh_band=$(mesh_cmd backhaul get real_band)
		local bh_ssid="$(uci -q get wireless.bh_ap_${bh_band}.ssid)"
		local cur_bhsta_mlo="$(uci -q get wireless.bh_sta_mlo.mlo)"
		local current_bh_apmld="$(cfg80211tool $sta_iface g_mesh_mld | sed -ne 's/.*g_mesh_mld:\(.*\),.*$/\1/p')"
		local mesh_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
		local bhap_iface=$(uci -q get wireless.bh_ap_${bh_band}.ifname)
		local best_bh_apmld="$(cfg80211tool $bhap_iface g_mesh_mld 0x$mesh_id | sed -ne 's/.*g_mesh_mld:\(.*\),.*$/\1/p')"
		local force_to_slo=0

		if ! topomon_cac_status_multi_check "$cur_bhsta_mlo"; then
			log "Topomon check best bssid later!"
			return 0
		fi

		local new_bhsta_mlo=
		if [ "$curr_bh_type" != "isolated" ]; then
			new_bhsta_mlo=$(mesh_cmd mlo_members "$best_bh_apmld" no_scan "cfg80211tool")
		else
			new_bhsta_mlo=$(mesh_cmd mlo_members "$best_bh_apmld" scan "cfg80211tool")
		fi

		if [ -n "$new_bhsta_mlo" ] && __is_mlo_bhlink; then

			if [ -z "$current_bh_apmld" ]; then
				if [ "$curr_bh_type" != "isolated" ]; then
					log "Current AP MLD is NULL"
					return 1
				fi
				current_bh_apmld="$(topomon_current_status "best_bssid")"
			fi

			if [ "$best_bh_apmld" = "$current_bh_apmld" ]; then
				# best uplink mld not changed, to check mlo config
				if [ "$new_bhsta_mlo" != "$cur_bhsta_mlo" ]; then
					log "MLO config changed[$cur_bhsta_mlo --> $new_bhsta_mlo]"
					return 1
				fi

				# current bh_type isn't isolated, and mlo config not changed
				if [ "$curr_bh_type" != "isolated" ]; then
					# revert MLO ---> SLO, while rssi is poor
					# check mlo affiliated link's metric, currently only rssi
					#local check_result=$(mesh_cmd mlo_bhlink_check "$cur_bhsta_mlo")
					#[ "$check_result" = "0" ] && return 0 # good link
					#[ "$check_result" = "2" ] && return 0 # check_failed, retry next time
					#[ "$check_result" = "1" ] && new_bhsta_mlo=""
					return 0
				fi

				# current bh_type is isolated, and best_bh_apmld equal to current_bh_apmld
				new_bhsta_mlo=""

				# force change from mlo to slo
				force_to_slo=1
				topomon_update_status "force_slo_backup" "1"
			fi
		fi

		# uplink mld changed
		if [ -n "$new_bhsta_mlo" ]; then
			topomon_update_status "best_bssid" $best_bh_apmld
			log "best uplink apmld changed to $best_bh_apmld"
			return 1
		fi

		local new_uplink_bssid=$(cfg80211tool $sta_iface g_mesh_bssid all_band | awk -F":" '{print $2}')
		local best_bssid=$(echo "$new_uplink_bssid" | sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4:\5:\6/")
		[ "$best_bssid" = "00:00:00:00:00:00" ] && {
			return 0
		}

		topomon_update_status "best_bssid" $new_uplink_bssid
		iwconfig $sta_iface 2>/dev/null | grep -q -i $best_bssid

		if [ $? = 1 ] || [ "$force_to_slo" = "1" ]; then
			log "best bssid is different : $best_bssid, change from mlo2slo=$force_to_slo"
			return 1
		else
			return 0
		fi
	else
		local best_bssid=$(cfg80211tool $sta_iface g_mesh_bssid | awk -F":" '{print $2}' | sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/")
		[ "$best_bssid" = "00:00:00:00:00:00" ] && {
			return 0
		}

		topomon_update_status "best_bssid" $best_bssid
		iwconfig $sta_iface 2>/dev/null | grep -q -i $best_bssid

		if [ $? = 1 ]; then
			log "best bssid is different : $best_bssid"
			return 1
		else
			return 0
		fi
	fi
}

topomon_init() {
	local bh_type="$1"
	local port_name="$2"
	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	local int_ip=0
	local uplink_rate=0
	local hop_count=0
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local backhaul_type=
	local uplink_mac=
	local bh_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
	local easymesh_support=$(mesh_cmd easymesh_support)

	[ -d $TOPOMON_STATUS_DIR ] || mkdir -p $TOPOMON_STATUS_DIR
	if [ "$bh_type" = "wired" ]; then
		uplink_mac=$3
		int_ip=$4
		uplink_rate=$5
		hop_count=$6
		eth_link_rate=$(phyhelper speed iface "$port_name")
		[ $uplink_rate -gt $eth_link_rate ] && uplink_rate=$eth_link_rate

		cfg80211tool $bh_wlan_iface mesh_ethmode 1
		cfg80211tool $bh_wlan_iface mesh_capip $int_ip
		cfg80211tool $bh_wlan_iface mesh_ulrate $uplink_rate
		cfg80211tool $bh_wlan_iface mesh_hop $hop_count
		backhaul_type=1

		topomon_wifi_if_down $bh_sta_iface
	elif [ "$bh_type" == "wireless" ]; then
		local wifi_iface=$(uci show wireless | grep ".ifname=\'$bh_sta_iface\'" | awk -F"." '{print $2}')
		local sta_disabled=$(uci -q get wireless.$wifi_iface.disabled)
		cfg80211tool $bh_wlan_iface mesh_ethmode 0
		backhaul_type=2
		if [ $sta_disabled = "1" ]; then
			uci set wireless.$wifi_iface.disabled=0
			uci commit wireless
			wifi update
		fi
		wpa_cli -i $bh_sta_iface -p /var/run/wpa_supplicant-$bh_sta_iface enable 0
		sleep 2
		local bh_sta_is_running=$(ifconfig $bh_sta_iface | grep -wc "RUNNING")
		if [ $bh_sta_is_running = "1" ]; then
			int_ip=$(cfg80211tool $bh_wlan_iface g_mesh_capip | awk -F":" '{print $2}')
			uplink_rate=$(cfg80211tool $bh_wlan_iface g_mesh_ulrate | awk -F":" '{print $2}')
			hop_count=$(cfg80211tool $bh_wlan_iface g_mesh_hop | awk -F":" '{print $2}')
			uplink_mac=$(cfg80211tool $bh_wlan_iface g_mesh_ulmac | cut -f2-7 -d":")
		else
			local str_ip=$(uci -q get xiaoqiang.common.CAP_IP)
			[ -n "$str_ip" ] && int_ip=$(ip2int $str_ip)
			uplink_rate=0
			hop_count=255
			uplink_mac=0
		fi
	elif [ "$bh_type" == "isolated" ]; then
		local str_ip=$(uci -q get xiaoqiang.common.CAP_IP)
		[ -n "$str_ip" ] && int_ip=$(ip2int $str_ip)
		uplink_rate=0
		hop_count=255
		uplink_mac=0
	fi

	if [ $int_ip != "0" ]; then
		local str_ip=$(int2ip $int_ip)
		[ "$str_ip" != "0.0.0.0" ] && {
			topomon_update_status "cap_ip" $str_ip
			uci -q set xiaoqiang.common.CAP_IP=$str_ip
			uci commit xiaoqiang
		}
	fi

	topomon_update_status "uplink_mac" $uplink_mac
	topomon_update_status "bh_type" $bh_type
	topomon_update_status "hop_count" $hop_count
	topomon_update_status "eth_link_rate" $uplink_rate
	[ $port_name != "null" ] && topomon_update_status "port_name" $port_name
	topomon_link_update $backhaul_type

	[ "$easymesh_support" = "1" ] && bhtype_2_xquci ${bh_type}
	set_backhaul_ap_aplimit $bh_wlan_iface $hop_count

	local mac_bin=$(echo $uplink_mac | sed s'/://'g)
	local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x$mac_bin)
	echo "$lan_mac $info" > /proc/enid/response_info

	[ $hop_count != "255" ] && topomon_re_push
}

topomon_update_cap_wifi_param() {
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	local wait=$1

	[ -z "$wait" ] && wait=1

	if [ $wait -eq 1 ]; then
		for i in {1..15}
		do
			ifconfig $bh_wlan_iface > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				break
			else
				sleep 2
			fi
		done
	fi

	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	#local str_ip=$(ifconfig br-lan | grep "inet\ addr" | awk '{print $2}' | awk -F: '{print $2}')
	local str_ip=$(uci -q get network.lan.ipaddr)
	local int_ip=$(ip2int $str_ip)
	local uplink_rate=9999
	local hop_count=0
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local backhaul_type=0

	local device=$(uci -q get misc.wireless.if_5G)

	cfg80211tool $bh_wlan_iface mesh_capip $int_ip
	cfg80211tool $bh_wlan_iface mesh_hop 0

	local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x0)
	echo "$lan_mac $info" > /proc/enid/response_info

	echo "update cap mesh param done" >> /dev/console
	topomon_cap_push
}

topomon_ping_test() {
	local ip=$1
	ping $1 -c 1 -w 2 > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "success"
	else
		echo "failed"
	fi
}

topomon_enid_init() {
	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	echo "$lan_mac 0000000000000000000000000000000000000000" > /proc/enid/response_info
	echo "re enid init done" >> /dev/console
}

topomon_enid_update() {
	local uplink_mac=$1
	local int_ip=$2
	local uplink_rate=$3
	local hop_count=$4
	local port_name=$5
	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local backhaul_type=1
	local str_ip=$(int2ip $int_ip)
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	local current_ip=$(topomon_current_status "cap_ip")
	local bh_ap_running=$(ifconfig $bh_wlan_iface | grep -wc "RUNNING")
	local easymesh_support=$(mesh_cmd easymesh_support)

	[ "$str_ip" = "$current_ip" ] || {
		topomon_update_status "cap_ip" $str_ip
		uci -q set xiaoqiang.common.CAP_IP=$str_ip
		uci commit xiaoqiang
	}

	eth_link_rate=$(phyhelper speed iface "$port_name")
	[ $uplink_rate -gt $eth_link_rate ] && uplink_rate=$eth_link_rate
	topomon_update_status "bh_type" "wired"
	topomon_update_status "uplink_mac" $uplink_mac
	topomon_update_status "eth_link_rate" $uplink_rate
	topomon_update_status "hop_count" $hop_count
	topomon_update_status "port_name" $port_name

	cfg80211tool $bh_wlan_iface mesh_capip $int_ip
	cfg80211tool $bh_wlan_iface mesh_ulrate $uplink_rate
	cfg80211tool $bh_wlan_iface mesh_hop $hop_count

	[ "$easymesh_support" = "1" ] && bhtype_2_xquci "wired"
	set_backhaul_ap_aplimit $bh_wlan_iface $hop_count

	local mac_bin=$(echo $uplink_mac | sed s'/://'g)
	local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x$mac_bin)
	echo "$lan_mac $info" > /proc/enid/response_info
	ubus call xq_info_sync_mqtt topo_changed
}

topomon_wireless_update() {
	local status_changed=0
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	local int_ip=$(cfg80211tool $bh_wlan_iface g_mesh_capip | awk -F":" '{print $2}')
	local str_ip=$(int2ip $int_ip)
	local current_ip=$(topomon_current_status "cap_ip")
	local hop_changed=0
	local uplink_changed=0
	[ "$str_ip" = "$current_ip" ] || {
		status_changed=1
		topomon_update_status "cap_ip" $str_ip
		uci -q set xiaoqiang.common.CAP_IP=$str_ip
		uci commit xiaoqiang
	}

	local uplink_rate=$(cfg80211tool $bh_wlan_iface g_mesh_ulrate | awk -F":" '{print $2}')
	local current_uprate=$(topomon_current_status "eth_link_rate")
	[ "$uplink_rate" = "$current_uprate" ] || {
		status_changed=1
		topomon_update_status "eth_link_rate" $uplink_rate
	}

	local hop_count=$(cfg80211tool $bh_wlan_iface g_mesh_hop | awk -F":" '{print $2}')
	local current_hop=$(topomon_current_status "hop_count")
	[ "$hop_count" = "$current_hop" ] || {
		status_changed=1
		hop_changed=1
		topomon_update_status "hop_count" $hop_count
		set_backhaul_ap_aplimit $bh_wlan_iface $hop_count
	}

	local current_uplink_mac=$(topomon_current_status "uplink_mac")
	local uplink_mac=$(cfg80211tool $bh_wlan_iface g_mesh_ulmac | cut -f2-7 -d":")
	[ -n "$uplink_mac" -a "$current_uplink_mac" != "$uplink_mac" ] && {
		status_changed=1
		uplink_changed=1
		topomon_update_status "uplink_mac" $uplink_mac
	}

	[ $status_changed -eq 1 ] && {
		local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
		local backhaul_type=2
		local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
		local mac_bin=$(echo $uplink_mac | sed s'/://'g)
		local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x$mac_bin)
		echo "$lan_mac $info" > /proc/enid/response_info
		[ $hop_changed -eq 1 -o $uplink_changed -eq 1 ] && ubus call xq_info_sync_mqtt topo_changed
	}
}

topomon_push() {
	local role="$1"
	local easymesh_support=$(mesh_cmd easymesh_support)

	if [ "$easymesh_support" = "1" ]; then
		if [ "$role" = "agent" -o "$role" = "re" ]; then
			topomon_re_push
		elif [ "$role" = "controller" -o "$role" = "cap" ]; then
			topomon_cap_push
		else
			log "Push error : easymesh unknown role $role"
		fi
	else
		# mimesh
		if [ "$role" = "RE" -o "$role" = "re" ]; then
			topomon_re_push
		elif [ "$role" = "CAP" -o "$role" = "cap" ]; then
			topomon_cap_push
		else
			log "Push error : unknown role $role"
		fi
	fi
}

topomon_cac_status_check() {
	local ifname=$1
	local status=$(cfg80211tool $ifname get_cac_state | grep -w $ifname | awk -F: '{print $2}')
	if [ "$status" = "1" ]; then
		return 1
	else
		return 0
	fi
}

topomon_cac_status_multi_check() {
	local band_list="$1"

	for band in $band_list; do
		local band_iface=$(uci -q misc.backhauls.backhaul_${band}_ap_iface)
		topomon_cac_status_check $band_iface
		if [ "$?" = "1" ]; then
			log "$band_iface is doing cac currently!"
			return 1
		fi
	done
	return 0
}

topomon_update_re_wifi_param() {
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	local backhaul_5g_ap_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	local bh_type=$(topomon_current_status "bh_type")

	[ -z $bh_type ] && return

	if [ "$bh_type" = "wired" ]; then
		cfg80211tool $backhaul_5g_ap_iface mesh_ethmode 1
		local str_ip=$(topomon_current_status "cap_ip")
		local hop_count=$(topomon_current_status "hop_count")
		local ulrate=$(topomon_current_status "eth_link_rate")
		[ -n $str_ip ] && {
			local bin_ip=$(ip2int $str_ip)
			cfg80211tool $backhaul_5g_ap_iface mesh_capip $bin_ip
		}
		[ -n $hop_count ] && cfg80211tool $backhaul_5g_ap_iface mesh_hop $hop_count
		[ -n $ulrate ] && cfg80211tool $backhaul_5g_ap_iface mesh_ulrate $ulrate
	else
		cfg80211tool $backhaul_5g_ap_iface mesh_ethmode 0
	fi
	echo "update re mesh param done" >> /dev/console
}

topomon_update_mesh_param() {
	local netmod=$(uci -q get xiaoqiang.common.NETMODE)
	local capmod=$(uci -q get xiaoqiang.common.CAP_MODE)
	if [ "whc_cap" = "$netmod" -o "lanapmode" = "$netmod" -a "ap" = "$capmod" ]; then
		topomon_update_cap_wifi_param 0
	elif [ "whc_re" = "$netmod" ]; then
		topomon_update_re_wifi_param
	fi
}

#trigger to get new DHCP-IP dynamically
#generally called when ping failed.
trigger_dhcp_new_ip(){
	iface="br-lan"
	pid_file="/var/run/udhcpc-${iface}.pid"
	if [ -f "$pid_file" ]; then
		#trigger udhcpc to renew/rebound DHCP-IP
		cat $pid_file |xargs kill -SIGUSR1
	else
		log "WARN: udhcpc pid file not exist, udhcpc not running?!"
	fi
}

set_ezmesh_wifi_config() {
	local role=$(uci -q get xiaoqiang.common.EASYMESH_ROLE)
	local bh_5g_sta_iface=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
	local bh_5g_ap_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local device_5g=$(uci -q get misc.wireless.if_5G)
	local mesh_apmac=$(getmac lan)

	if [ "${role}" = "agent" ]; then
		cfg80211tool ${bh_5g_sta_iface} wds 1
		cfg80211tool ${bh_5g_sta_iface} mesh_ver 2
	fi

	cfg80211tool ${bh_5g_ap_iface} wds 1
	cfg80211tool ${bh_5g_ap_iface} mesh_ver 2
	cfg80211tool ${bh_5g_ap_iface} mesh_apmac ${mesh_apmac}
	cfg80211tool ${bh_5g_ap_iface} mesh_id "0x${network_id}"
	hostapd_cli -i ${bh_5g_ap_iface} -p /var/run/hostapd-${device_5g} -P /var/run/hostapd_cli-${bh_5g_ap_iface}.pid update_beacon
}

get_ezmesh_link_status() {
    #区分xiaomi mesh和easymesh以及区分是否和第三方设备组网
    local controller_feature=$(uci -q get xiaoqiang.common.CONTROLLER_FEATURE)
    #wan_port=$(uci -q get port_service.wan.ports)
    wan_port=4
    #判断WAN口是否连接有线
    local wan_link_status=$(phyhelper link | grep "port:$wan_port" | awk -F ' ' '{print $2}')
    #版本不支持CONTROLLER_FEATURE的情况：区分是否和第三方设备组网
    local vendor_info=$(uci -q get xiaoqiang.common.vendorinfo | grep miwifi)

    #表示和第三方设备组网:就不需要靠enid机制来识别环路
    #比如和中兴网关组网此时controller_feature=ZTE vendor_info是NULL
    #和小米mesh组网controller_feature不存在
    #和小米easymesh组网，controller_feature=xiaomi
    #和小米easymesh老版本组网：controller_feature=none，多判断了vendor_info加以保证，如何是小米设备自己组网vendor_info会包含miwifi字段
    if [ -n "$controller_feature" -a "$controller_feature" != "xiaomi" ]; then
        #mesh有线组网
        if [ "$wan_link_status" == "link:up" ]; then
            echo "eth_up"
        else
            local bh_sta=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
            local islink=$(iwinfo $bh_sta assoclist | grep stacount | cut -d ":" -f 2)
            if [ $islink -eq 1 ]; then
                echo "wifi_up"
            else
                echo "wifi_eth_down"
            fi
        fi
    fi
}

#trigger to notify topo_monitor wireless backhaul is connected
notify_wifi_bh_linked(){
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	local bh_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
	hop_count=$(cfg80211tool $bh_sta_iface g_mesh_hop | awk -F":" '{print $2}')
	if [ $hop_count != "255" ]; then
		local ulmac=$(cfg80211tool $bh_sta_iface g_mesh_ulmac | cut -f2-7 -d":")
		ubus call topomon wifi_up "{ \"ulmac\" : \"$ulmac\" }"
	fi
}

#get wireless backhaul hop
get_wifi_hop(){
	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"
	local bh_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
	[ -z "$bh_sta_iface" ] && bh_sta_iface=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)

	local wifi_connect=$(iwconfig $bh_sta_iface | sed -ne 's/.*Access Point:.*\(Not-Associated\).*$/\1/p')
	if [ -n "$wifi_connect" ]; then
		mesh_hop=255
	else
		mesh_hop=$(cfg80211tool $bh_sta_iface g_mesh_hop | awk -F":" '{print $2}')
	fi
	[ -n "$mesh_hop" -a "$mesh_hop" != "255" ] && echo "$mesh_hop" && return

	if __is_mlo_bhlink; then
		local main_band=$(mesh_cmd backhaul get band)
		local main_bhiface=$(uci -q get misc.backhauls.backhaul_${main_band}_sta_iface)
		local main_wifi_connect=$(iwconfig $bh_sta_iface | sed -ne 's/.*Access Point:.*\(Not-Associated\).*$/\1/p')
		if [ -n "$main_wifi_connect" ]; then
			mesh_hop=255
		else
			mesh_hop=$(cfg80211tool $main_bhiface g_mesh_hop | awk -F":" '{print $2}')
		fi
	fi
	echo "$mesh_hop"
}

#get wireless backhaul uplink rssi
get_bh_rssi(){
	local bh_type=$(topomon_current_status "bh_type")
	[ "$bh_type" != "wireless" ] && return

	local bh_band=$(mesh_cmd backhaul get real_band)
	[ -z "$bh_band" ] && bh_band="5g"

	local best_rssi=
	local bh_mlo_support=$(mesh_cmd bh_mlo_support)
	local bhsta_mlo=$(uci -q get wireless.bh_sta_mlo.mlo)
	if [ "$bh_mlo_support" = "1" ] && [ -n "$bhsta_mlo" ]; then
		# wireless backhaul connected by mlo
		for band in $bhsta_mlo; do
			local bh_sta_iface=$(uci -q get misc.backhauls.backhaul_${band}_sta_iface)
			local rssi=$(iwconfig $bh_sta_iface 2>>/dev/null | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}')
			if [ -z "$best_rssi" ] \
					|| [ -n "$rssi" -a "$rssi" -gt "$best_rssi" ]; then
				best_rssi=$rssi
			fi
		done
	else
		bh_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
		best_rssi=$(iwconfig $bh_sta_iface 2>>/dev/null | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}')
	fi
	echo "$best_rssi"
}

#disable all affiliated stas
__bh_band_mld_unset(){
	local band_list=$(uci -q get misc.mld.sta_mlo)
	local bh_band=$(mesh_cmd backhaul get real_band)

	[ -z "$band_list" ] && band_list="$bh_band"
	for band in $band_list; do
		local sec_name="bh_sta_$band"
		uci -q set wireless.$sec_name.disabled='1'
		uci -q set wireless.$sec_name.mld=""
	done
	uci -q set wireless.bh_sta_mlo=""
	uci commit wireless
}

__bh_band_mld_setup(){
	local new_mlo="$1"

	[ -z "$new_mlo" ] && return

	local lanmac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local mesh_version=$(mesh_cmd max_mesh_version)
	local mld_dev=$(uci -q get misc.mld.bh_sta)
	local cur_bh_band=$(mesh_cmd backhaul get real_band)

	local new_bh_band=
	local tmp_new_mlo=" $new_mlo "
	if [ "${tmp_new_mlo##* $cur_bh_band }" = "${tmp_new_mlo}" ]; then
		if [ "${tmp_new_mlo##* 5gh }" != "${tmp_new_mlo}" ]; then
			new_bh_band="5gh"
		elif [ "${tmp_new_mlo##* 5g }" != "${tmp_new_mlo}" ]; then
			new_bh_band="5g"
		elif [ "${tmp_new_mlo##* 2g }" != "${tmp_new_mlo}" ]; then
			new_bh_band="2g"
		fi
		[ -n "$new_bh_band" ] && mesh_cmd backhaul set real_band $new_bh_band
	fi

	# setup new mlo configs
	for radio in $new_mlo; do
		local sec_name="bh_sta_$radio"
		uci -q set wireless.$sec_name.disabled="0"
		uci -q set wireless.$sec_name.mld="$mld_dev"
	done
	if [ -z "$(uci -q show wireless.$mld_dev)" ]; then
		local bh_ssid="$(uci -q get wireless.bh_sta_${cur_bh_band}.ssid)"
		uci -q batch <<-EOF >/dev/null
			set wireless.$mld_dev=wifi-mld
			set wireless.$mld_dev.mld_macaddr="$(mld_macaddr bh_sta)"
			set wireless.$mld_dev.mld_ssid="$bh_ssid"
		EOF
	fi
	uci -q set wireless.bh_sta_mlo=wifi-mlo
	uci -q set wireless.bh_sta_mlo.mlo="$new_mlo"
	uci commit wireless
}

__bh_band_update() {
	local bh_band="$1"
	local bh_mlo_supp=$(mesh_cmd bh_mlo_support)

	local cur_bh_band=$(mesh_cmd backhaul get real_band)
	log "__bh_band_update: target band $bh_band"

	mesh_cmd backhaul set real_band "$bh_band" >>/dev/null
	if [ "$bh_mlo_supp" = "1" ]; then
		__bh_band_mld_unset
		uci -q set wireless.bh_sta_${cur_bh_band}.disabled="1"
		uci -q set wireless.bh_sta_${bh_band}.disabled="0"
	else
		local bh_band_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
		local bh_band_device=$(uci -q get misc.wireless.if_${bh_band_upcase})
		local bh_band_ap_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
		uci -q set wireless.bh_ap.device="$bh_band_device"
		uci -q set wireless.bh_ap.ifname="$bh_band_ap_iface"
		uci -q set wireless.bh_sta.device="$bh_band_device"
		uci -q set wireless.bh_sta.ifname="$bh_band_sta_iface"
		uci -q set wireless.bh_sta.disabled="0"
	fi
	uci commit wireless

	wifi update
}

#update backhaul band 5g<-->5gh
bh_band_update(){
	local bh_band=$1
	local force=$2

	[ -z "$bh_band" ] && return

	local bh_band_upcase=$(echo $bh_band | tr '[a-z]' '[A-Z]')
	if [ "$force" != "1" ]; then
		local scan_dev="$(uci -q get misc.wireless.if_${bh_band_upcase})"
		local scan_iface="$(uci -q get misc.wireless.ifname_${bh_band_upcase})"
		local meshid="$(uci -q get xiaoqiang.common.NETWORK_ID)"

		ifconfig $scan_iface > /dev/null 2>&1
		[ "$?" != "0" ] && return

		# check if bh_ap ssid exists in another channel
		local scan_result=$(meshd -s -i "$scan_iface" -e "$meshid" 2>>/dev/null)
		if [ -z "$scan_result" ]; then
			log "bh_ap with same meshid doesn't exist on $bh_band, bh_band_update failed!"
			echo "failed"
			return
		fi
	fi

	(trap "lock -u $XQWHC_WIFI_LOCK; exit 1" INT TERM ABRT QUIT ALRM HUP;
		lock $XQWHC_WIFI_LOCK;
		__bh_band_update "$bh_band" >>/dev/null;
		lock -u $XQWHC_WIFI_LOCK)

	log "bh_band_update to $bh_band succeed!"
	echo "success"
}

# 0 - link down; 1 - link up
bhsta_link_check() {
	local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
	local bh_sta_mlo="$(uci -q get wireless.bh_sta_mlo.mlo)"
	local real_bh_band=$(mesh_cmd backhaul get real_band)

	if [ "$bh_mlo_support" = "1" ] && [ -n "$bh_sta_mlo" ]; then
		for mlo in ${bh_sta_mlo}; do
			local ifname=$(uci -q get wireless.bh_sta_${mlo}.ifname)
			local network_id=`wpa_cli -p /var/run/wpa_supplicant-$ifname list_network | grep CURRENT | awk '{print $1}'`
			if [ -n $network_id ]; then
				return 1
			fi
		done

		return 0
	fi

	local real_ifname=$(uci -q get misc.backhauls.backhaul_${real_bh_band}_sta_iface)
	local real_network_id=`wpa_cli -p /var/run/wpa_supplicant-$real_ifname list_network | grep CURRENT | awk '{print $1}'`
	if [ -n $real_network_id ]; then
		return 1
	fi
	return 0
}

topomon_wifi_bhsta_modify() {
	local bhsta_ifname="$1"
	local bh_band="$(mesh_cmd backhaul get band)"
	local bh_mlo_support=$(mesh_cmd bh_mlo_support)

	local bh_radios=""
	local bhsta_disabled=1
	[ "$bh_mlo_support" = "1" ] && bh_radios="$(uci -q get misc.mld.sta_mlo)"
	[ -z "$bh_radios" ] && bh_radios="$bh_band"
	for radio in $bh_radios; do
		local disabled="$(uci -q get wireless.bh_sta_$radio.disabled)"
		[ -z "$disabled" ] && disabled=$(uci -q get wireless.bh_sta.disabled)
		[ "$disabled" != "1" ] && bhsta_disabled=0
	done

	if [ "$bhsta_disabled" = "1" ]; then
		if ! topomon_check_best_bssid $bhsta_ifname; then
			topomon_set_connect_bssid $bhsta_ifname 1
		fi
	else
		topomon_wifi_if_up $bhsta_ifname
	fi
	return 1
}

# Only MLD RE need to do update
# while backhaul changed from wired to wireless.
topomon_wifi_bhcfg_update(){
	local bh_mlo_support=$(mesh_cmd bh_mlo_support)
	[ "$bh_mlo_support" != "1" ] && return 0

	local bh_band="$(mesh_cmd backhaul get band)"
	local bh_radio="$(uci -q get misc.wireless.if_$(echo $bh_band|tr '[a-z]' '[A-Z]'))"
	local bh_apiface="$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)"
	local ax="$(uci -q get wireless.${bh_radio}.ax)"
	local bh_type=$(topomon_current_status "bh_type")

	# 11ac mode, unset bh mlo config while current mlo is not null
	if [ "$ax" = "0" ]; then
		__bh_band_mld_unset
		if [ -z "$bh_type" ] || [ "$bh_type" = "wireless" ]; then
			local bh_band_sec="bh_sta_${bh_band}"
			uci -q set wireless.${bh_band_sec}.disabled=0
			uci commit wireless
			return 1
		fi
	fi

	# 11be mode, do nothing while current mlo is null
	#if [ "$ax" = "1" -a -z "$mlo" ]; then
	#fi
	return 0
}

check_sta_mlo_links() {
	local bh_mlo_support=$(mesh_cmd bh_mlo_support)
	[ "$bh_mlo_support" != "1" ] && return 0

	local sta_mlo=$(uci -q get wireless.bh_sta_mlo.mlo)
	[ -z "$sta_mlo" ] && return 0

	local slo_backup_band=$(uci -q get misc.mld.slo_backup)

	if [ -n "$slo_backup_band" ]; then
		local slo_backup_iface=$(uci -q get misc.backhauls.backhaul_${slo_backup_band}_sta_iface)
		local max_failed_times=$(uci -q get misc.mld.mlo_failed_max_times)
		[ -z "$max_failed_times" ] && max_failed_times=6
		local failed_times=$(wpa_cli -g /var/run/wpa_supplicantglobal ifname=$slo_backup_iface status | grep "mlo_partner_failed_times=" | awk -F'=' '{print $2}')
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
			uci commit wireless

			topomon_update_status "force_slo_backup" "1"

			log "MLO: -------------> change to slo backup $slo_backup_band"

			wifi update
		fi
	fi
	return 0
}

topomon_wifi_bhsta_isolate() {
	local bhsta_ifname="$1"
	local isolate_mode="$2"
	local isolate_file=""

	[ -z "$isolate_mode" ] && return

	local bhsta_ifname_list=
	local mlo_sets=$(uci -q get wireless.bh_sta_mlo.mlo)
	if [ -n "$mlo_sets" ]; then
		for band in $mlo_sets; do
			local tmp_ifname="$(uci -q get misc.backhauls.backhaul_${band}_sta_iface)"
			if [ -z "$bhsta_ifname_list" ]; then
				bhsta_ifname_list="$tmp_ifname"
			else
				bhsta_ifname_list="$bhsta_ifname_list $tmp_ifname"
			fi
		done
	else
		bhsta_ifname_list="$bhsta_ifname"
	fi

	for ifname in $bhsta_ifname_list; do
		if [ -e /sys/class/net/$bhsta_ifname/brport/isolated ]; then
			isolate_file="/sys/class/net/$bhsta_ifname/brport/isolated"
		else
			isolate_file="/sys/class/net/$bhsta_ifname/brport/isolate_mode"
		fi

		local cur_mode=$(cat $isolate_file 2>>/dev/null)
		if [ "$cur_mode" != "$isolate_mode" ]; then
			echo "$isolate_mode" > $isolate_file 2>>/dev/null
			log "set $bhsta_ifname isolate_mode: $isolate_mode"
		fi
	done

	return 1
}

case "$1" in
	init)
	topomon_init "$2" "$3" "$4" "$5" "$6" "$7"
	;;
	ping_test)
	topomon_ping_test "$2"
	;;
	wifi_if_up)
	topomon_wifi_if_up "$2"
	;;
	wifi_if_down)
	topomon_wifi_if_down "$2"
	;;
	set_connect_bssid)
	topomon_set_connect_bssid "$2" "$3"
	;;
	check_best_bssid)
	topomon_check_best_bssid "$2"
	;;
	topo_update)
	topomon_topo_update "$2" "$3" "$4" "$5" "$6" "$7"
	;;
	update_status)
	topomon_update_status "$2" "$3"
	;;
	current_status)
	topomon_current_status "$2"
	;;
	cap_init)
	topomon_update_cap_wifi_param "$2"
	;;
	enid_init)
	topomon_enid_init
	;;
	enid_update)
	topomon_enid_update "$2" "$3" "$4" "$5" "$6"
	;;
	link_update)
	topomon_link_update "$2"
	;;
	wireless_update)
	topomon_wireless_update
	;;
	push)
	topomon_push "$2"
	;;
	cac_status_check)
	topomon_cac_status_check "$2"
	;;
	update_mesh_param)
	topomon_update_mesh_param
	;;
	trigger_dhcp_new_ip)
	trigger_dhcp_new_ip
	;;
	notify_wifi_bh_linked)
	notify_wifi_bh_linked
	;;
	get_wifi_hop)
	get_wifi_hop
	;;
	get_bh_rssi)
	get_bh_rssi
	;;
	bh_band_update)
	bh_band_update "$2" "$3"
	;;
	bhsta_link_check)
	bhsta_link_check
	;;
	wifi_bhcfg_update)
	topomon_wifi_bhcfg_update
	;;
	wifi_bhsta_modify)
	topomon_wifi_bhsta_modify "$2"
	;;
	set_mesh_wifi_config)
	set_ezmesh_wifi_config
	;;
	get_ezmesh_link_status)
	get_ezmesh_link_status
	;;
	check_sta_mlo_links)
	check_sta_mlo_links
	;;
	wifi_bhsta_isolate)
	topomon_wifi_bhsta_isolate "$2" "$3"
	;;
	*)
	;;
esac
