#!/bin/ash

[ -z "$MAC" ] && exit 1

case "$EVENT" in
"1")
	msg=$(printf '{"tag":"sec_nic_connect","connected":true,"mac":"%s"}' "$MAC")
	milog.sh -m "$msg"
	;;
"0")
	msg=$(printf '{"tag":"sec_nic_connect","connected":false,"mac":"%s"}' "$MAC")
	milog.sh -m "$msg"
	;;
esac

exit 0
