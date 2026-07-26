#!/bin/sh
# Copyright (C) 2016 Xiaomi
#

. /lib/functions.sh

scan_wifi() {
        local cfgfile="$1"
        DEVICES=
        config_cb() {
                local type="$1"
                local section="$2"
                # section start
                case "$type" in
                        wifi-device)
                                append DEVICES "$section"
                                config_set "$section" vifs ""
                                config_set "$section" ht_capab ""
                        ;;
                esac
                # section end
                config_get TYPE "$CONFIG_SECTION" TYPE
                case "$TYPE" in
                        wifi-iface)
                                config_get device "$CONFIG_SECTION" device
                                config_get vifs "$device" vifs
                                append vifs "$CONFIG_SECTION"
                                config_set "$device" vifs "$vifs"
                        ;;
                esac
        }
        config_load "${cfgfile:-wireless}"
}


wifiap_interface_find_by_device()
{
	scan_wifi
	local ifname
	local ssid
	local ssid_base64
	local ssid_5g
	local ssid_base64_5g
	local key
	local key_base64
	local key_5g
	local key_base64_5g
	local device_name=`uci get misc.wireless.if_2G 2>/dev/null`
	local device_name_5g=`uci get misc.wireless.if_5G 2>/dev/null`
	local ifname_2g=`uci get misc.wireless.ifname_2G 2>/dev/null`
	local ifname_5g=`uci get misc.wireless.ifname_5G 2>/dev/null`

	if [ "${ifname_2g}" != "" ]; then
	config_get vifs "${device_name}" vifs
	for vif in $vifs; do
		config_get ifname "$vif" ifname
		if [ "$ifname" == "${ifname_2g}" ]; then
		config_get ssid "$vif" ssid
		config_get key "$vif" key
		if [ "$key" == "" ]; then
			config_get sae "$vif" sae
			if [ "$sae" == "1" ]; then
				config_get key "$vif" sae_password
			fi
		fi
		ssid_base64=`echo -n "$ssid" | base64 | tr -d '\n'`
		key_base64=`echo -n "$key" | base64 | tr -d '\n'`
		fi
	done
	fi
        if [ "${ifname_5g}" != "" ]; then
        config_get vifs "${device_name_5g}" vifs
        for vif in $vifs; do
                config_get ifname "$vif" ifname
                if [ "$ifname" == "${ifname_5g}" ]; then
                config_get ssid_5g "$vif" ssid
                config_get key_5g "$vif" key
                if [ "$key_5g" == "" ]; then
                    config_get sae "$vif" sae
                    if [ "$sae" == "1" ]; then
                        config_get key_5g "$vif" sae_password
                    fi
                fi
                ssid_base64_5g=`echo -n "${ssid_5g}" | base64 | tr -d '\n'`
                key_base64_5g=`echo -n "${key_5g}" | base64 | tr -d '\n'`
                fi
        done
	fi


tbus -t 2 list | grep -v netapi | grep -v master | while read a
do
     #call tbus function to notice device change wifi passwd
    [ "${ifname_2g}" == "" ] && [ "${ifname_5g}" == "" ] && return 1
    if [ "${ifname_2g}" == "" ];  then
	tbus -t 2 call $a notice  "{\"ssid_5g\":\"${ssid_base64_5g}\",\"passwd_5g\":\"${key_base64_5g}\"}"
    fi
    if [ "$ifname_5g" == "" ]; then
	tbus -t 2 call $a notice  "{\"ssid\":\"${ssid_base64}\",\"passwd\":\"${key_base64}\"}"
    else
        tbus -t 2 call $a notice  "{\"ssid\":\"${ssid_base64}\",\"passwd\":\"${key_base64}\",\"ssid_5g\":\"${ssid_base64_5g}\",\"passwd_5g\":\"${key_base64_5g}\"}"
    fi
done
}
scan_wifi
wifiap_interface_find_by_device

