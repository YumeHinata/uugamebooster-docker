#!/bin/sh

. /lib/xqled/xqled_common.sh

config_load "$THIS_MODULE"

led_func_list=$(__slist_get "$STYPE_FUNC")
color_func_list=$(__slist_get "$STYPE_COLOR")

xqled_func_act_pwm()
{
	func="$1"

	__validate_func "$func" || return $?

	color=$(config_get "$func" color)
	__validate_color "$color" || return $?

	trg=$(config_get "$func" trigger)

	[ -z "$color" ] || [ -z "$trg" ] && {
		LED_LOGE " xqled [$func] option inv $color, $trg"
		return 22
	}

	if [ "$LED_GLOBAL_CTL" = "0" ]; then
		VAL=0
		trg=$TRIGGER_OFF
		LED_LOGI " xqled ignore func [$func] for xiaoqiang.common.BLUE_LED "
	else
		R=$(config_get "$color" R)
		G=$(config_get "$color" G)
		B=$(config_get "$color" B)
		W=$(config_get "$color" W)

		VAL=$R
		VAL=$(((VAL << 8) + G))
		VAL=$(((VAL << 8) + B))
		VAL=$(((VAL << 8) + W))
	fi

	# if led is blinking disable blink first
	echo "none" > /sys/class/leds/rgb/trigger
	usleep 1000
	echo $VAL > /sys/class/leds/rgb/brightness

	if [ "$trg" = "$TRIGGER_BLINK" ]; then
		blinkon=$(config_get "$func" msec_on)
		blinkoff=$(config_get "$func" msec_off)
		[ $VAL -ne 0 ] && {
			echo "timer" > /sys/class/leds/rgb/trigger
			echo "$blinkon" > /sys/class/leds/rgb/delay_on
			echo "$blinkoff" > /sys/class/leds/rgb/delay_off
		}
	fi

	return $?
}
