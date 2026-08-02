#!/bin/sh

# mimesh_sync: sync mimesh

. /lib/mimesh/mimesh_public.sh


ERR_SYNC=60
ERR_SYNC_TIMEOUT=61
ERR_SYNC_ERR_WITHMSG=62
ERR_SYNC_WITHOUT_RE=63

wifi_mimesh_lock="/var/run/mimesh_wifi.lock"

# mimesh sync method
SYNC_USE_QCA=0  # disabled after trafficd ready
RETRY_MAX=3
RET_OK="success"
FCFG_SYNC="/var/run/trafficd_mimesh_sync_cap"

USE_ENCODE=1
GUEST_SUPPORT=$(uci -q get misc.mesh.guest)

__get_nfc()
{
	local nfc_support=$(uci -q get misc.nfc.nfc_support)

	if [ "$nfc_support" = "1" ]; then
		local nfc_enable=$(uci -q get nfc.nfc.nfc_enable)
		local config_id=$(uci -q get nfc.nfc.config_id)
		[ -z "$nfc_enable" ] && nfc_enable=0
		nfc_jsonstr="\"nfc_enable\":\"$nfc_enable\",\"nfc_id\":\"$config_id\""
	else
		nfc_jsonstr=""
	fi
}

__get_hostap_mlo()
{
	local mlo_support=$(mesh_cmd mlo_support)
	local mlo_vap_support="$(uci -q get misc.features.mlo_vap_support)"
	# for vap_mlo
	if [ "$mlo_vap_support" = "1" ]; then
		local hostap_mld_dev=$(uci -q get misc.mld.hostap)
		local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
		local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_2g\'" | awk -F"." '{print $2}')
		local basic_wifi_enc="$(uci -q get wireless.$iface_2g.encryption)"
		local basic_wifi_owe="$(uci -q get wireless.$iface_2g.owe)"

		local mlo_enable=$(uci -q get wireless.${hostap_mld_dev}.mlo_enable)
		[ -z "$mlo_enable" ] && mlo_enable='0'

		local mlo_ssid=$(uci -q get wireless.${hostap_mld_dev}.mlo_ssid)
		[ -z "$mlo_ssid" ] && {
			local basic_wifi_ssid="$(uci -q get wireless.$iface_2g.ssid)"
			local mlo_default_suffix="$(uci -q get misc.mld.ssid_suffix)"
			[ -z "$mlo_default_suffix" ] && mlo_default_suffix="_MLO"

			mlo_ssid="$basic_wifi_ssid$mlo_default_suffix"
		}

		local mlo_hidden=$(uci -q get wireless.${hostap_mld_dev}.mlo_hidden)
		[ -z "$mlo_hidden" ] && mlo_hidden='0'

		local mlo_enc=$(uci -q get wireless.${hostap_mld_dev}.mlo_enc)
		[ -z "$mlo_enc" ] && {
			[ "$basic_wifi_enc" = "none" -o "$basic_wifi_owe" = "1" ] && mlo_enc='owe' || mlo_enc='ccmp'
		}

		local mlo_pwd=$(uci -q get wireless.${hostap_mld_dev}.mlo_pwd)
		[ -z "$mlo_pwd" ] && {
			if [ "$mlo_enc" = "owe" ]; then
				mlo_pwd=''
			elif [ "$basic_wifi_enc" = "ccmp" ]; then
				mlo_pwd="$(uci -q get wireless.$iface_2g.sae_password)"
			else
				mlo_pwd="$(uci -q get wireless.$iface_2g.key)"
			fi
		}

		if [ "$USE_ENCODE" -gt 0 ]; then
			mlo_ssid="$(base64_enc "$mlo_ssid")"
			mlo_pwd="$(base64_enc "$mlo_pwd")"
		fi

		hostap_mlo_jsonstr="\"mlo\":\"0\",\"mlo_enable\":\"$mlo_enable\",\"mlo_ssid\":\"$mlo_ssid\",\"mlo_hidden\":\"$mlo_hidden\",\"mlo_enc\":\"$mlo_enc\",\"mlo_pwd\":\"$mlo_pwd\""

	elif [ "$mlo_support" = "1" ]; then
		local hostap_mld_dev=$(uci -q get misc.mld.hostap)
		local hostap_mlo_enable=$(uci -q get wireless.${hostap_mld_dev}.mlo_enable)
		[ -z "$hostap_mlo_enable" ] && hostap_mlo_enable=0
		hostap_mlo_jsonstr="\"mlo\":\"$hostap_mlo_enable\""
	else
		hostap_mlo_jsonstr=""
	fi
}

__get_wifi()
{
	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_2g\'" | awk -F"." '{print $2}')
	local device_2g=$(uci -q get misc.wireless.if_2G)

	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')
	local device_5g=$(uci -q get misc.wireless.if_5G)

	wifi_countrycode=$(uci -q get wireless.wifi0.country)
	ch2g_adj_en=$(uci -q get wireless.$device_2g.ch_adj_en)
	bh_en=$(uci -q get xiaoqiang.common.bhap_enable)

	local bh_band=$(mesh_cmd backhaul get band)
	local is_tri_band=$(mesh_cmd is_tri_band)
	if [ "$is_tri_band" = "1" ]; then
		local bh_band_upcase=$(echo "$bh_band" | tr '[a-z]' '[A-Z]')
		local bh_ifname=$(uci -q get misc.wireless.ifname_$bh_band_upcase)
		device_5g=$(uci -q get misc.wireless.if_${bh_band_upcase})

		local nbh_band_upcase=$(mesh_cmd nbh_band | tr '[a-z]' '[A-Z]')
		local nbh_ifname=$(uci -q get misc.wireless.ifname_$nbh_band_upcase)
		local device_5g_nbh=$(uci -q get misc.wireless.if_$nbh_band_upcase)

		local ifname_5gh=$(uci -q get misc.wireless.ifname_5GH)
		local iface_5gh=$(uci show wireless | grep -w "ifname=\'$ifname_5gh\'" | awk -F"." '{print $2}')

		local iface_5g_nbh=
		local dev_type=$(mesh_cmd dev_type)
		# when backhaul is 5gh and cap is tri-band suit router,
		# set iface_5g_swap=1 to ensure that tri-suite cap is compatible
		# with the res which backhaul is 5g when doing config sync
		if [ "$bh_band" = "5gh" ] && [ "$dev_type" = "tri-suite" ]; then
			# iface_5g -> 5gl, iface_5gh -> 5gh, swap=1
			iface_5g_swap=1
			iface_5g_nbh=$iface_5gh
		else
			# iface_5g -> bh 5g, iface_5gh -> nbh 5g, swap=0
			iface_5g_swap=0
			iface_5g=$(uci show wireless | grep -w "ifname=\'$bh_ifname\'" | awk -F"." '{print $2}')
			iface_5g_nbh=$(uci show wireless | grep -w "ifname=\'$nbh_ifname\'" | awk -F"." '{print $2}')
		fi

		ssid_5g_nbh="`uci -q get wireless.$iface_5g_nbh.ssid`"
		pswd_5g_nbh="`uci -q get wireless.$iface_5g_nbh.key`"
		[ -z "$pswd_5g_nbh" ] && pswd_5g_nbh=""
		mgmt_5g_nbh="`uci -q get wireless.$iface_5g_nbh.encryption`"
		hidden_5g_nbh="`uci -q get wireless.$iface_5g_nbh.hidden`"
		[ -z "$hidden_5g_nbh" ] && hidden_5g_nbh=0
		disabled_5g_nbh="`uci -q get wireless.$iface_5g_nbh.disabled`"
		[ -z "$disabled_5g_nbh" ] && disabled_5g_nbh=0

		txpwr_5g_nbh="`uci -q get wireless.$device_5g_nbh.txpwr`"
		[ -z "$txpwr_5g_nbh" ] && txpwr_5g_nbh="max"
		ch_5g_nbh="`uci -q get wireless.$device_5g_nbh.channel`"
		[ -z "$ch_5g_nbh" ] && ch_5g_nbh="auto"
		bw_5g_nbh="`uci -q get wireless.$device_5g_nbh.bw`"
		[ -z "$bw_5g_nbh" ] && bw_5g_nbh=0
		txbf_5g_nbh="`uci -q get wireless.$device_5g_nbh.txbf`"
		[ -z "$txbf_5g_nbh" ] && txbf_5g_nbh=3
		ax_5g_nbh="`uci -q get wireless.$device_5g_nbh.ax`"
		[ -z "$ax_5g_nbh" ] && ax_5g_nbh=1

		bsd_5g_nbh="`uci -q get wireless.$iface_5g_nbh.bsd`"
		[ -z "$bsd_5g_nbh" ] && bsd_5g_nbh=0
		sae_5g_nbh="`uci -q get wireless.$iface_5g_nbh.sae`"
		[ -z "$sae_5g_nbh" ] && sae_5g_nbh=""
		sae_pwd_5g_nbh="`uci -q get wireless.$iface_5g_nbh.sae_password`"
		[ -z "$sae_pwd_5g_nbh" ] && sae_pwd_5g_nbh=""
		ieee80211w_5g_nbh="`uci -q get wireless.$iface_5g_nbh.ieee80211w`"
		[ -z "$ieee80211w_5g_nbh" ] && ieee80211w_5g_nbh=""

		if [ "$USE_ENCODE" -gt 0 ]; then
			ssid_5g_nbh="$(base64_enc "$ssid_5g_nbh")"
			pswd_5g_nbh="$(base64_enc "$pswd_5g_nbh")"
			sae_pwd_5g_nbh="$(base64_enc "$sae_pwd_5g_nbh")"
		else
			ssid_5g_nbh="$(str_escape "$ssid_5g_nbh")"
			pswd_5g_nbh="$(str_escape "$pswd_5g_nbh")"
			sae_pwd_5g_nbh="$(str_escape "$sae_pwd_5g_nbh")"
		fi
		[ -z "$pswd_5g_nbh" -a "$mgmt_5g_nbh" = "ccmp" ] && pswd_5g_nbh="$sae_pwd_5g_nbh"
		nbh_jsonstr="\"bh_band\":\"$bh_band\",\"ssid_5g_nbh\":\"$ssid_5g_nbh\",\"pswd_5g_nbh\":\"$pswd_5g_nbh\",\
\"mgmt_5g_nbh\":\"$mgmt_5g_nbh\",\"hidden_5g_nbh\":\"$hidden_5g_nbh\",\"disabled_5g_nbh\":\"$disabled_5g_nbh\",\
\"ax_5g_nbh\":\"$ax_5g_nbh\",\"txpwr_5g_nbh\":\"$txpwr_5g_nbh\",\"ch_5g_nbh\":\"$ch_5g_nbh\",\"bw_5g_nbh\":\"$bw_5g_nbh\",\
\"bsd_5g_nbh\":\"$bsd_5g_nbh\",\"txbf_5g_nbh\":\"$txbf_5g_nbh\",\"sae_5g_nbh\":\"$sae_5g_nbh\",\
\"sae_passwd_5g_nbh\":\"$sae_pwd_5g_nbh\",\"ieee80211w_5g_nbh\":\"$ieee80211w_5g_nbh\",\"iface_5g_swap\":\"$iface_5g_swap\""
	else
		nbh_jsonstr=""
	fi

	ssid_2g="`uci -q get wireless.$iface_2g.ssid`"
	pswd_2g="`uci -q get wireless.$iface_2g.key`"
	[ -z "$pswd_2g" ] && pswd_2g=""
	mgmt_2g="`uci -q get wireless.$iface_2g.encryption`"
	hidden_2g="`uci -q get wireless.$iface_2g.hidden`"
	[ -z "$hidden_2g" ] && hidden_2g=0
	disabled_2g="`uci -q get wireless.$iface_2g.disabled`"
	[ -z "$disabled_2g" ] && disabled_2g=0

	ssid_5g="`uci -q get wireless.$iface_5g.ssid`"
	pswd_5g="`uci -q get wireless.$iface_5g.key`"
	[ -z "$pswd_5g" ] && pswd_5g=""
	mgmt_5g="`uci -q get wireless.$iface_5g.encryption`"
	hidden_5g="`uci -q get wireless.$iface_5g.hidden`"
	[ -z "$hidden_5g" ] && hidden_5g=0
	disabled_5g="`uci -q get wireless.$iface_5g.disabled`"
	[ -z "$disabled_5g" ] && disabled_5g=0

	txpwr_2g="`uci -q get wireless.$device_2g.txpwr`"
	[ -z "$txpwr_2g" ] && txpwr_2g=max

	ch_2g="`uci -q get wireless.$device_2g.channel`"
	[ -z "$ch_2g" ] && ch_2g="auto"

	bw_2g="`uci -q get wireless.$device_2g.bw`"
	[ -z "$bw_2g" ] && bw_2g=0

	txbf_2g="`uci -q get wireless.$device_2g.txbf`"
	[ -z "$txbf_2g" ] && txbf_2g=3

	ax_2g="`uci -q get wireless.$device_2g.ax`"
	[ -z "$ax_2g" ] && ax_2g=1

	txpwr_5g="`uci -q get wireless.$device_5g.txpwr`"
	[ -z "$txpwr_5g" ] && txpwr_5g=max

	ch_5g="`uci -q get wireless.$device_5g.channel`"
	[ -z "$ch_5g" ] && ch_5g="auto"

	bw_5g="`uci -q get wireless.$device_5g.bw`"
	if [ "$is_tri_band" = "1" ] && [ "$bh_band" = "5gh" ]; then
		# tri-suite backhaul, sync 80 to re while BW is 0 or auto
		[ -z "$bw_5g" -o "$bw_5g" = "0" -o "$bw_5g" = "auto" ] && bw_5g=80 && bw_5g_auto=1
	else
		[ -z "$bw_5g" ] && bw_5g=0
	fi

	txbf_5g="`uci -q get wireless.$device_5g.txbf`"
	[ -z "$txbf_5g" ] && txbf_5g=3

	ax_5g="`uci -q get wireless.$device_5g.ax`"
	[ -z "$ax_5g" ] && ax_5g=1

	bsd_2g="`uci -q get wireless.$iface_2g.bsd`"
	[ -z "$bsd_2g" ] && bsd_2g=0

	bsd_5g="`uci -q get wireless.$iface_5g.bsd`"
	[ -z "$bsd_5g" ] && bsd_5g=0

	sae_2g="`uci -q get wireless.$iface_2g.sae`"
	[ -z "$sae_2g" ] && sae_2g=""

	sae_5g="`uci -q get wireless.$iface_5g.sae`"
	[ -z "$sae_5g" ] && sae_5g=""

	sae_pwd_2g="`uci -q get wireless.$iface_2g.sae_password`"
	[ -z "$sae_pwd_2g" ] && sae_pwd_2g=""

	sae_pwd_5g="`uci -q get wireless.$iface_5g.sae_password`"
	[ -z "$sae_pwd_5g" ] && sae_pwd_5g=""

	ieee80211w_2g="`uci -q get wireless.$iface_2g.ieee80211w`"
	[ -z "$ieee80211w_2g" ] && ieee80211w_2g=""

	ieee80211w_5g="`uci -q get wireless.$iface_5g.ieee80211w`"
	[ -z "$ieee80211w_5g" ] && ieee80211w_5g=""

	support160="`uci -q get misc.wireless.support_160m`"
	[ -z "$support160" ] && support160=0

	iot_switch="`uci -q get wireless.miot_2G.userswitch`"
	[ -z "$iot_switch" ] && iot_switch=""

	twt="$(uci -q get wireless.$iface_2g.twt_responder)"
	[ -z "$twt" ] && twt=""

	[ "$USE_ENCODE" -gt 0 ] || {
	# support special string escape
		ssid_2g="$(str_escape "$ssid_2g")"
		pswd_2g="$(str_escape "$pswd_2g")"
		ssid_5g="$(str_escape "$ssid_5g")"
		pswd_5g="$(str_escape "$pswd_5g")"
		sae_pwd_2g="$(str_escape "$sae_pwd_2g")"
		sae_pwd_5g="$(str_escape "$sae_pwd_5g")"
	}
}

__get_bh_wifi()
{
	local bh_band=$(mesh_cmd backhaul get band)
	local iface_5g_name=`uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface`
	local iface_5g_no=`uci show wireless|grep $iface_5g_name|awk -F "." '{print $2}'`
	if [ -n "$iface_5g_no" ]; then
		ssid_bh="`uci -q get wireless.$iface_5g_no.ssid`"
		pswd_bh="`uci -q get wireless.$iface_5g_no.key`"
		mgmt_bh="`uci -q get wireless.$iface_5g_no.encryption`"
		maclist_5g="`uci -q get wireless.$iface_5g_no.maclist`"
		maclist_5g_format="`echo -n $maclist_5g | sed "s/ /;/g"`"
		filter_5g="`uci -q get wireless.$iface_5g_no.macfilter`"
	else
		random_ssid_str="`dd if=/dev/urandom bs=1 count=6 2> /dev/null | openssl base64`"
		ssid_bh="MiMesh_$random_ssid_str"
		pswd_bh="`dd if=/dev/urandom bs=1 count=12 2> /dev/null | openssl base64`"
		mgmt_bh="psk2"
		maclist_5g=""
		maclist_5g_format=""
		filter_5g=""
	fi

	echo "$ssid_bh" > /tmp/ssid_backhaul_init
	echo "$pswd_bh" > /tmp/pswd_backhaul_init
}

__get_guest()
{
	[ "$GUEST_SUPPORT" != "1" ] && return

	local gst_sect=""
	local gst_ssid=""
	local gst_mgmt=""
	local gst_pswd=""
	local gst_disab="1"
	local gst_sae=""
	local gst_sae_pswd=""
	local gst_ieee80211w=""
	local jstr=""

	gst_sect="guest_2G"
	if [ "$(uci -q get wireless.$gst_sect)" = "wifi-iface" ]; then
		gst_disab="$(uci -q get wireless.$gst_sect.disabled)"
		[ -z "$gst_disab" ] && gst_disab=0
		if [ "$gst_disab" != "1" ]; then
			gst_ssid="$(uci -q get wireless.$gst_sect.ssid)"
			gst_mgmt="$(uci -q get wireless.$gst_sect.encryption)"
			gst_pswd="$(uci -q get wireless.$gst_sect.key)"
			if [ "$gst_mgmt" = "ccmp" ] || [ "$gst_mgmt" = "psk2+ccmp" ]; then
				gst_sae="$(uci -q get wireless.$gst_sect.sae)"
				gst_sae_pswd="$(uci -q get wireless.$gst_sect.sae_password)"
				gst_ieee80211w="$(uci -q get wireless.$gst_sect.ieee80211w)"
			fi

			if [ "$USE_ENCODE" -gt 0 ]; then
				# support special string escape
				gst_ssid="$(base64_enc "$gst_ssid")"
				gst_pswd="$(base64_enc "$gst_pswd")"
				gst_sae_pswd="$(base64_enc "$gst_sae_pswd")"
			fi

			gst_vlan="$(uci -q get port_service.guest.vlan)"

			# construct gst_jstr
			if [ "$gst_mgmt" = "ccmp" ] || [ "$gst_mgmt" = "psk2+ccmp" ]; then
				gst_jstr="\"gst_ssid\":\"$gst_ssid\",\"gst_disab\":\"$gst_disab\",\"gst_mgmt\":\"$gst_mgmt\",\"gst_pswd\":\"$gst_pswd\",\
\"gst_sae\":\"$gst_sae\",\"gst_sae_pswd\":\"$gst_sae_pswd\",\"gst_ieee80211w\":\"$gst_ieee80211w\",\"gst_vlan\":\"$gst_vlan\""
			else
				gst_jstr="\"gst_ssid\":\"$gst_ssid\",\"gst_disab\":\"$gst_disab\",\"gst_mgmt\":\"$gst_mgmt\",\"gst_pswd\":\"$gst_pswd\",\"gst_vlan\":\"$gst_vlan\""
			fi
		else
			gst_jstr="\"gst_disab\":\"$gst_disab\""
		fi
	fi
}

__get_iotwifi()
{
	local iot_dev_support=$(uci -q get misc.features.iot_dev)

	if [ "$iot_dev_support" = "1" ]; then
		local iot2g_ssid="`uci -q get wireless.iot_2g.ssid`"
		local iot2g_encryption="`uci -q get wireless.iot_2g.encryption`"
		local iot2g_wifi5mode="`uci -q get wireless.iot_2g.iotwifi5mode`"
		local iot2g_disabled="`uci -q get wireless.iot_2g.disabled`"
		local iot2g_password=""
		if [ "$iot2g_encryption" == "psk2" -o "$iot2g_encryption" == "mixed-psk" -o "$iot2g_encryption" == "psk" ]; then
			iot2g_password="`uci -q get wireless.iot_2g.key`"
		elif [ "$iot2g_encryption" == "ccmp" -o "$iot2g_encryption" == "psk2+ccmp" ]; then
			iot2g_password="`uci -q get wireless.iot_2g.sae_password`"
		fi

		local iot5g_ssid="`uci -q get wireless.iot_5g.ssid`"
		local iot5g_encryption="`uci -q get wireless.iot_5g.encryption`"
		local iot5g_wifi5mode="`uci -q get wireless.iot_5g.iotwifi5mode`"
		local iot5g_disabled="`uci -q get wireless.iot_5g.disabled`"
		local iot5g_password=""
		if [ "$iot5g_encryption" == "psk2" -o "$iot5g_encryption" == "mixed-psk" -o "$iot5g_encryption" == "psk" ]; then
			iot5g_password="`uci -q get wireless.iot_5g.key`"
		elif [ "$iot5g_encryption" == "ccmp" -o "$iot5g_encryption" == "psk2+ccmp" ]; then
			iot5g_password="`uci -q get wireless.iot_5g.sae_password`"
		fi

		local miot_access_iotdev="`uci -q get wireless.miot_2G.miot_access_iotdev`"
		[ -z "$miot_access_iotdev" ] && {
			miot_access_iotdev=0
		}

		if [ "$USE_ENCODE" -gt 0 ]; then
			iot2g_ssid="$(base64_enc "$iot2g_ssid")"
			iot2g_password="$(base64_enc "$iot2g_password")"
			iot5g_ssid="$(base64_enc "$iot5g_ssid")"
			iot5g_password="$(base64_enc "$iot5g_password")"
		fi
		
		iot_wifi_jsonstr="\"iot2g_ssid\":\"$iot2g_ssid\",\"iot2g_pwd\":\"$iot2g_password\",\"iot2g_enc\":\"$iot2g_encryption\",\
\"iot2g_disabled\":\"$iot2g_disabled\",\"iot2g_wifi5\":\"$iot2g_wifi5mode\",\"iot5g_ssid\":\"$iot5g_ssid\",\
\"iot5g_pwd\":\"$iot5g_password\",\"iot5g_enc\":\"$iot5g_encryption\",\"iot5g_disabled\":\"$iot5g_disabled\",\"iot5g_wifi5\":\"$iot5g_wifi5mode\",\"miot_access_iotdev\":\"$miot_access_iotdev\""
	else
		iot_wifi_jsonstr=""
	fi
}

__get_system()
{
	timezoneindex="$(uci -q get system.@system[0].timezoneindex)"
	timezone="`uci -q get system.@system[0].timezone`"
	ota_auto="`uci -q get otapred.settings.auto`"
	[ -z "$ota_auto" ] && {
		ota_auto=0
		uci set otapred.settings.auto=0
		uci commit otapred
	}

	ota_time="`uci -q get otapred.settings.time`"
	[ -z "$ota_time" ] && {
		ota_time=4
		uci set otapred.settings.time="$ota_time"
		uci commit otapred
	}

	led_blue="`uci -q get xiaoqiang.common.BLUE_LED`"
	[ -z "$led_blue" ] && led_blue=1
	led_blue_sum=$(uci -q get xiaoqiang.common.BLUE_LED_SUM)

	ethled="`uci -q get xiaoqiang.common.ETHLED`"
	[ -z "$ethled" ] && ethled=1
	ethled_sum=$(uci -q get xiaoqiang.common.ETHLED_SUM)
	
	fan_mode=$(uci -q get mitempctrl.settings.mode)
	temp_config_sum=$(uci -q get mitempctrl.settings.config_sum)

	lang="`uci -q get luci.main.lang`"
	CountryCode="`nvram get CountryCode`"

	server_S="`uci -q get miwifi.server.S`"
	server_APP="`uci -q get miwifi.server.APP`"
	server_API="`uci -q get miwifi.server.API`"
	server_STUN="`uci -q get miwifi.server.STUN`"
	server_BROKER="`uci -q get miwifi.server.BROKER`"

	privacy="`uci -q get xiaoqiang.common.PRIVACY`"
}

__get_miscan()
{
	miscan_enable="`uci -q get miscan.config.enabled`"
	[ -z "$miscan_enable" ] && miscan_enable=1
}

__info_compose()
{
    # collect whc_sync msg & push to REs
#tbus call 192.168.31.115 whc_sync "{\"ssid_2g\":\"!@D01-son\",\"ssid_5g\":\"!@D01-son\",\"pswd_2g\":\"123456789\",\"pswd_5g\":\"123456789\",\"mgmt_2g\":\"mixed-psk\",\"mgmt_5g\":\"mixed-psk\",\"txpwr_2g\":\"max\",\"txpwr_5g\":\"max\",\"hidden_2g\":\"0\",\"hidden_5g\":\"0\,\"ch_2g\":\"1\",\"ch_5g\":\"161\",\"bw_2g\":\"0\",\"bw_5g\":\"0\",\"bsd_2g\":\"1\",\"bsd_5g\":\"1\",\"txbf_2g\":\"0\",\"txbf_5g\":\"0\",\sae_2g\":\"1\",\"sae_5g\":\"1\",\"sae_passwd_2g\":\"123456789\",\"sae_passwd_5g\":\"123456789\",\"ieee80211w_2g\":\"1\",\"ieee80211w_5g\":\"1\",\"gst_disab\":\"1\",\"gst_ssid\":\"\",\"gst_pswd\":\"\",\"gst_mgmt\":\"\",\"timezone\":\"CST-8\",\"ota_auto\":\"0\",\"ota_time\":\"4\",\"led_blue\":\"1\"}"

	__get_wifi

	__get_guest

	__get_system
	__get_miscan
	__get_nfc
	__get_hostap_mlo
	__get_iotwifi

	msg_decode="{\
\"ssid_2g\":\"$ssid_2g\",\"ssid_5g\":\"$ssid_5g\",\"pswd_2g\":\"$pswd_2g\",\"pswd_5g\":\"$pswd_5g\",\
\"mgmt_2g\":\"$mgmt_2g\",\"mgmt_5g\":\"$mgmt_5g\",\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\"ch2g_adj_en\":\"$ch2g_adj_en\",\"bh_en\":\"$bh_en\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"bsd_2g\":\"$bsd_2g\",\"bsd_5g\":\"$bsd_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\
\"sae_2g\":\"$sae_2g\",\"sae_5g\":\"$sae_5g\",\"sae_passwd_2g\":\"$sae_pwd_2g\",\"sae_passwd_5g\":\"$sae_pwd_5g\",\
\"ieee80211w_2g\":\"$ieee80211w_2g\",\"ieee80211w_5g\":\"$ieee80211w_5g\",\
\"timezone\":\"$timezone\",\"ota_auto\":\"$ota_auto\",\"ota_time\":\"$ota_time\",\"led_blue\":\"$led_blue\",\"led_blue_sum\":\"$led_blue_sum\",\
\"ethled\":\"$ethled\",\"ethled_sum\":\"$ethled_sum\",\"miscan_enable\":\"$miscan_enable\",\"support160\":\"$support160\",\
\"iot_switch\":\"$iot_switch\",\"twt\":\"$twt\",\
\"fan_mode\":\"$fan_mode\",\"temp_config_sum\":\"$temp_config_sum\"\
}"

	msg="$msg_decode"
	if [ "$USE_ENCODE" -gt 0 ]; then
	msg="{\
\"ssid_2g\":\"$(base64_enc "$ssid_2g")\",\"ssid_5g\":\"$(base64_enc "$ssid_5g")\",\"pswd_2g\":\"$(base64_enc "$pswd_2g")\",\"pswd_5g\":\"$(base64_enc "$pswd_5g")\",\
\"mgmt_2g\":\"$mgmt_2g\",\"mgmt_5g\":\"$mgmt_5g\",\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\"ch2g_adj_en\":\"$ch2g_adj_en\",\"bh_en\":\"$bh_en\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"bsd_2g\":\"$bsd_2g\",\"bsd_5g\":\"$bsd_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\
\"sae_2g\":\"$sae_2g\",\"sae_5g\":\"$sae_5g\",\"sae_passwd_2g\":\"$(base64_enc "$sae_pwd_2g")\",\"sae_passwd_5g\":\"$(base64_enc "$sae_pwd_5g")\",\
\"ieee80211w_2g\":\"$ieee80211w_2g\",\"ieee80211w_5g\":\"$ieee80211w_5g\",\
\"timezone\":\"$timezone\",\"ota_auto\":\"$ota_auto\",\"ota_time\":\"$ota_time\",\"led_blue\":\"$led_blue\",\"led_blue_sum\":\"$led_blue_sum\",\
\"ethled\":\"$ethled\",\"ethled_sum\":\"$ethled_sum\",\"miscan_enable\":\"$miscan_enable\",\"support160\":\"$support160\",\
\"iot_switch\":\"$iot_switch\",\"twt\":\"$twt\",\
\"fan_mode\":\"$fan_mode\",\"temp_config_sum\":\"$temp_config_sum\",\"privacy\":\"$privacy\"\
}"
	fi

	[ -n "$timezoneindex" ] && msg="$(json_str_append "$msg" "\"tz_index\":\"$timezoneindex\"")"
	[ "$bw_5g_auto" = "1" ] && msg="$(json_str_append "$msg" "\"bw_5g_auto\":\"$bw_5g_auto\"")"
	msg="$(json_str_append "$msg" "$nbh_jsonstr")"
	msg="$(json_str_append "$msg" "\"dev_type\":\"$(mesh_cmd dev_type)\"")"
	msg="$(json_str_append "$msg" "$nfc_jsonstr")"
	msg="$(json_str_append "$msg" "$hostap_mlo_jsonstr")"
	msg="$(json_str_append "$msg" "$iot_wifi_jsonstr")"
	[ -n "$gst_jstr" ] && msg="$(json_str_append "$msg" "$gst_jstr")"
}

__init_info_compose()
{
	local meshNewConfig="$1"

	__get_wifi
	__get_system
	__get_nfc
	__get_hostap_mlo

	enc_mode=$(/usr/sbin/check_encrypt_mode.lua 2>>/dev/null)
	if [ "$enc_mode" = "1" ]; then
		web_passwd="$(uci -q get account.legacy.admin)"
		web_passwd256="$(uci -q get account.common.admin)"
	else
		web_passwd="$(uci -q get account.common.admin)"
		web_passwd256=
	fi

	#cap_mode
	cap_mode=
	cap_ip=
	vendorinfo=

	local mesh_version="`uci -q get xiaoqiang.common.MESH_VERSION`"
	if [ -z "$mesh_version" ]; then
		mesh_version=1
	fi

	if [ "$mesh_version" -ge "2" ]; then
		net_mode="`uci -q get xiaoqiang.common.NETMODE`"
		if [ "$net_mode" = "lanapmode" ]; then
			cap_mode="ap"
			cap_ip="`uci -q get network.lan.ipaddr`"
			local model="`bdata get model`"
			local color="`bdata get color`"
			local rom="`uci get /usr/share/xiaoqiang/xiaoqiang_version.version.ROM`"
			vendorinfo="miwifi-${model}-${rom}-${color}"
		elif [ "$net_mode" = "whc_re" ]; then
			cap_mode="`uci -q get xiaoqiang.common.CAP_MODE`"
			cap_ip="`uci -q get xiaoqiang.common.CAP_IP`"
		else
			cap_mode="router"
			cap_ip="`uci -q get network.lan.ipaddr`"
		fi
	fi

	[ "$USE_ENCODE" != "0" ] && nbh_b64=1 || nbh_b64=0

	if [ -n "$CountryCode" -a "$CountryCode" != "CN" ]; then
		init_msg="{\
\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\"ch2g_adj_en\":\"$ch2g_adj_en\",\"bh_en\":\"$bh_en\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\"wifi_countrycode\":\"$wifi_countrycode\",\
\"support160\":\"$support160\",\"web_passwd\":\"$web_passwd\",\"mesh_version\":\"$mesh_version\",\"cap_mode\":\"$cap_mode\",\"cap_ip\":\"$cap_ip\",\
\"vendorinfo\":\"$vendorinfo\",\"nbh_b64\":\"$nbh_b64\",\
\"timezone\":\"$timezone\",\"lang\":\"$lang\",\"CountryCode\":\"$CountryCode\",\"server_S\":\"$server_S\",\"server_APP\":\"$server_APP\",\
\"server_API\":\"$server_API\",\"server_STUN\":\"$server_STUN\",\"server_BROKER\":\"$server_BROKER\"\
}"
	else
		init_msg="{\
\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\"ch2g_adj_en\":\"$ch2g_adj_en\",\"bh_en\":\"$bh_en\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\
\"support160\":\"$support160\",\"web_passwd\":\"$web_passwd\",\"mesh_version\":\"$mesh_version\",\"cap_mode\":\"$cap_mode\",\"cap_ip\":\"$cap_ip\",\
\"vendorinfo\":\"$vendorinfo\",\"nbh_b64\":\"$nbh_b64\"\
}"
	fi

	[ -n "$web_passwd256" ] && init_msg="$(json_str_append "$init_msg" "\"web_passwd256\":\"$web_passwd256\"")"

	[ "$bw_5g_auto" = "1" ] && init_msg="$(json_str_append "$init_msg" "\"bw_5g_auto\":\"$bw_5g_auto\"")"
	init_msg="$(json_str_append "$init_msg" "$nbh_jsonstr")"
	init_msg="$(json_str_append "$init_msg" "\"dev_type\":\"$(mesh_cmd dev_type)\"")"
	init_msg="$(json_str_append "$init_msg" "$nfc_jsonstr")"
	init_msg="$(json_str_append "$init_msg" "$hostap_mlo_jsonstr")"

	if [ "$meshNewConfig" = "meshNewConfig" ]; then
        __get_iotwifi
        init_msg="$(json_str_append "$init_msg" "$iot_wifi_jsonstr")"
	fi

}
__syncbuf_compare()
{
	local msg_pre=`cat $FCFG_SYNC | grep -E "ssid.*pswd.*mgmt.*" | awk 'END{print $0}'`
	local msg_now="$1"
	[ "$msg_pre" = "$msg_now" ]
}

## sync_jsonbuf
# output jsonbuf as input for tbus call * whc_sync "$jsonbuf"
mimesh_sync_jsonbuf()
{
	__info_compose
	echo "$msg"

	__syncbuf_compare "$msg" || MIMESH_LOGI " whc_sync reply msg=<\"$msg\">"
	echo "`date +%Y%m%d-%H%M%S` whc_sync reply msg compose on CAP:" > "$FCFG_SYNC"
	echo "$msg_decode" >> "$FCFG_SYNC"
	echo "$msg" >> "$FCFG_SYNC"
}

mimesh_init_jsonbuf()
{
	__init_info_compose "$1"
	echo "$init_msg"
}

mimesh_init_sync_jsonbuf()
{
	__init_info_compose "$1"
	__get_bh_wifi

	[ "$mgmt_2g" == "ccmp" ] && pswd_2g=$sae_pwd_2g
	[ "$mgmt_5g" == "ccmp" ] && pswd_5g=$sae_pwd_5g

	init_syncbuf="{\
\"bsd\":$bsd_5g,\
\"ssid_2g\":\"$(base64_enc "$ssid_2g")\",\"pswd_2g\":\"$(base64_enc "$pswd_2g")\",\"mgmt_2g\":\"$mgmt_2g\",\
\"ssid_5g\":\"$(base64_enc "$ssid_5g")\",\"pswd_5g\":\"$(base64_enc "$pswd_5g")\",\"mgmt_5g\":\"$mgmt_5g\",\
\"ssid_bh\":\"$(base64_enc "$ssid_bh")\",\"pswd_bh\":\"$(base64_enc "$pswd_bh")\",\"mgmt_bh\":\"$mgmt_bh\",\
\"initbuf\":$init_msg\
}"
	echo "$init_syncbuf"
}

## notify REs with precompose cmd, if re exist&active
# 1. get and validate WHC_RE active in tbus list, exclude repeater
# 2. run tbus cmd
notify_re()
{
	. /usr/share/libubox/jshn.sh
	json_init
	json_add_string "method" "whc_sync"
	json_add_string "payload" $jmsg
	json_str=`json_dump`

	echo $json_str

	MIMESH_LOGI " ubus call xq_info_sync_mqtt send_msg "$json_str" "
	ubus call xq_info_sync_mqtt send_msg "$json_str"
	return 1
}

mimesh_sync()
{
	local downup="$1"
	local fail=0

	local msg=""
	__info_compose

	MIMESH_LOGI " mimesh_sync note msg=<\"$msg\">"
	echo "`date +%Y%m%d-%H%M%S` mimesh_sync notice msg compose on CAP:" > "$FCFG_SYNC"
	echo "$msg_decode" >> "$FCFG_SYNC"
	echo "$msg" >> "$FCFG_SYNC"

	local cmd="whc_sync"
	local jmsg="$msg"
	notify_re
	ret=$?
	wifi update "$downup" &

	return "$ret"
}

mimesh_sync_lite()
{
	local fail=0
	local msg=""
	__info_compose

	MIMESH_LOGI " mimesh_sync_lite note msg=<\"$msg\">"
	echo "`date +%Y%m%d-%H%M%S` mimesh_sync_lite notice msg compose on CAP:" > "$FCFG_SYNC"
	echo "$msg_decode" >> "$FCFG_SYNC"
	echo "$msg" >> "$FCFG_SYNC"

	local cmd="whc_sync"
	local jmsg="$msg"
	notify_re
	return $?
}
