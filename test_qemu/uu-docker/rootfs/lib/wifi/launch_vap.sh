#!/bin/sh
#
# Copyright (c) 2022 Qualcomm Technologies, Inc.
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#

. /lib/functions.sh

start_event_vap() {
	local vap_mode=""
	local vap_mode_ret=0

	. /lib/wifi/qcawificfg80211.sh
	get_vap_mode
	if [ "$vap_mode" = "0" ]; then
		if [ $vap_mode_ret = 1 ]; then
			echo "***** Fast boot is disabled for first boot $1 *****" > /dev/kmsg
		elif [ $vap_mode_ret = 2 ]; then
			echo "***** Fast boot is disabled for default config $1 *****" > /dev/kmsg
		elif [ $vap_mode_ret = 3 ]; then
			echo "***** Fast boot is not supported for Whunt $1 *****" > /dev/kmsg
		elif [ $vap_mode_ret = 4 ]; then
			echo "***** Global ini file not present: Fast boot is disabled $1 *****" > /dev/kmsg
		elif [ $vap_mode_ret = 5 ]; then
			echo "***** Fast boot is disabled for subsequent load $1 *****" > /dev/kmsg
		else
			echo "***** Fast boot VAP mode is disabled $1 *****" > /dev/kmsg
		fi
		return
	fi

	lock /var/run/wifilock
	if [ -f /tmp/event_radio_done_for_$1 ]; then
		echo Duplicate radio found: $1 > /dev/console
		lock -u /var/run/wifilock
		return
	fi

	echo "***** Fast boot VAP mode is enabled $1 *****" > /dev/kmsg
	touch /tmp/event_radio_done_for_$1
	lock -u /var/run/wifilock

	touch /tmp/event_fast_boot_in_progress

	post_load_qcawificfg80211 $1
	post_detect_qcawificfg80211 $1
}

[ "$1" != "/lib/wifi" ] && start_event_vap $1
