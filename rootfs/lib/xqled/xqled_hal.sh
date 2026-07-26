#!/bin/sh

#trace caller
#ppid=$PPID
#XQLED_LOGI " xqled [$1], called by ppid[$ppid],<`cat /proc/${ppid}/cmdline`>"

driver=$(uci -q get xqled.driver.name)
[ -z "$driver" ] && driver="gpio"

[ -f "/lib/xqled/xqled_${driver}.sh" ] || exit 1
. /lib/xqled/xqled_${driver}.sh 2>/dev/null >/dev/null

if type "xqled_func_act_${driver}" 2>/dev/null >/dev/null; then
	"xqled_func_act_${driver}" "$1"
else
	echo "xqled: not support xqled_func_act_${driver}."
	exit 2
fi
