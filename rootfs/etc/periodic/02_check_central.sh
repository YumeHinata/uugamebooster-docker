#!/bin/sh

[ "$1" != "5min" ] && exit

[ "$(cat /proc/xiaoqiang/ft_mode)" = "1" ] && exit
[ "$(cat /proc/uptime | awk -F. '{print$1}')" -lt "600" ] && exit
[ "$(uci -q get miio_ot.ot.bound)" != "1" ] && exit
[ -n "$(pidof central_software_pack.sh)" ] && exit

count=$(nvram get other_format_count)
[ -z "$count" ] && count=0

for i in $(seq 3); do
    [ -f "/tmp/central_normal_stop" ] && exit

    /data/docker/docker ps | grep -qsw miot_central && {
        [ "$count" -gt 0 ] && {
            nvram set other_format_count=0
            nvram commit
        }
        exit
    }
    sleep 20
done


count=$((count + 1))

[ "$count" -le 3 ] && {
    echo "FATAL: Central container not found, mtd erase other, count:$count." > /dev/console
    nvram set other_format_count=$count
    nvram commit

    reboot
}
