#!/bin/ash
echo "call miot_post " >> /dev/console

if [ -n "$3" ]; then
	name=$(echo $3 | sed s/[.]//g)
else
	name=$(echo $2 | sed s/[.]//g)
fi

mkdir -p /tmp/iot_attempt

last_attempt_time=$(cat /tmp/iot_attempt/iot_attempt_time_$name 2>/dev/null)
now_time=$(date +%s)

if [ -z "$last_attempt_time" ]; then
	timeout=99
else
	timeout=$(expr $now_time - $last_attempt_time)
fi

if [ $timeout -gt 30 ]; then
	echo $now_time > /tmp/iot_attempt/iot_attempt_time_$name
	if [ -n "$3" ]; then
		iotrelay -t 0 -m $1 -o $2 -I $3 &
	else
		iotrelay -t 0 -m $1 -I $2 &
	fi

	miot_status=$(uci -q get wireless.miot_2G.userswitch)
	led_status=$(uci -q get xiaoqiang.common.BLUE_LED)
	[ "${led_status:=1}" = "1" ] && [ "$miot_status" = "1" ] && {
		(xqled iot_discovery;sleep 20;/etc/init.d/miot restart) &
	}
fi
