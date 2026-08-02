#!/bin/sh

. /lib/xqled/xqled_common.sh

config_load "$THIS_MODULE"

init_env() {
	local name=$(config_get $1 name)
	local method=$(config_get $1 method)
	local val=$(config_get $1 value)
	[ -n "$method" ] && {
		val=$(eval $method)
	}

	[ -z "$name" -o -z "$val" ] && {
		LED_LOGE " init_env: name or val is null"
		return 1
	}
	eval export $name=$val
}

do_action() {
	local command=$(config_get $1 command)
	local led=$(config_get $1 led)
	local options=$(config_get $1 options)
	local option=""
	local val=""

	# if have command, just run it and return
	[ -n "$command" ] && {
		LED_LOGD " do_action:command of $1 is $command"
		eval $command
		return $?
	}

	[ -f /sys/class/leds/$led/brightness ] || {
		LED_LOGE " do_action: led $led not exist"
		return 1
	}

	for option in $options; do
		val=$(config_get $1 $option)
		[ -z "$val" ] && {
			LED_LOGE " do_action: option $option of $1 is null"
			return 2
		}
		eval echo $val >/sys/class/leds/$led/$option
	done
}

xqled_func_act_sysfs() {
	local func="$1"
	local action=""

	# init env from uci config
	config_foreach init_env "env_var"

	# get argv of func for action
	local argv=$(config_get $func argv)
	[ -n "$argv" ] && {
		eval export $argv
	}

	# get action of func
	local action_list=$(config_get $func action)
	action_list=$(eval echo $action_list)
	[ -z "$action_list" ] && {
		LED_LOGE " xqled_func_act_sysfs:action of $func is null"
		return 1
	}

	for action in $action_list; do
		do_action $action
	done

	LED_LOGI " xqled finish [$func]"

	return $?
}
