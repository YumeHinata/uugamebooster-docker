#!/bin/sh
#echo -n "8.8.8.8"
. /lib/network/config.sh
_is_device_running() {
local device="$1"
[ -z "$device" ] && return 1
ifconfig "$device" | grep -q "RUNNING"
}
get_wanitf_ip() {
local DDNS_REGISTERED_IP=$1
local first_wan_ip
local use_privateip=$(uci -q get ddns.global.upd_privateip)
local first_wan_private_ip
network_flush_cache
for interface in `awk '/^config.*interface/{print$3}' /etc/config/network|tr "\'\"" " " `
do
[ "$interface" = "wan" -o ${interface:0:4} = "wan_" ] && {
ubus_call network.interface.$interface status
json_get_var up "up"
json_get_var device "device"
! _is_device_running "$device" && continue
[ "$up" = "1" ] && {
json_select "ipv4-address"
local __idx1=1
while json_is_a "$__idx1" object; do
json_select "$((__idx1++))"
json_get_var address "address"
json_select ".."
done
[ -n "$address" ] && {
[ -z "$DDNS_REGISTERED_IP" -o "$DDNS_REGISTERED_IP" = "$address" ] && {
echo -n "$address"
exit 0
}
[ "$use_privateip" != "1" ] && {
[ -z "$first_wan_private_ip" ] && first_wan_private_ip=$address
address=$(echo $address | grep -v -E "(^0|^10\.|^100\.6[4-9]\.|^100\.[7-9][0-9]\.|^100\.1[0-1][0-9]\.|^100\.12[0-7]\.|^127|^169\.254|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-1]\.|^192\.168)")
}
[ -n "$address" -a -z "$first_wan_ip" ] && first_wan_ip=$address
}
}
}
done
[ -n "$first_wan_ip" ] && {
echo -n "$first_wan_ip"
exit 0
}
[ "$use_privateip" != "1" -a -n "$first_wan_private_ip" ] && {
echo -n "$first_wan_private_ip"
exit 0
}
echo "Cannot get wan ip!" >&2
exit 2
}
get_wanitf_ip $@