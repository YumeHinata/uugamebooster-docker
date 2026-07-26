#!/bin/ash

get_2_1() {
	ubus call trafficd wan | jsonfilter -e '@.rx_rate'
}

get_2_2() {
	ubus call trafficd wan | jsonfilter -e '@.tx_rate'
}

get_2_3() {
	ubus call trafficd hw '{"leaf":true,"filter":{"assoc":true}}' |
		jsonfilter -e '@.*' | awk '!/is_ap/ || /"is_ap":\s*0/' | wc -l
}

get_2_20() {
	ubus call trafficd hw '{"leaf":true,"filter":{"assoc":true}}' |
		jsonfilter -e '@.*.hw' |
		sed 's/\(.*\)/"\1"/' |
		jsonfilter -a -e "@"
}

set_2_24() {
	local mac time
	local val="$1"

	mac=$(echo "$val" | jsonfilter -e '@.mac')
	time=$(echo "$val" | jsonfilter -e '@.time')

	uci del_list miio_spec.2_24.cfg="${mac}_${time}"
	uci add_list miio_spec.2_24.cfg="${mac}_${time}"
	uci commit miio_spec.2_24
}
