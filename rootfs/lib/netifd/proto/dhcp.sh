#!/bin/sh

[ -L /sbin/udhcpc ] || exit 0

. /lib/functions.sh
. ../netifd-proto.sh
init_proto "$@"

proto_dhcp_init_config() {
	renew_handler=1
	no_l3dev=1

	proto_config_add_string 'ipaddr:ipaddr'
	proto_config_add_string 'hostname:hostname'
	proto_config_add_string clientid
	proto_config_add_string vendorid
	proto_config_add_boolean 'broadcast:bool'
	proto_config_add_boolean 'norelease:bool'
	proto_config_add_string 'reqopts:list(string)'
	proto_config_add_boolean 'defaultreqopts:bool'
	proto_config_add_string iface6rd
	proto_config_add_array 'sendopts:list(string)'
	proto_config_add_boolean delegate
	proto_config_add_string zone6rd
	proto_config_add_string zone
	proto_config_add_string mtu6rd
	proto_config_add_string customroutes
	proto_config_add_boolean classlessroute
}

proto_dhcp_add_sendopts() {
	[ -n "$1" ] && append "$3" "-x $1"
}

proto_dhcp_setup() {
	local config="$1"
	local iface="$2"

	local ipaddr hostname clientid vendorid broadcast norelease reqopts defaultreqopts iface6rd sendopts delegate zone6rd zone mtu6rd customroutes classlessroute
	json_get_vars ipaddr hostname clientid vendorid broadcast norelease reqopts defaultreqopts iface6rd delegate zone6rd zone mtu6rd customroutes classlessroute

	local opt dhcpopts
	for opt in $reqopts; do
		append dhcpopts "-O $opt"
	done

	hostname=$(uci -q get misc.hardware.dhcp_hostname)
	[ -z "$hostname" ] && {
		local  model=$(uci -q get misc.hardware.model)
		[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)
		hostname="MiWiFi-$model"
	}

	json_for_each_item proto_dhcp_add_sendopts sendopts dhcpopts

	[ "$defaultreqopts" = 0 ] && defaultreqopts="-o" || defaultreqopts=
	[ "$broadcast" = 1 ] && broadcast="-B" || broadcast=
	[ "$norelease" = 1 ] && norelease="" || norelease="-R"
	[ -n "$clientid" ] && clientid="-x 0x3d:${clientid//:/}" || clientid="-C"
	[ -n "$iface6rd" ] && proto_export "IFACE6RD=$iface6rd"
	[ -n "$iface6rd" -a "$iface6rd" != 0 -a -f /lib/netifd/proto/6rd.sh ] && append dhcpopts "-O 212"
	[ -n "$zone6rd" ] && proto_export "ZONE6RD=$zone6rd"
	[ -n "$zone" ] && proto_export "ZONE=$zone"
	[ -n "$mtu6rd" ] && proto_export "MTU6RD=$mtu6rd"
	[ -n "$customroutes" ] && proto_export "CUSTOMROUTES=$customroutes"
	[ "$delegate" = "0" ] && proto_export "IFACE6RD_DELEGATE=0"
	# Request classless route option (see RFC 3442) by default
	[ "$classlessroute" = "0" ] || append dhcpopts "-O 121 -O 249"

	[ -x /usr/sbin/getIspName ] && [ "$(/usr/sbin/getIspName)" = "CUCC" ] && {
		local model=$(getIspModel)
		local model_hex=$(echo -n ${model} | hexdump -v -e '1/1 "%02X"')
		local model_len=$(echo ${model} | awk '{printf("%02X",length($0))}')
		local vendor="Xiaomi"
		local vendor_hex=$(echo -n ${vendor} | hexdump -v -e '1/1 "%02X"')
		local vendor_len=$(echo ${vendor} | awk '{printf("%02d",length($0))}')
		local category="WlanAP"
		local category_hex=$(echo -n ${category} | hexdump -v -e '1/1 "%02X"')
		local category_len=$(echo ${category} | awk '{printf("%02X",length($0))}')
		vendorid="000101${vendor_len}${vendor_hex}02${category_len}${category_hex}03${model_len}${model_hex}"
	}

	proto_export "INTERFACE=$config"
	if [ -x "/usr/sbin/getIspName" ] && [ "$(/usr/sbin/getIspName)" = "CUCC" ]; then
		proto_run_command "$config" udhcpc \
			-a \
			-p /var/run/udhcpc-$iface.pid \
			-s /lib/netifd/dhcp.script \
			-O 33 \
			-f -t 0 -i "$iface" \
			${ipaddr:+-r $ipaddr} \
			${hostname:+-x "hostname:$hostname"} \
			${vendorid:+-x "0x3c:$vendorid" -V ""} \
			$clientid $defaultreqopts $broadcast $release $dhcpopts
	else
		proto_run_command "$config" udhcpc \
			-a \
			-p /var/run/udhcpc-$iface.pid \
			-s /lib/netifd/dhcp.script \
			-O 33 \
			-f -t 0 -i "$iface" \
			${ipaddr:+-r $ipaddr} \
			${hostname:+-x "hostname:$hostname"} \
			${vendorid:+-V "$vendorid"} \
			$clientid $defaultreqopts $broadcast $release $dhcpopts
	fi
}

proto_dhcp_renew() {
	local interface="$1"
	# SIGUSR1 forces udhcpc to renew its lease
	local sigusr1="$(kill -l SIGUSR1)"
	[ -n "$sigusr1" ] && proto_kill_command "$interface" $sigusr1
}

proto_dhcp_teardown() {
	local interface="$1"
	proto_kill_command "$interface"
}

add_protocol dhcp
