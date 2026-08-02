#!/bin/ash

log_exec() {
	echo "========== $1"
	eval "$1"
}

add_mlo_vap_into_list() {
	local mld_dev=
	local mlo_vap_bands=
	local radio_upcase=
	local mlo_vap_ifname=
	local mlo_vap_index=

	mld_dev=$(uci -q get misc.mld.hostap)
	[ -z "$mld_dev" ] && return

	mlo_vap_bands=$(uci -q get misc.mld.hostap_mlo)
	for radio in $mlo_vap_bands; do
		radio_upcase=$(echo "$radio" | tr '[a-z]' '[A-Z]')
		mlo_vap_ifname=$(uci -q get misc.wireless.ifname_mlo_$radio_upcase)
		if ifconfig "$mlo_vap_ifname" >/dev/null 2>&1; then
			mlo_vap_index=$(echo "$mlo_vap_ifname" | sed 's/[^0-9]//g')
			list="$list $mlo_vap_index"
		fi
	done
}

list="0 1"
if ifconfig wl14 >/dev/null 2>&1; then
	list="$list 14"
fi
if ifconfig wl15 >/dev/null 2>&1; then
	list="$list 15"
fi
if ifconfig wl2 >/dev/null 2>&1; then
	list="$list 2"
fi

iot_dev_support=$(uci -q get misc.features.iot_dev)
if [ "$iot_dev_support" = "1" ]; then
	if ifconfig wl16 >/dev/null 2>&1; then
		list="$list 16"
	fi

	if ifconfig wl17 >/dev/null 2>&1; then
		list="$list 17"
	fi
fi

mlo_vap_support=$(uci -q get misc.features.mlo_vap_support)
if [ "$mlo_vap_support" = "1" ]; then
	add_mlo_vap_into_list
fi

easymesh_support=$(mesh_cmd easymesh_support)
if [ "$easymesh_support" = "1" ]; then
	easymesh_role=$(uci -q get xiaoqiang.common.EASYMESH_ROLE)
	if [ "$easymesh_role" = "controller" ] \
			|| [ "$easymesh_role" = "agent" ]; then
		easymesh_configured=1
	fi
fi

netmode=$(uci -q get xiaoqiang.common.NETMODE)
if [ "$netmode" = "whc_cap" ] \
		|| [ "$netmode" = "whc_re" ] \
		|| [ "$netmode" = "lanapmode" ] \
		|| [ "$easymesh_configured" = "1" ]; then

	bh_radio_list="2g 5g 5gh"
	for bh_radio in $bh_radio_list; do
		bh_vap_if=$(uci -q get "misc.backhauls.backhaul_${bh_radio}_ap_iface")
		[ -z "$bh_vap_if" ] && continue

		bh_sta_if=$(uci -q get "misc.backhauls.backhaul_${bh_radio}_sta_iface")
		[ -z "$bh_sta_if" ] && continue

		if echo "${bh_vap_if:-wl}"|grep -qsvxE 'wl[0-2]'; then
			bh_vap_if=$(echo "$bh_vap_if" | cut -d l -f 2)
			bh_vap_list="$bh_vap_list $bh_vap_if"
		fi

		if [ -n "$bh_sta_if" ]; then
			bh_sta_if=$(echo "$bh_sta_if" | cut -d l -f 2)
			bh_sta_list="$bh_sta_list $bh_sta_if"
		fi
	done

	list="$list $bh_vap_list"
fi

echo "========== list:$list"
for i in $list; do
	radio=
	ifname=
	iface=

	echo "wl$i"
	log_exec "iwinfo wl$i info"
	log_exec "iwinfo wl$i assolist"
	log_exec "iwinfo wl$i txpowerlist"
	log_exec "iwinfo wl$i freqlist"
	log_exec "wlanconfig wl$i list"
	log_exec "iwconfig wl$i"
	log_exec "iwpriv wl$i get_chutil"
	log_exec "iwpriv wl$i get_channf"
	log_exec "iwpriv wl$i txrx_stats 9"
	log_exec "iwpriv wl$i txrx_stats 10"
	log_exec "iwpriv wl$i txrx_stats 262" #wds table
	radio=$(uci -q show misc.wireless | grep -w "wl$i" | grep -E "ifname_|wifi5_" | awk -F'=' '{print $1}')
	[ -n "$radio" ] && {
		radio=${radio##*_}
		ifname="wl$i"
		iface=$(uci -q get misc.wireless.if_$radio)
		log_exec "hostapd_cli -p /var/run/hostapd-$iface -i $ifname get_config | grep -v 'passphrase='"
	}
done

if [ "$netmode" = "whc_re" ] \
		|| [ "$easymesh_role" = "agent" ] \
		&& [ -n "$bh_sta_list" ]; then

	echo "========== bh_sta_list:$bh_sta_list"
	for i in $bh_sta_list; do
		echo "========== @@@@ iwinfo wl$i @@@@"
		log_exec "iwinfo wl$i info"
		log_exec "iwconfig wl$i"
		log_exec "wpa_cli -p /var/run/wpa_supplicant-wl$i -i wl$i status"
		log_exec "wpa_cli -p /var/run/wpa_supplicant-wl$i -i wl$i list_networks"
	done
fi
