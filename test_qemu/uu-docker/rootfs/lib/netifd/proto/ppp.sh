#!/bin/sh

[ -x /usr/sbin/pppd ] || exit 0

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

ppp_select_ipaddr()
{
	local subnets=$1
	local res
	local res_mask

	for subnet in $subnets; do
		local addr="${subnet%%/*}"
		local mask="${subnet#*/}"

		if [ -n "$res_mask" -a "$mask" != 32 ]; then
			[ "$mask" -gt "$res_mask" ] || [ "$res_mask" = 32 ] && {
				res="$addr"
				res_mask="$mask"
			}
		elif [ -z "$res_mask" ]; then
			res="$addr"
			res_mask="$mask"
		fi
	done

	echo "$res"
}

ppp_exitcode_tostring()
{
	local errorcode=$1
	[ -n "$errorcode" ] || errorcode=5

	case "$errorcode" in
		0) echo "OK" ;;
		1) echo "FATAL_ERROR" ;;
		2) echo "OPTION_ERROR" ;;
		3) echo "NOT_ROOT" ;;
		4) echo "NO_KERNEL_SUPPORT" ;;
		5) echo "USER_REQUEST" ;;
		6) echo "LOCK_FAILED" ;;
		7) echo "OPEN_FAILED" ;;
		8) echo "CONNECT_FAILED" ;;
		9) echo "PTYCMD_FAILED" ;;
		10) echo "NEGOTIATION_FAILED" ;;
		11) echo "PEER_AUTH_FAILED" ;;
		12) echo "IDLE_TIMEOUT" ;;
		13) echo "CONNECT_TIME" ;;
		14) echo "CALLBACK" ;;
		15) echo "PEER_DEAD" ;;
		16) echo "HANGUP" ;;
		17) echo "LOOPBACK" ;;
		18) echo "INIT_FAILED" ;;
		19) echo "AUTH_TOPEER_FAILED" ;;
		20) echo "TRAFFIC_LIMIT" ;;
		21) echo "CNID_AUTH_FAILED";;
		*) echo "UNKNOWN_ERROR" ;;
	esac
}

ppp_generic_init_config() {
	proto_config_add_string username
	proto_config_add_string password
	proto_config_add_string keepalive
	proto_config_add_boolean keepalive_adaptive
	proto_config_add_int demand
	proto_config_add_string pppd_options
	proto_config_add_string 'connect:file'
	proto_config_add_string 'disconnect:file'
	proto_config_add_string ipv4
	proto_config_add_string ipv6
	proto_config_add_boolean authfail
	proto_config_add_int mru
	proto_config_add_string pppname
	proto_config_add_string unnumbered
	proto_config_add_boolean persist
	proto_config_add_int maxfail
	proto_config_add_int holdoff
}

ppp_generic_setup() {
	local config="$1"; shift
	local localip
	local force_disable_ipv6=$(uci -q get network.$config.force_disable_ipv6)

	json_get_vars ipv4 ipv6 ip6table demand keepalive keepalive_adaptive username password pppd_options pppname unnumbered persist maxfail peerdns

	if [ "$ipv4" = "0" ]; then
		ipv4="0"
	else
		ipv4=""
	fi

	if [ "$ipv6" = "auto" -a "$force_disable_ipv6" != "1" ]; then
		ipv6=1
		autoipv6=1
	else
		ipv6=""
		autoipv6=0
	fi

	if [ "${demand:-0}" -gt 0 ]; then
		demand="precompiled-active-filter /etc/ppp/filter demand idle $demand"
	else
		demand=""
	fi
	if [ -n "$persist" ]; then
		[ "${persist}" -lt 1 ] && persist="nopersist" || persist="persist"
	fi
	if [ -z "$maxfail" ]; then
		[ "$persist" = "persist" ] && maxfail=0 || maxfail=1
	fi
	[ -n "$mru" ] || json_get_var mru mru
	[ -n "$pppname" ] || pppname="${proto:-ppp}-$config"
	[ -n "$unnumbered" ] && {
		local subnets
		( proto_add_host_dependency "$config" "" "$unnumbered" )
		network_get_subnets subnets "$unnumbered"
		localip=$(ppp_select_ipaddr "$subnets")
		[ -n "$localip" ] || {
			proto_block_restart "$config"
			return
		}
	}

	[ -n "$keepalive" ] || keepalive="5 20"

	local lcp_failure="${keepalive%%[, ]*}"
	local lcp_interval="${keepalive##*[, ]}"
	local lcp_adaptive="lcp-echo-adaptive"
	[ "${lcp_failure:-0}" -lt 1 ] && lcp_failure=""
	[ "$lcp_interval" != "$keepalive" ] || lcp_interval=5
	[ "${keepalive_adaptive:-1}" -lt 1 ] && lcp_adaptive=""
	[ -n "$connect" ] || json_get_var connect connect
	[ -n "$disconnect" ] || json_get_var disconnect disconnect

	proto_run_command "$config" /usr/sbin/pppd \
		nodetach ipparam "$config" \
		ifname "$pppname" \
		${localip:+$localip:} \
		${lcp_failure:+lcp-echo-interval $lcp_interval lcp-echo-failure $lcp_failure $lcp_adaptive} \
		${ipv4:+-ip} \
		${ipv6:++ipv6} \
		${autoipv6:+set AUTOIPV6=$autoipv6} \
		${ip6table:+set IP6TABLE=$ip6table} \
		${peerdns:+set PEERDNS=$peerdns} \
		nodefaultroute \
		usepeerdns \
		$demand $persist maxfail $maxfail \
		${holdoff:+holdoff "$holdoff"} \
		${username:+user "$username" password "$password"} \
		${connect:+connect "$connect"} \
		${disconnect:+disconnect "$disconnect"} \
		ip-up-script /lib/netifd/ppp-up \
		ipv6-up-script /lib/netifd/ppp6-up \
		ip-down-script /lib/netifd/ppp-down \
		ipv6-down-script /lib/netifd/ppp-down \
		${mru:+mtu $mru mru $mru} \
		"$@" $pppd_options
}

ppp_generic_teardown() {
	local interface="$1"
	local errorstring=$(ppp_exitcode_tostring $ERROR)

	case "$ERROR" in
		0)
		;;
		2)
			proto_notify_error "$interface" "$errorstring"
			proto_block_restart "$interface"
		;;
		11|19)
			json_get_var authfail authfail
			proto_notify_error "$interface" "$errorstring"
			if [ "${authfail:-0}" -gt 0 ]; then
				proto_block_restart "$interface"
			fi
		;;
		*)
			proto_notify_error "$interface" "$errorstring"
		;;
	esac

	proto_kill_command "$interface"
}

# PPP on serial device

proto_ppp_init_config() {
	proto_config_add_string "device"
	ppp_generic_init_config
	no_device=1
	available=1
	lasterror=1
}

proto_ppp_setup() {
	local config="$1"

	json_get_var device device
	ppp_generic_setup "$config" "$device"
}

proto_ppp_teardown() {
	ppp_generic_teardown "$@"
}

proto_pppoe_init_config() {
	ppp_generic_init_config
	proto_config_add_string "ac"
	proto_config_add_string "service"
	proto_config_add_string "host_uniq"
	lasterror=1
}

proto_pppoe_setup() {
	local config="$1"    # 'wan' or 'wan_2'
	local iface="$2"     # real interface, like 'eth0'
	local specdial_enable specdial last_state
	local f_specdial="/tmp/state/pppoe_specdial_$config"
	local f_last_state="/tmp/state/pppoe_last_error_$config"

	for module in slhc ppp_generic pppox pppoe; do
		/sbin/insmod $module 2>&- >&-
	done

	json_get_var mru mru
	mru="${mru:-1492}"

	json_get_var ac ac
	json_get_var service service
	json_get_var host_uniq host_uniq

	specdial_enable=$(uci -q get network."$config".special)
	[ "1" = "$specdial_enable" ] && [ -f "$f_specdial" ] && {
		specdial=$(cat "$f_specdial")
	}
	[ -f "$f_last_state" ] && last_state=$(cat "$f_last_state")
	[ "$last_state" = "11" ] || [ "$last_state" = "19" ] && holdoff=30 || holdoff=2

	ppp_generic_setup "$config" \
		plugin rp-pppoe.so \
		plugin specdial.so \
		${ac:+rp_pppoe_ac "$ac"} \
		${service:+rp_pppoe_service "$service"} \
		${specdial:+specdial "$specdial"} \
		"nic-$iface"
}

proto_pppoe_teardown() {
	local config="$1"    # 'wan' or 'wan_2'
	local specdial
	local f_last_state="/tmp/state/pppoe_last_error_$config"
	local f_specdial="/tmp/state/pppoe_specdial_$config"

	# save pppoe last error
	[ -f "$f_last_state" ] || mkdir -p '/tmp/state';
	echo "$ERROR" > "$f_last_state"
	case "$ERROR" in
		11|19) # auth failed error code
		for i in 1 6 7; do
			specdial=$(cat "$f_specdial" 2>/dev/null)
			if [ "$specdial" = "$i" ]; then
				echo -n > "$f_specdial"
				continue
			fi
			if [ -z "$specdial" ]; then
				echo $i > "$f_specdial"
				break
			fi
		done
		;;
		*)
		rm -rf "$f_specdial"
		;;
	esac
	ppp_generic_teardown "$@"
}

proto_pppoa_init_config() {
	ppp_generic_init_config
	proto_config_add_int "atmdev"
	proto_config_add_int "vci"
	proto_config_add_int "vpi"
	proto_config_add_string "encaps"
	no_device=1
	available=1
	lasterror=1
}

proto_pppoa_setup() {
	local config="$1"
	local iface="$2"

	for module in slhc ppp_generic pppox pppoatm; do
		/sbin/insmod $module 2>&- >&-
	done

	json_get_vars atmdev vci vpi encaps

	case "$encaps" in
		1|vc) encaps="vc-encaps" ;;
		*) encaps="llc-encaps" ;;
	esac

	ppp_generic_setup "$config" \
		plugin pppoatm.so \
		${atmdev:+$atmdev.}${vpi:-8}.${vci:-35} \
		${encaps}
}

proto_pppoa_teardown() {
	ppp_generic_teardown "$@"
}

proto_pptp_init_config() {
	ppp_generic_init_config
	proto_config_add_string "server"
	proto_config_add_string "interface"
	available=1
	no_device=1
	lasterror=1
}

proto_pptp_setup() {
	local config="$1"
	local iface="$2"
	local bind_wan="wan"
	[ -x /usr/sbin/mwan3 ] && bind_wan=$(/usr/sbin/mwan3 curr_wan ipv4)

	local wan_type=$(uci -q get network.$bind_wan.proto)
	local wan_mtu=1500
	local host_save="/tmp/state/pptp_host_save"

	case "$wan_type" in
		"pppoe")
			wan_mtu=$(uci -q get network.$bind_wan.mru)
			[ -z "$wan_mtu" ] && wan_mtu=1480
			;;
		*)
			wan_mtu=$(uci -q get network.$bind_wan.mtu)
			[ -z "$wan_mtu" ] && wan_mtu=1500
			;;
	esac

	local is_wan_vlan_enable=$(uci -q get vlan_service.Internet.enable)
	[ "$is_wan_vlan_enable" = "1" ] && wan_mtu=`expr $wan_mtu - 4`

	mru=`expr $wan_mtu - 40`

	local ip serv_addr server interface
	json_get_vars interface server
	[ -n "$server" ] && {
		for ip in $(resolveip -t 5 "$server"); do
			echo "$ip" | grep -sqE '^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$' && {
				( proto_add_host_dependency "$config" "$ip" $interface )
				echo "$ip" >> "$host_save"
				serv_addr=1
			}
		done
	}
	[ -n "$serv_addr" ] || {
		echo "Could not resolve server address"
		sleep 5
		proto_setup_failed "$config"
		exit 1
	}

	local load
	for module in slhc ppp_generic ppp_async ppp_mppe ip_gre gre pptp; do
		grep -q "^$module " /proc/modules && continue
		/sbin/insmod $module 2>&- >&-
		load=1
	done
	[ "$load" = "1" ] && sleep 1

	holdoff=0

	ppp_generic_setup "$config" \
		plugin pptp.so \
		pptp_server $server \
		file /etc/ppp/options.pptp
}

proto_pptp_teardown() {
	local host_save="/tmp/state/pptp_host_save"

	[ -f "$host_save" ] && {
		while read -r ip; do
			route delete "$ip"
		done < "$host_save"
		rm -rf "$host_save"
	}
	ppp_generic_teardown "$@"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol ppp
	[ -f /usr/lib/pppd/*/rp-pppoe.so ] && add_protocol pppoe
	[ -f /usr/lib/pppd/*/pppoatm.so ] && add_protocol pppoa
	[ -f /usr/lib/pppd/*/pptp.so ] && add_protocol pptp
}
