#!/bin/ash

connected=0
ipv6_addr=$(ubus call mobile status 2>/dev/null | jsonfilter -q -e "@['ipv6']")
[ -z "$ipv6_addr" ] && return
[ "$ipv6_addr" != "0:0:0:0:0:0:0:0" ] && connected=1
echo "$connected"
