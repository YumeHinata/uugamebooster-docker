#!/bin/ash

gLvl=6
gMsg=
gChk=

check_running() {
	# Check log daemon is running
	pgrep syslog-ng >/dev/null 2>&1
}

check_json() {
	echo "$1" | jsonfilter -e '@' >/dev/null 2>&1
}

usage() {
	cat <<-EOF
		Usage: $0 OPTION...
		generate milog msg.

		  -c      check message format before send
		  -m      message payload
		  -l      log level, 0 - 7, use 6 - info as default
	EOF
}

while getopts "m:l:ch" opt; do
	case "${opt}" in
	m)
		gMsg=${OPTARG}
		;;
	l)
		gLvl=${OPTARG}
		;;
	c)
		gChk=1
		;;
	h)
		usage
		exit
		;;
	\?)
		usage >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

if ! uci -q get milog.global.enable | grep -sqw 1; then
	# Do nothing if milog is disabled
	exit 0
fi

if [ -z "$gMsg" ]; then
	exit 2
fi

if ! echo "$gLvl" | grep -sqE '^[0-7]$'; then
	printf 'the format for log level is incorrect!\n' >&2
	exit 3
fi

if [ -n "$gChk" ]; then
	if ! check_json "$gMsg"; then
		printf 'the format for log message is incorrect!\n' >&2
		exit 4
	fi
fi

if check_running; then
	logger -p "local7.$gLvl" -t "milog" "$gMsg"
else
	echo "<$gLvl>$gMsg" >/dev/kmsg
fi
