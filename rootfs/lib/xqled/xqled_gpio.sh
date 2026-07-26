#!/bin/sh

. /lib/xqled/xqled_common.sh

config_load "$THIS_MODULE"

led_led_list=$(__slist_get "$STYPE_LED")
led_func_list=$(__slist_get "$STYPE_FUNC")

LED_ON=0
LED_OFF=1
LED_BLINK=2

# key arg, gpio, on/off, blink
__hal_led_on()
{
	gpio $1 0
}

__hal_led_off()
{
	gpio $1 1
}

__hal_led_blink()
{
	gpio l $2 $1
}

# led gpio controll
# xqled_hal_ctr 6 0   -- gpio 6 on
# xqled_hal_ctr 6 1   -- gpio 6 off
# xqled_hal_ctr 6 2 8 8 -- gpio 6 blink,on 800ms off 800ms
xqled_hal_ctr()
{
	local gpio="$1"
	local swt="$2"

	if [ "$swt" -eq "$LED_ON" ]; then
		__hal_led_on $1
	elif [ "$swt" -eq "$LED_OFF" ]; then
		__hal_led_off $1
	elif [ "$swt" -eq "$LED_BLINK" ]; then
		__hal_led_blink $1 $3 $4
	fi

	return $?
}

xqled_func_act_gpio()
{
	local func="$1"

	__validate_func "$func" || return $?

	local nled=$(config_get $func nled)
	__validate_led "$nled" || return $?

	local color=$(config_get $func color)
	__validate_color "$nled" "$color" || return $?

	local trg=$(config_get $func trigger)

	[ -z "$nled" -o -z "$color" -o -z "$trg" ] && {
		XQLED_LOGE " xqled [$func] option inv, $nled, $color, $trg"
		return 22
	}

	# check blue led switch
	if [ "$USE_BLUE_SWT" -gt 0 ]; then
		[ "$color" = "blue" -a "$LED_GLOBAL_CTL" = "0" -a "$trg" != "$TRIGGER_OFF" ] && {
			XQLED_LOGI "  xqled ignore func [$func] for xiaoqiang.common.BLUE_LED "
			trg="$TRIGGER_OFF"
		}
	fi

	# reset all gpio of led
	local black_gpios="$(config_get $nled black)"
	for gg in $black_gpios; do
		xqled_hal_ctr "$gg" $LED_OFF
	done

	# get gpio by led + color
	local gpios="$(config_get $nled $color)"

	for gg in $gpios; do
		if [ "$trg" = "$TRIGGER_BLINK" ]; then
			# blink
			config_get mson $func msec_on 800
			config_get msoff $func msec_off 800

			xqled_hal_ctr "$gg" $LED_BLINK $(MS2UNIT $mson) $(MS2UNIT $msoff)
		elif [ "$trg" = "$TRIGGER_ON" ]; then
			# led on
			xqled_hal_ctr "$gg" $LED_ON
		else
			# led off
			:
		fi
	done
	return $?
}
