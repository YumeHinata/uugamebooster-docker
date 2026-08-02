#!/bin/sh
###
# @Copyright (C), 2020-2022, Xiaomi CO., Ltd.:
# @Description: Used to configure ACL rules for the specified port
# @Author: Lin Hongqing
# @Date: 2022-09-28 10:00:07
# @Email: linhongqing@xiaomi.com
# @LastEditTime: 2022-09-28 14:22:02
# @LastEditors: Lin Hongqing
# @History: first version
###

readonly PSUCI="port_service"
readonly LOCK_FILE="/var/lock/game_port.lock"

log() {
	logger -t "game_port" -p $1 "$2"
}

ssdk_sh_wrapper() {
	local dev_id="$1"
	local cmd=$(mktemp)
	local output=$(mktemp)

	echo "device id set $dev_id" >> $cmd
	echo ${@:2} >> $cmd

	ssdk_sh run $cmd $output

	cat $output
	rm -rf $cmd $output
}

# set port as game port
# game port will has the highest priority
port_set_highest_pri() {
	local port=$1
	[ -z "${port}" ] && {
		log err "port_set_highest_pri: port is empty"
	}

	log info "set port $port as game port"

	ssdk_sh_wrapper 1 qos ptmode set 0 dscp enable
	ssdk_sh_wrapper 1 qos ptmode set 1 dscp enable
	ssdk_sh_wrapper 1 qos ptmode set 2 dscp enable
	ssdk_sh_wrapper 1 qos ptmode set 3 dscp enable
	ssdk_sh_wrapper 1 qos ptmode set 4 dscp enable
	ssdk_sh_wrapper 1 qos ptmode set 5 dscp enable
	ssdk_sh_wrapper 1 acl list create 1 0
	ssdk_sh_wrapper 1 acl rule add 1 0 1 no 0x0 0x0 mac no no no no no no no no no no no no no no no no no no no no no no no no no no no no no yes no no no no no yes 48 0x3f no yes 7 no no 0 0 no no no no no no no no no no no no no no no no no no no no 0
	ssdk_sh_wrapper 1 acl list bind 1 0 0 "$port"
	ssdk_sh_wrapper 1 acl status set enable

	ssdk_sh_wrapper 0 qos ptpriprece set 0 0 4 2 3 1 0 no no 0 0
	ssdk_sh_wrapper 0 qos ptpriprece set 1 2 6 1 5 4 4 no no 3 3
	ssdk_sh_wrapper 0 qos ptpriprece set 2 2 6 1 5 4 4 no no 3 3
	ssdk_sh_wrapper 0 qos dscpmap set 0 0xc0 0x0 0x0 0x7 0x0 0x0 0x0 no no no yes no 0x0
	ssdk_sh_wrapper 0 servcode config set 1 no 0 0xfffefcff 0xfbbfff 0 0 0 0 0 0 0

	log info "set port $port as game port finish"
}

# set port as normal port
# flush acl rule
port_flush_acl() {
	log info "flush acl rule"

	ssdk_sh_wrapper 1 acl list unbind 1 0 0 0
	ssdk_sh_wrapper 1 acl list unbind 1 0 0 1
	ssdk_sh_wrapper 1 acl list unbind 1 0 0 2
	ssdk_sh_wrapper 1 acl list unbind 1 0 0 3
	ssdk_sh_wrapper 1 acl list unbind 1 0 0 4
	ssdk_sh_wrapper 1 acl list unbind 1 0 0 5
	ssdk_sh_wrapper 1 acl rule del 1 0 1
	ssdk_sh_wrapper 1 acl list destroy 1
	ssdk_sh_wrapper 0 qos ptpriprece set 0 0 1 3 4 2 0 no no 0 0
	ssdk_sh_wrapper 0 qos ptpriprece set 1 2 3 1 6 5 5 no no 4 4
	ssdk_sh_wrapper 0 qos ptpriprece set 2 2 3 1 6 5 5 no no 4 4
	ssdk_sh_wrapper 0 qos dscpmap set 0 0xc0 0x0 0x0 0x0 0x0 0x0 0x0 no no no no no 0x0
	ssdk_sh_wrapper 0 servcode config set 1 no 0 0xfffefcff 0xffbfff 0 0 0 0 0 0 0
}

start() {
	local game_port game_phy_id
	local flag_enable=$(uci -q get "${PSUCI}".game.enable)

	log info "start game port, en:${flag_enable}"

	[ "${flag_enable}" = "1" ] && {
		game_port=$(uci -q get "${PSUCI}".game.ports)
		game_phy_id=$(port_map config get "$game_port" phy_id)
		port_set_highest_pri "${game_phy_id}"
	} || {
		# cleanup game port
		uci batch <<-EOF
			set "$PSUCI".game.ports=""
			commit "$PSUCI"
		EOF
		port_flush_acl
	}
}

stop() {
	port_flush_acl
}

# use lock to block concurrent access
trap "lock -u $LOCK_FILE" EXIT
lock $LOCK_FILE

# main
case "$1" in
start)
	# start game service
	start
	;;
stop)
	# stop game service
	stop
	;;
restart)
	# restart game service
	stop
	start
	;;
*)
	echo "Usage: $0 {start|stop|restart}"
	exit 1
	;;
esac
