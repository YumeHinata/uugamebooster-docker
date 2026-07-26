#!/bin/ash

gMethod=
gParams=

. /usr/share/libubox/jshn.sh
[ -f "/etc/miio_spec/init.sh" ] && . /etc/miio_spec/init.sh

usage() {
	cat <<-EOF
		Usage: $0 OPTION...
		MIIO Spec data process

		  -m      method name
		  -p      params data
	EOF
}

while getopts "m:p:h" opt; do
	case "${opt}" in
	m)
		gMethod=${OPTARG}
		;;
	p)
		gParams=${OPTARG}
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

if [ -z "$gMethod" ]; then
	printf "Method not specified!\n" >&2
	exit 2
fi

case "$gMethod" in
"event" | "properties_changed")
	data=$("$gMethod" "$gParams")
	json_init
	json_add_string "msg" "$data"
	reply=$(json_dump)
	json_cleanup

	ubus send miio_proxy "$reply"
	;;
\?)
	printf "%s not supported!\n" "$gMethod" >&2
	exit 3
	;;
esac
