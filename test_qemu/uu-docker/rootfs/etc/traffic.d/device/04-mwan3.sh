#!/bin/sh
# Ref env vars from /sbin/device_event_call

get_ip() {
	local mac="$1"

	ubus call trafficd hw "{\"hw\": \"$mac\"}" 2>/dev/null |
		jsonfilter -q -e '$.ip_list[0].ip'
}

[ -z "$MAC" ] && exit 1

if [ "1" = "$EVENT" ] || [ "3" = "$EVENT" ]; then
	ipaddr=$(get_ip "$MAC")
	[ -z "$ipaddr" ] && exit 1
fi

case "$EVENT" in
"1" | "3")
	/usr/sbin/mwan3 add_device "$MAC" "$ipaddr" "ipv4"
	;;
*)
	/usr/sbin/mwan3 del_device "$MAC"
	;;
esac

exit 0
