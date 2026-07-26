#!/bin/sh

COUNTRY_CODE="$1"

set_timezone_by_country() {
	local cc="$1"
	local tz=""
	local tz_idx=""

	if [ -z "$cc" ]; then
		cc=$(getCountryCode)
	fi

	tz_idx=$(uci -q get country_mapping."$cc".timezoneindex)
	[ -z "$tz_idx" ] && {
		echo "No timezone index for country $cc" >/dev/console
		return
	}


	tz=$(uci -q get timezone."${tz_idx//./_}".tz)
	[ -z "$tz" ] && {
		echo "No timezone for index $tz_idx" >/dev/console
		return
	}

	echo "$tz" >/tmp/TZ

	uci set system.@system[0].timezone="$tz"
	uci set system.@system[0].timezoneindex="$tz_idx"
	uci commit system

	# apply timezone to kernel
	hwclock -u -t

	if [ -c "/dev/rtc0" ]; then
		local uptime=""
		uptime=$(cut -d'.' -f1 </proc/uptime)
		[ "$uptime" -gt 100 ] && hwclock -w -u
	fi
}

set_timezone_by_country "$COUNTRY_CODE"
