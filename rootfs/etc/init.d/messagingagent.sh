#!/bin/sh /etc/rc.common

START=99

USE_PROCD=1
PROG=/usr/bin/messagingagent

num='2'
mqtts='1'
config_load misc
config_get num messagingagent thread_num "$num"
config_get mqtts messagingagent mqtts_flag "$mqtts"

start_service() {
	[ "$(uci -q get messaging.setting.enable)" = "0" ] && return
	/usr/sbin/check_accessInternet.sh "server" || return

	# start command
	procd_open_instance
	procd_set_param command "$PROG" --handler_threads "$num" --mqtts_enable "$mqtts"
	procd_set_param respawn
	procd_close_instance
	echo "start messagingagent ok."
}

stop_service() {
	# because messagingagant ignore SIGTERM, so we use SIGKILL
	killall -9 "$PROG"
	echo "stop messagingagent ok."
}
