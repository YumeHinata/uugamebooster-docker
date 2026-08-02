#!/bin/sh

. /lib/functions.sh
. ../netifd-proto.sh
init_proto "$@"

proto_dhcpv6_init_config() {
	renew_handler=1

	proto_config_add_string 'reqaddress:or("try","force","none")'
	proto_config_add_string 'reqprefix:or("auto","no",range(0, 64))'
	proto_config_add_string clientid
	proto_config_add_string 'reqopts:list(uinteger)'
	proto_config_add_string 'defaultreqopts:bool'
	proto_config_add_string 'noslaaconly:bool'
	proto_config_add_string 'forceprefix:bool'
	proto_config_add_string 'extendprefix:bool'
	proto_config_add_string 'norelease:bool'
	proto_config_add_string 'noserverunicast:bool'
	proto_config_add_string 'noclientfqdn:bool'
	proto_config_add_string 'noacceptreconfig:bool'
	proto_config_add_array 'ip6prefix:list(ip6addr)'
	proto_config_add_string iface_dslite
	proto_config_add_string zone_dslite
	proto_config_add_string encaplimit_dslite
	proto_config_add_string iface_map
	proto_config_add_string zone_map
	proto_config_add_string encaplimit_map
	proto_config_add_string iface_464xlat
	proto_config_add_string zone_464xlat
	proto_config_add_string zone
	proto_config_add_string 'ifaceid:ip6addr'
	proto_config_add_string "userclass"
	proto_config_add_string "vendorclass"
	proto_config_add_array "sendopts:list(string)"
	proto_config_add_boolean delegate
	proto_config_add_int "soltimeout"
	proto_config_add_boolean fakeroutes
	proto_config_add_boolean sourcefilter
	proto_config_add_boolean keep_ra_dnslifetime
	proto_config_add_int "ra_holdoff"
	proto_config_add_int "verbosity"
	proto_config_add_int "passthrough"
}

proto_dhcpv6_add_prefix() {
	append "$3" "$1"
}

proto_dhcpv6_add_sendopts() {
	[ -n "$1" ] && append "$3" "-x$1"
}

proto_dhcpv6_load_passthrough() {
	local wan6_iface="$1"

	local kernel_ver=$(uname -r)
	local pass_ifname=$(uci -q get network.$wan6_iface.pass_ifname)
	local macaddr

	[ -d /sys/module/passthrough ] || insmod passthrough
	macaddr=$(cat /sys/class/net/br-lan/address)

	/usr/bin/pconfig add "$pass_ifname" "${pass_ifname}_6"
	ifconfig "${pass_ifname}_6" hw ether "$macaddr"
	ifconfig "${pass_ifname}_6" up
	brctl addif br-lan "${pass_ifname}_6"

	. /lib/miwifi/miwifi_core_libs.sh
	network_accel_hook "ipv6_passthrough" "load"
}

proto_dhcpv6_vendor_class_unicom_spec() {
	# 只有联通需要上报option-16
	# 厂商名称(固定)
	local vendor="Xiaomi"
	local vendor_len=$(echo ${vendor} | awk '{printf("%02X",length($0))}')
	local vendor_hex=$(echo -n ${vendor} | hexdump -v -e '1/1 "%02X"')
	# 组网路由器类型(固定)
	local category="WlanAP"
	local category_len=$(echo ${category} | awk '{printf("%02X",length($0))}')
	local category_hex=$(echo -n ${category} | hexdump -v -e '1/1 "%02X"')
	# 组网路由器型号
	local  model=$(getIspModel)
	[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)
	local model_len=$(echo ${model} | awk '{printf("%02X", length($0))}')
	local model_hex=$(echo -n ${model} | hexdump -v -e '1/1 "%02X"')

	local vendor_class_data="01${vendor_len}${vendor_hex}02${category_len}${category_hex}03${model_len}${model_hex}"
	local vendor_class_len=$(echo $vendor_class_data | awk '{printf("%04X", length($0)/2)}')
	# Enterprise Code 客户指定，暂为0x0001
	local option_16_data="00000001${vendor_class_len}${vendor_class_data}"
	echo $option_16_data
}

miwifi_init_clientid() {
	local wan6_iface="$1"
	local wan_iface="${wan6_iface/6/}"
	local wan_mac=$(getmac $wan_iface)

	[ -n "$wan_mac" ] && {
		local clientid="00030001${wan_mac//:/}"
		uci -q batch <<-EOF
			set network.${wan6_iface}.clientid="${clientid}"
			commit network
		EOF
	}
}

__force_enable_ifname_ipv6() {
	local ifname="$1"
	local try_count=3

	[ -z "$ifname" ] && return
	local is_ether=$(ip addr show dev $ifname | grep -q 'link/ether' && echo 1)

	if [ "$is_ether" = "1" ]; then
		while [ $try_count -gt 0 ]; do
			echo 1 > /proc/sys/net/ipv6/conf/$ifname/disable_ipv6
			echo 0 > /proc/sys/net/ipv6/conf/$ifname/disable_ipv6
			sleep 1
			local ipv6_addr=$(ip -6 addr show dev $ifname | grep -E 'inet6' | grep -E 'scope link' | grep 'fe80::')
			[ -n "$ipv6_addr" ] && break
			try_count=$((try_count - 1))
		done
	else
		echo 0 > /proc/sys/net/ipv6/conf/$ifname/disable_ipv6
	fi
}

proto_dhcpv6_setup() {
	local config="$1"
	local iface="$2"

	local reqaddress reqprefix clientid reqopts defaultreqopts noslaaconly forceprefix extendprefix norelease noserverunicast noclientfqdn noacceptreconfig ip6prefix ip6prefixes iface_dslite iface_map iface_464xlat ifaceid userclass vendorclass sendopts delegate zone_dslite zone_map zone_464xlat zone encaplimit_dslite encaplimit_map soltimeout fakeroutes sourcefilter keep_ra_dnslifetime ra_holdoff verbosity passthrough
	json_get_vars reqaddress reqprefix clientid reqopts defaultreqopts noslaaconly forceprefix extendprefix norelease noserverunicast noclientfqdn noacceptreconfig iface_dslite iface_map iface_464xlat ifaceid userclass vendorclass delegate zone_dslite zone_map zone_464xlat zone encaplimit_dslite encaplimit_map soltimeout fakeroutes sourcefilter keep_ra_dnslifetime ra_holdoff verbosity passthrough
	json_for_each_item proto_dhcpv6_add_prefix ip6prefix ip6prefixes

	[ -x /usr/sbin/getIspName ] && [ "$(/usr/sbin/getIspName)" = "CUCC" ] && {
		local vendor=$(proto_dhcpv6_vendor_class_unicom_spec)
		if [ -n "$vendor" ]; then
			vendorclass=${vendor}
		fi
	}

	[ -z "$clientid" ] && {
		miwifi_init_clientid "$config"
		clientid=$(uci -q get network.$config.clientid)
	}

	# Configure
	local opts=""
	[ -n "$reqaddress" ] && append opts "-N$reqaddress"

	[ -z "$reqprefix" -o "$reqprefix" = "auto" ] && reqprefix=0
	[ "$reqprefix" != "no" ] && append opts "-P$reqprefix"

	[ -n "$clientid" ] && append opts "-c$clientid"

	[ "$defaultreqopts" = "0" ] && append opts "-R"

	[ "$noslaaconly" = "1" ] && append opts "-S"

	[ "$forceprefix" = "1" ] && append opts "-F"

	[ "$norelease" = "1" ] && append opts "-k"

	[ "$noserverunicast" = "1" ] && append opts "-U"

	[ "$noclientfqdn" = "1" ] && append opts "-f"

	[ "$noacceptreconfig" = "1" ] && append opts "-a"

	[ -n "$ifaceid" ] && append opts "-i$ifaceid"

	[ -n "$vendorclass" ] && append opts "-V$vendorclass"

	[ -n "$userclass" ] && append opts "-u$userclass"

	[ "$keep_ra_dnslifetime" = "1" ] && append opts "-L"

	[ -n "$ra_holdoff" ] && append opts "-m$ra_holdoff"

	[ -n "$verbosity" ] && append opts "-v"
	if [ "$(bdata get CountryCode)" = "JP" ]; then
		append opts "-g"
	fi

	local opt
	for opt in $reqopts; do
		append opts "-r$opt"
	done

	json_for_each_item proto_dhcpv6_add_sendopts sendopts opts

	append opts "-t${soltimeout:-120}"

	[ -n "$ip6prefixes" ] && proto_export "USERPREFIX=$ip6prefixes"
	[ -n "$iface_dslite" ] && proto_export "IFACE_DSLITE=$iface_dslite"
	[ -n "$iface_map" ] && proto_export "IFACE_MAP=$iface_map"
	[ -n "$iface_464xlat" ] && proto_export "IFACE_464XLAT=$iface_464xlat"
	[ "$delegate" = "0" ] && proto_export "IFACE_DSLITE_DELEGATE=0"
	[ "$delegate" = "0" ] && proto_export "IFACE_MAP_DELEGATE=0"
	[ -n "$zone_dslite" ] && proto_export "ZONE_DSLITE=$zone_dslite"
	[ -n "$zone_map" ] && proto_export "ZONE_MAP=$zone_map"
	[ -n "$zone_464xlat" ] && proto_export "ZONE_464XLAT=$zone_464xlat"
	[ -n "$zone" ] && proto_export "ZONE=$zone"
	[ -n "$encaplimit_dslite" ] && proto_export "ENCAPLIMIT_DSLITE=$encaplimit_dslite"
	[ -n "$encaplimit_map" ] && proto_export "ENCAPLIMIT_MAP=$encaplimit_map"
	[ "$fakeroutes" != "0" ] && proto_export "FAKE_ROUTES=1"
	[ "$sourcefilter" = "0" ] && proto_export "NOSOURCEFILTER=1"
	[ "$extendprefix" = "1" ] && proto_export "EXTENDPREFIX=1"

	[ "$passthrough" = "1" ] && proto_dhcpv6_load_passthrough "$config"

	use_tempaddr=$(uci -q get ipv6.$config.use_tempaddr)
	if [ "$use_tempaddr" = "1" ]; then
		echo 2 > /proc/sys/net/ipv6/conf/$iface/accept_ra
		echo 2 > /proc/sys/net/ipv6/conf/$iface/use_tempaddr
		echo 0 > /proc/sys/net/ipv6/conf/$iface/accept_ra_defrtr
	else
		#default config
		echo 0 > /proc/sys/net/ipv6/conf/$iface/accept_ra
		echo 0 > /proc/sys/net/ipv6/conf/$iface/use_tempaddr
		echo 1 > /proc/sys/net/ipv6/conf/$iface/accept_ra_defrtr
	fi

	__force_enable_ifname_ipv6 $iface

	proto_export "INTERFACE=$config"
	proto_run_command "$config" odhcp6c \
		-s /lib/netifd/dhcpv6.script \
		$opts $iface
}

proto_dhcpv6_renew() {
	local interface="$1"
	# SIGUSR1 forces odhcp6c to renew its lease
	local sigusr1="$(kill -l SIGUSR1)"
	[ -n "$sigusr1" ] && proto_kill_command "$interface" $sigusr1
}

proto_dhcpv6_teardown() {
	local interface="$1"
	proto_kill_command "$interface"
}

add_protocol dhcpv6
