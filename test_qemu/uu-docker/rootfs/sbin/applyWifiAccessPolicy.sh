#!/bin/sh

. /lib/functions.sh

log_file="/tmp/applyWifiAccessPolicy.log"
LOG_FILE_ENABLE=1

log()
{
	[ -n "${LOG_FILE_ENABLE}" ] && echo "$@" >> $log_file
}

cfg80211tool()
{
	local ifname="$1"
	# local ifup=$(ifconfig|grep $ifname > /dev/null;echo $?)

	[ -n "${LOG_FILE_ENABLE}" ] && echo cfg80211tool "$@" >> $log_file
	# if [ "$ifup" -eq 0 ]; then
		/usr/sbin/cfg80211tool "$@"
	# fi
}

addWifiAClByBand()
{
	local stamac="$1"
	local bindBand="$2"

	if [ -z "$stamac" ] || [ -z "$bindBand" ]; then
		log "addWifiAClByBand: param error! return"
		return
	fi

	local wifinum=$(uci -q get misc.wireless.wl_if_count)
	if [ "$bindBand" == "2G" ]; then
		local if_5G=$(uci -q get misc.wireless.if_5G)
		local ifname_5G=$(uci -q get misc.wireless.ifname_5G)
		local guest_5G=$(uci -q get misc.wireless.ifname_guest_5G)
		local iot_5G=$(uci -q get misc.wireless.wifi5_bk_5G)
		cfg80211tool "$if_5G" addwifi_acl "$stamac"
		cfg80211tool "$ifname_5G" kickmac "$stamac"
		if [ "$wifinum" -gt 2 ]; then
			local ifname_5G2=$(uci -q get misc.wireless.ifname_5GH)
			local if_5GH=$(uci -q get misc.wireless.if_5GH)
			cfg80211tool "$if_5GH" addwifi_acl "$stamac"
			cfg80211tool "$ifname_5G2" kickmac "$stamac"
		fi
		cfg80211tool "$guest_5G" kickmac "$stamac"
		cfg80211tool "$iot_5G" kickmac "$stamac"
	elif [ "$bindBand" == "5G" ]; then
		local if_2G=$(uci -q get misc.wireless.if_2G)
		local ifname_2G=$(uci -q get misc.wireless.ifname_2G)
		local guest_2G=$(uci -q get misc.wireless.ifname_guest_2G)
		local iot_2G=$(uci -q get misc.wireless.wifi5_bk_2G)
		cfg80211tool "$if_2G" addwifi_acl "$stamac"
		cfg80211tool "$ifname_2G" kickmac "$stamac"
		cfg80211tool "$guest_2G" kickmac "$stamac"
		cfg80211tool "$iot_2G" kickmac "$stamac"
	fi
}

delWifiAClByBand()
{
	local stamac="$1"
	local band="$2"

	if [ -z "$stamac" ] || [ -z "$band" ]; then
		log "delWifiAClByBand: param error! return"
		return
	fi

	local wifinum=$(uci -q get misc.wireless.wl_if_count)
	local if_2G=$(uci -q get misc.wireless.if_2G)
	local if_5G=$(uci -q get misc.wireless.if_5G)

	if [ "$band" == "2G" ]; then
		cfg80211tool "$if_2G" delwifi_acl "$stamac"
	elif [ "$band" == "5G" ]; then
		cfg80211tool "$if_5G" delwifi_acl "$stamac"
		if [ "$wifinum" -gt 2 ]; then
			local if_5GH=$(uci -q get misc.wireless.if_5GH)
			cfg80211tool "$if_5GH" delwifi_acl "$stamac"
		fi
	fi
}

flushAllWifiAccessACl()
{
	local wifinum=$(uci -q get misc.wireless.wl_if_count)
	local if_2G=$(uci -q get misc.wireless.if_2G)
	local if_5G=$(uci -q get misc.wireless.if_5G)

	cfg80211tool "$if_2G" flushwifi_acl
	cfg80211tool "$if_5G" flushwifi_acl
	if [ "$wifinum" -gt 2 ]; then
		local if_5GH=$(uci -q get misc.wireless.if_5GH)
		cfg80211tool "$if_5GH" flushwifi_acl
	fi
}

config_wifiaccess_acl_item()
{
	local stamac="$1"
	local bindMac="$2"
	local bindBand="$3"
	local wl_if_count=$(uci -q get misc.wireless.wl_if_count)
	local if_2G=$(uci -q get misc.wireless.if_2G)
	local if_5G=$(uci -q get misc.wireless.if_5G)
	local if_5GH

	[ $wl_if_count -eq 3 ] && {
		if_5GH=$(uci -q get misc.wireless.if_5GH)
	}

	if [ -z "$stamac" ] || [ -z "$bindMac" ] || [ -z "$bindBand" ]; then
		log "config_wifiaccess_acl_item: param error! return"
		return
	fi

	if [ "$bindMac" == "none" ] && [ "$bindBand" == "none" ]; then
		log "$stamac bind none"
		cfg80211tool "$if_2G" delwifi_acl "$stamac"
		cfg80211tool "$if_5G" delwifi_acl "$stamac"

		[ ! -z "$if_5GH" ] && {
			cfg80211tool "$if_5GH" delwifi_acl "$stamac"
		}

		return
	fi

	if [ "$bindMac" != "none" ]; then
		## need bind Mesh Node Mac
		local apmac=$(getmac lan)
		local apmacUpperCase=$(echo "$apmac" | tr 'a-z' 'A-Z')
		local bindMacUpperCase=$(echo "$bindMac" | tr 'a-z' 'A-Z')

		if [ "$bindMacUpperCase" == "$apmacUpperCase" ]; then
			## bind current node and band
			if [ "$bindBand" != "none" ]; then
				log "$stamac bind currentNode bind $bindBand"
				addWifiAClByBand "$stamac" "$bindBand"
				delWifiAClByBand "$stamac" "$bindBand"
			else
				## bind current node, not bind band
				log "$stamac bind currentNode not bind band"
				delWifiAClByBand "$stamac" "2G"
				delWifiAClByBand "$stamac" "5G"
			fi
		else
			## not bind current node
			log "$stamac not bind currentNode"
			addWifiAClByBand "$stamac" "2G"
			addWifiAClByBand "$stamac" "5G"
		fi
	else
		## only bind band
		log "$stamac only bind $bindBand"
		addWifiAClByBand "$stamac" "$bindBand"
		delWifiAClByBand "$stamac" "$bindBand"
	fi
}

__apply_wifiaccess_policy()
{
	local section="$1"
	local stamac=$(uci -q get wifiaccess.${section}.stamac)
	local bindMac=$(uci -q get wifiaccess.${section}.bindMac)
	local bindBand=$(uci -q get wifiaccess.${section}.bindBand)

	log "__apply_wifiaccess_policy: $stamac $bindMac $bindBand"
	config_wifiaccess_acl_item "$stamac" "$bindMac" "$bindBand"
}

config_all_wifiaccess_acl()
{
	log "config_all_wifiaccess_acl"
	flushAllWifiAccessACl
	config_load wifiaccess
	config_foreach __apply_wifiaccess_policy wifi-sta
}

log "applyWifiAccessPolicy: $@"

case "$1" in
	applyAll)
		config_all_wifiaccess_acl
		;;
	applyItem)
		shift 1
		config_wifiaccess_acl_item "$@"
		;;
esac
