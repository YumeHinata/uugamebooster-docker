#!/bin/sh

. /lib/functions.sh

THIS_MODULE="xqled"
STYPE_COLOR="color"
STYPE_FUNC="func"
TRIGGER_BLINK="blink"
TRIGGER_ON="on"
TRIGGER_OFF="off"

TAG="led"
LED_DBG=1

USE_BLUE_SWT=1
[ $USE_BLUE_SWT -gt 0 ] && LED_GLOBAL_CTL=$(uci -q get xiaoqiang.common.BLUE_LED)

led_led_list=""
led_func_list=""
color_func_list=""

LED_LOGI()
{
	[ "$LED_DBG" -gt 1 ] && sout="-s"
	logger "$sout" -p 2 -t "$TAG" "$1"
}

LED_LOGE()
{
	[ "$LED_DBG" -gt 1 ] && sout="-s"
	logger "$sout" -p 1 -t "$TAG" "$1"
}

LED_LOGD()
{
	[ "$LED_DBG" -gt 1 ] && {
		sout="-s"
		logger "$sout" -p 2 -t "$TAG" "$1"
	}
}

MS2UNIT()
{
	local val=$(($1 / 100))
	[ -z "$val" ] && val=1
	echo -n "$val"
}

# get the all te support func sect-name
__slist_get()
{
	stype="$1"
	list=""

	__func_get()
	{ append list "$1"; }

	config_foreach __func_get "$stype"
	echo -n "$list"
}

__validate_func()
{
	func="$1"

	# check func is support in the list
	list_contains led_func_list "$func" || {
		LED_LOGE "xqled func [$func] NOT defined!"
		return 11
	}

	return 0
}

__validate_led()
{
	local led="$1"

	# check func is support in the list
	list_contains led_led_list "$led" || {
		XQLED_LOGE " xqled name [$led] NOT defined!"
		return 12
	}

	return 0
}

__validate_color()
{
	local led=$1
	local color=$2

	if [ -z "$color" ]; then
		color=$1
		# check func is support in the list
		list_contains color_func_list "$color" || {
			LED_LOGE "xqled color [$color] NOT defined!"
			return 11
		}
	else
		local gg=$(config_get "$led" "$color")
		[ -n "$gg" ] || {
			XQLED_LOGE " xqled [$led] NOT define color[$color]"
			return 13
		}
	fi
}
