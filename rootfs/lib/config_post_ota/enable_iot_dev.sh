#!/bin/sh

device_2g="wifi0"
device_5g="wifi1"
iot_dev2g_name="wl17"
iot_dev5g_name="wl16"

dev_macaddr_2g="$(getmac wl1)"
dev_macaddr_5g="$(getmac wl0)"
iot2g_macaddr="$(calcbssid -i4 -m $dev_macaddr_2g)"
iot5g_macaddr="$(calcbssid -i4 -m $dev_macaddr_5g)"

if [ "$(uci -q get misc.features.iot_dev)" != "1" ]; then
	uci set misc.features.iot_dev='1'
	uci set misc.wireless.wifi5_bk_2G="$iot_dev2g_name"
	uci set misc.wireless.wifi5_bk_5G="$iot_dev5g_name"
	uci commit misc
fi

if ! uci show wireless | grep iot_2g >>/dev/null; then
		uci -q batch <<-EOF >/dev/null
		set wireless.iot_2g=wifi-iface
		set wireless.iot_2g.device="$device_2g"
		set wireless.iot_2g.ifname="$iot_dev2g_name"
		set wireless.iot_2g.mode='ap'
		set wireless.iot_2g.network='lan'
		set wireless.iot_2g.encryption='mixed-psk'
		set wireless.iot_2g.hidden='0'
		set wireless.iot_2g.disabled='1'
		set wireless.iot_2g.iotwifi5mode='1'
		set wireless.iot_2g.macaddr="$iot2g_macaddr"

		set wireless.iot_5g=wifi-iface
		set wireless.iot_5g.device="$device_5g"
		set wireless.iot_5g.ifname="$iot_dev5g_name"
		set wireless.iot_5g.network='lan'
		set wireless.iot_5g.mode='ap'
		set wireless.iot_5g.encryption='mixed-psk'
		set wireless.iot_5g.hidden='0'
		set wireless.iot_5g.disabled='1'
		set wireless.iot_5g.iotwifi5mode='1'
		set wireless.iot_5g.macaddr="$iot5g_macaddr"
	EOF
	uci commit wireless
else
	uci -q set wireles.iot_2g.device="$device_2g"
	uci -q set wireles.iot_5g.device="$device_5g"
	uci -q set wireless.iot_2g.macaddr="$iot2g_macaddr"
	uci -q set wireless.iot_5g.macaddr="$iot5g_macaddr"
	uci commit wireless
fi