#!/bin/sh
# format: {enable}:{wan number:2}:{mode}
enable=0
mode=0

enable=$(uci -q get mwan3.globals.enabled)
mode=$(uci -q get mwan3.default_rule.use_policy)

case "$mode" in
"balanced")
	mode=0
	;;
"wan_wanb")
	mode=1
	;;
"wanb_wan")
	mode=2
	;;
"wan_only")
	mode=3
	;;
"wanb_only")
	mode=4
	;;
*)
	mode=0
	;;
esac

echo "${enable}:2:${mode}"
