#!/bin/sh

_log()
{
    logger -p warn -t re_macfilter " $1"
}

RE_IP="$1"
[ -z "$RE_IP" ] && {
	_log "add re lanmac to white macfilter failed, invalid ip <$@>"
	return
}

RE_MAC="$(cat /proc/net/arp|grep -w "$RE_IP"|awk '{print $4}')"
[ -z "$RE_MAC" ] && {
	_log "add re lanmac to white macfilter failed, invalid mac for <$RE_IP>"
	return
}

[ -x /usr/sbin/set_mesh_role_macfilter.sh ] && {
	/usr/sbin/set_mesh_role_macfilter.sh "$RE_MAC" &
	_log "add re lanmac<$RE_MAC> to white macfilter succeed"
}
