#!/bin/sh

[ -x /usr/sbin/xl2tpd ] || exit 0

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_l2tp_init_config() {
	proto_config_add_string "username"
	proto_config_add_string "password"
	proto_config_add_string "keepalive"
	proto_config_add_string "pppd_options"
	proto_config_add_boolean "ipv6"
	proto_config_add_int "mtu"
	proto_config_add_int "checkup_interval"
	proto_config_add_string "server"
	available=1
	no_device=1
	no_proto_task=1
	teardown_on_l3_link_down=1
}

proto_l2tp_setup() {
	local interface="$1"
	local optfile="/tmp/l2tp/options.${interface}"
	local ip serv_addr server host
	local host_save="/tmp/state/l2tp_host_save"
	local bind_wan="wan"

	json_get_var server server
	host="${server%:*}"
	for ip in $(resolveip -t 5 "$host"); do
		echo "$ip" | grep -sqE '^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$' && {
			( proto_add_host_dependency "$interface" "$ip" )
			echo "$ip" >> "$host_save"
			serv_addr=1
		}
	done
	[ -n "$serv_addr" ] || {
		echo "Could not resolve server address" >&2
		sleep 5
		proto_setup_failed "$interface"
		exit 1
	}

	# Start and wait for xl2tpd
	if [ ! -p /var/run/xl2tpd/l2tp-control -o -z "$(pidof xl2tpd)" ]; then
		/etc/init.d/xl2tpd restart

		local wait_timeout=0
		while [ ! -p /var/run/xl2tpd/l2tp-control ]; do
			wait_timeout=$(($wait_timeout + 1))
			[ "$wait_timeout" -gt 5 ] && {
				echo "Cannot find xl2tpd control file." >&2
				proto_setup_failed "$interface"
				exit 1
			}
			sleep 1
		done
	fi

	local ipv6 keepalive username password pppd_options mtu
	json_get_vars ipv6 keepalive username password pppd_options mtu
	[ "$ipv6" = 1 ] || ipv6=""

	local interval="${keepalive##*[, ]}"
	[ "$interval" != "$keepalive" ] || interval=5

	keepalive="${keepalive:+lcp-echo-interval $interval lcp-echo-failure ${keepalive%%[, ]*}}"
	username="${username:+user \"$username\" password \"$password\"}"
	ipv6="${ipv6:++ipv6}"

	[ -x /usr/sbin/mwan3 ] && bind_wan=$(/usr/sbin/mwan3 curr_wan ipv4)

	local wan_type=$(uci -q get network.$bind_wan.proto)
	local wan_mtu=1500
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

	mtu=`expr $wan_mtu - 40`
	mtu="${mtu:+mtu $mtu mru $mtu}"

	mkdir -p /tmp/l2tp
	cat <<EOF >"$optfile"
usepeerdns
nodefaultroute
ipparam "$interface"
ifname "l2tp-$interface"
ip-up-script /lib/netifd/ppp-up
ipv6-up-script /lib/netifd/ppp-up
ip-down-script /lib/netifd/ppp-down
ipv6-down-script /lib/netifd/ppp-down
# Don't wait for LCP term responses; exit immediately when killed.
lcp-max-terminate 0
$keepalive
$username
$ipv6
$mtu
holdoff 0
$pppd_options
EOF

	xl2tpd-control add l2tp-${interface} pppoptfile=${optfile} lns=${server} || {
		echo "xl2tpd-control: Add l2tp-$interface failed" >&2
		proto_setup_failed "$interface"
		exit 1
	}
	xl2tpd-control connect l2tp-${interface} || {
		echo "xl2tpd-control: Connect l2tp-$interface failed" >&2
		proto_setup_failed "$interface"
		exit 1
	}
}

proto_l2tp_teardown() {
	local interface="$1"
	local optfile="/tmp/l2tp/options.${interface}"
	local host_save="/tmp/state/l2tp_host_save"

	[ -f "$host_save" ] && {
		while read -r ip; do
			route delete "$ip"
		done < "$host_save"
		rm -rf "$host_save"
	}

	rm -f ${optfile}
	if [ -p /var/run/xl2tpd/l2tp-control ]; then
		xl2tpd-control remove l2tp-${interface} || {
			echo "xl2tpd-control: Remove l2tp-$interface failed" >&2
		}
	fi
	# Wait for interface to go down
        while [ -d /sys/class/net/l2tp-${interface} ]; do
		sleep 1
	done

	/etc/init.d/xl2tpd stop
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol l2tp
}
