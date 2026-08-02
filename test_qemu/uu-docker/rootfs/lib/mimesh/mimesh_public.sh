#!/bin/sh

# public for mimesh

export MIMESH_DEBUG=0 # miwifi set to 1 for test
export NETWORK_PRIV="lan"
export NETWORK_GUEST="guest"
export BHPREFIX="MiMesh"
export bh_defmgmt="psk2+ccmp"

# print level
export MIMESH_PRT_ERR=1      # erro
export MIMESH_PRT_INFO=2     # erro + info
export MIMESH_PRT_DEBUG=3    # erro + info + debug
export MIMESH_PRT_LEVEL="$MIMESH_PRT_INFO"
[ "$MIMESH_DEBUG" = "1" ] && MIMESH_PRT_LEVEL="$MIMESH_PRT_DEBUG"

# MLO candidate seletion threshold
MLO_RSSI_THRESHOLD_5G=-71
MLO_RSSI_THRESHOLD_5GH=-71
MLO_RSSI_THRESHOLD_2G=-71
MLO_METRIC_HYST=20

LOG_FILE="/tmp/log/mimesh.log"
TMP_LOG_SIZE=600000

[ -f $LOG_FILE ] || touch $LOG_FILE

MIMESH_TRACE()
{
	local log="$1"
	#return
	local file=$LOG_FILE
	local ts="`date '+%Y%m%d-%H%M%S'`@`cat /proc/uptime | awk '{print $1}'`"
	local time="[$ts]"
	local item="${time}    ${log}"

	echo -e "$item" >> "$file" 2>/dev/null
	sync
}

RET(){
	echo -n "$1"
}

MIMESH_LOGD()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_DEBUG" ] && return 0

	local __msg="$1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_debug $__msg"
	}
	#logger -p 4 -t mimesh_debug "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_debug $__msg"
}

MIMESH_LOGI()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_INFO" ] && return 0

	local __msg=" $1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_info $__msg"
	}
	#logger -p 3 -t mimesh_info "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_info $__msg"
}

MIMESH_LOGE()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_ERR" ] && return 0

	local __msg="$1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_error $__msg"
	}
	#logger -p 2 -t mimesh_error "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_error $__msg"
}

WHC_LOGD()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_DEBUG" ] && return 0

	local __msg="$1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_debug $__msg"
	}
	#logger -p 4 -t mimesh_debug "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_debug $__msg"
}

WHC_LOGI()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_INFO" ] && return 0

	local __msg=" $1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_info $__msg"
	}
	#logger -p 3 -t mimesh_info "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_info $__msg"
}

WHC_LOGE()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_ERR" ] && return 0

	local __msg="$1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_error $__msg"
	}
	#logger -p 2 -t mimesh_error "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_error $__msg"
}

### 
json_get_value_sh_p()
{
	local json_str="`echo $1 | sed 's/^{//' | sed 's/}$//'`"
	local key="$2"

	#json_str=`echo $json_str | sed 's/:[ ]*/:/g' | sed 's/[ ]*\"/\"/g'`
	echo "$json_str" | grep -q "\"$key\":" || {
		RET ""
		return 1
	}

	# value is a odject {}
	local tmp=`echo "$json_str" | sed 's/.*'\"$key\"':/\1/' | sed 's/^[ ]*//'`
	echo "$tmp" | grep -qE "^\{" && {
		RET "`echo $tmp | awk -F'}' '{print $1}'`}"
		return 0
	}

	# value is a array []
	echo "$tmp" | grep -qE "^\[" && {
		RET "`echo $tmp | awk -F']' '{print $1}'`]"
		return 0
	}

	# value is a value
	tmp=`echo $tmp | awk -F',' '{print $1}' | sed 's/[ ]*$//'`
	tmp=`echo $tmp | sed 's/\}//g' | sed 's/\]//g'`
	RET "$tmp" | sed 's/^"//' | sed 's/"$//'
	return 0
}

json_get_value_sh()
{
	local val=""
	json_load "$1"
	json_get_var val "$key"

	RET "$val"
	[ -n "$val" ]
}

json_get_value()
{
	local json_str="`echo "$1" | sed 's/^\[//' | sed 's/\]$//' `"
	local key="$2"

	parse_json "$json_str" "$key"
}

id_generate()
{
	local seed=`awk -F- '{print $1}' /proc/sys/kernel/random/uuid`
	local raw=`printf %d 0x$seed`
	RET $(($raw & 0xfffff))
}

str_escape()
{
	local str="$1"
	echo -n "$str" | sed -e 's/^"/\\"/' | sed -e 's/\([^\]\)"/\1\\"/g' | sed -e 's/\([^\]\)"/\1\\"/g' | sed -e 's/\([^\]\)\(\\[^"\\\/bfnrtu]\)/\1\\\2/g' | sed -e 's/\([^\]\)\\$/\1\\\\/'
}

base64_enc()
{
	## encode and unfold mutiple line
	local str="`echo -n "$1" | base64 | sed 's/ //g'`"
	RET "$str" | awk -v RS="" '{gsub("\n","");print}'
	#RET "`echo "$1" | base64 | xargs`"
}

base64_dec()
{
	RET "`echo "$1" | base64 -d`"
}

json_str_append()
{
	local cur_msg="$1"
	local new_msg="$1"
	local append_jsonstr="$2"

	if [ -n "$append_jsonstr" ]; then
		if [ -z "$cur_msg" ]; then
			new_msg="{$append_jsonstr}"
		else
			__final_ch() {
				local str="$@"
				local slen="${#str}"

				echo "$str" | cut -c "$slen"-"$slen"
			}

			local msg_prefix=""
			local final_ch=$(__final_ch "$cur_msg")

			if [ "$final_ch" = "," ]; then
				new_msg="${cur_msg}${append_jsonstr},"
			elif [ "$final_ch" = "}" ]; then
				new_msg="${cur_msg%\}*},${append_jsonstr}}"
			elif [ "$final_ch" = "\"" ]; then
				new_msg="${cur_msg},${append_jsonstr}"
			fi
		fi
	fi

	echo "$new_msg"
}

# truncate ssid, to avoid the situation that cut a UTF-8 large CHAR beyond ASCII.
# UTF-8 Characters span vary unit of sizeof(char), may vary from 1 to 6
# 1 unit UTF8: 0xxxxxxx
# 2 units UTF8: 110xxxxx 10xxxxxx
# 3 units UTF8: 1110xxxx 10xxxxxx 10xxxxxx
# 4 units UTF8: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
## support Chinese Char and emoji
ssid_truncate()
{
	local MAX_LEN=26
	local src_str="$1"

	local src_len="${#src_str}"
	[ "$src_len" -le "$MAX_LEN" ] && {
		echo -n "$src_str"
		return 0
	}

	logger -p 3 -t "ssid_trunca" "src $src_len@[$src_str]"

	local cut_len=0
	local ch=""
	local ch_hex=0x0
	local ch_val=0
	local cur_len="$src_len"
	local utf8_ch_flag=0

	while [ "$cur_len" -gt "$MAX_LEN" -o "$utf8_ch_flag" -eq 1 ]; do
		ii="$cur_len"
		ch="`echo -n $src_str | cut -b $ii-$ii`"
		ch_hex="`echo -n $ch | hexdump | awk 'NR==1 {print $2}' | cut -b 1-2`"
		ch_val="`printf %d 0x$ch_hex`"
		#logger -p 3 -t "ssid_trunca" " ch=[$ch], ch_hex=[$ch_hex], ch_val=$ch_val"

		if [ "$ch_val" -le 128 ]; then
			# ASCII char
			utf8_ch_flag=0
		else
			# utf8 char
			if [ "$((ch_val - 128))" -lt 64 ]; then
				utf8_ch_flag=1
			else
				utf8_ch_flag=0
			fi
		fi
		cur_len=$((cur_len - 1))

	done

	local dst_str=`echo -n "$src_str" | cut -b 1-$cur_len`
	#logger -p 3 -t "ssid_trunca"  " dst_str ${#dst_str}@[$dst_str]"

	echo -n "$src_str" | cut -b 1-$cur_len
	return 0
}

# test produce bh pwd, from ssid and mac md5sum
xor_sum()
{
	local s1=`echo "$1" | md5sum | awk '{print $1}'`
	local s2=`echo "$2" | md5sum | awk '{print $1}'`
	local str=""

	#local len=$(($l1 > $l2 ? $l1 : $l2))
	local len=${#s1}
	for i in `seq 0 2 $((len - 1))`; do
		bb=$((0x${s1:$i:2} ^ 0x${s2:$i:2}))
		#echo bb=$bb
		str="${str}`printf %02x $bb`"
	done
	#echo -n "${str// /}"
	echo -n "${str}"
}

led_link_good()
{
	#rm temporarily because no definition led
	echo "link good"
}

led_link_poor()
{
	#rm temporarily because no definition led
	echo "link poor"
}

led_link_fail()
{
	#rm temporarily because no definition led
	echo "link good"
}

recover_mesh_power()
{
	local max_power=0
	local real_power=0
	local power_level="max"
	local need_low_power=0

	max_power=$(uci -q get misc.wireless.if_5g_maxpower)
	if [ -z "$max_power" ]; then
		max_power=30
	fi
	max_power="${max_power%%.*}"

	power_level=$(uci -q get wireless.wifi1.txpwr)
	if [ -z "$power_level" ]; then
		power_level="max"
	fi

	need_low_power=$(uci -q get misc.mesh.need_lower_power)
	if [ -z "$need_low_power" ]; then
		need_low_power=0
	fi

	if [ "$need_low_power" == "1" ]; then
		if [ "$power_level" == "max" ]; then
			real_power=$max_power
		elif [ "$power_level" == "mid" ]; then
			real_power=$(expr $max_power - 1)
		elif [ "$power_level" == "min" ]; then
			real_power=$(expr $max_power - 3)
		fi
		iwconfig wl0 txpower ${real_power}
	fi
}

is_mlo_bhlink() {
	mlo_support_check
	[ "$?" != "1" ] && return 0

	local bh_sta_mlo=$(uci -q get wireless.bh_sta_mlo.mlo)
	[ -z "$bh_sta_mlo" ] && return 0

	for mem in $bh_sta_mlo; do
		local mem_sta_ifname=$(uci -q get misc.backhauls.backhaul_${mem}_sta_iface)
		[ -z "$mem_sta_ifname" ] && return 0

		local iface_secname=$(uci show wireless | grep -w "ifname=\'$mem_sta_ifname\'" | awk -F"." '{print $2}')
		[ -z "$iface_secname" ] && return 0

		local iface_disabled=$(uci -q get wireless.$iface_secname.disabled)
		[ "$iface_disabled" = "1" ] && return 0

		# check if connected?
		local is_connected=$(iwconfig $mem_sta_ifname | sed -ne 's/.*Access Point:\(.*\)/\1/p')
		if [ "$is_connected" != "Not-Associated" ] \
				&& [ "${is_connected##*:}" != "${is_connected}" ]; then
			return 1
		fi
	done

	#default to non mlo
	return 0
}

# check rssi or other metrics, current only check rssi
# return: 0=ok, 1=bad rssi, 2=check failed
mlo_bhlink_check() {
	local mlo_members="$1"

	for mem in $mlo_members; do
		local sta_iface=$(uci -q get wireless.bh_sta_$mem.ifname)
		local is_connected=$(iwconfig $sta_iface | sed -ne 's/.*Access Point:\(.*\)/\1/p')

		# not connected
		if [ "$is_connected" = "Not-Associated" ] \
				|| [ "${is_connected##*:}" = "${is_connected}" ]; then
			return 2
		fi

		# connected, check rssi
		local rssi=$(iwconfig $sta_iface 2>>/dev/null|grep 'Signal level'|awk -F'=' '{print $3}'|awk '{print $1}')
		local rssi_threshold=
		case "$mem" in
			2g)
				rssi_threshold=$MLO_RSSI_THRESHOLD_2G
				;;
			5g)
				rssi_threshold=$MLO_RSSI_THRESHOLD_5G
				;;
			5gh)
				rssi_threshold=$MLO_RSSI_THRESHOLD_5GH
				;;
			*)
				return 2
				;;
		esac

		local thresh_up=$(( rssi_threshold + 2 ))
		local thresh_down=$((  rssi_threshold - 2 ))
		[ "$rssi" -gt "$thresh_up" ] && continue
		[ "$rssi" -lt "$thresh_down" ] && return 1
	done
	return 0
}

# mlo_support_check
# mlo_support == 1 and (mlo_depend_split and split_state)
mlo_support_check() {
	local mlo_support="$(uci -q get misc.features.mlo_support)"
	[ "$mlo_support" != "1" ] && return 0

	local mlo_depend_split="$(uci -q get misc.features.mlo_depend_split)"
	if [ "$mlo_depend_split" = "1" ]; then
		local split_state="$(uci -q get xiaoqiang.common.split_state)"
		[ "$split_state" != "1" ] && return 0 || return 1
	fi
	return 1
}

# backhaul mlo_support check
# 0: not support, 1: support
bh_mlo_support() {
	mlo_support_check
	[ "$?" != "1" ] && return 0

	local mlo_disabled="$(uci -q get misc.mesh.backhaul_mlo_disabled)"
	[ "$mlo_disabled" = "1" ] && return 0

	# default support
	return 1
}

# easymesh support
# 0: not support, 1: support
easymesh_support() {
	local easymesh=$(uci -q get misc.mesh.easymesh)

	[ "$easymesh" = "1" ] && return 1
	return 0
}

# get mlo members from mlo_sets
# input
#	$1: mlo_sets=2g@bssid_2g,5g@bssid_5g,5gh@bssid_5gh
#	$2: scan or no_scan
#	$3: device_if tools for interactiong with wifi driver
# return val
#	mlo_members: 2g 5g or 2g 5gh or 5g 5gh or 2g 5g 5gh..
#	null string
mlo_members() {
	local mlo_sets="$1"
	local do_scan="$2"
	local device_if="$3"
	local meshid="$(uci -q get xiaoqiang.common.NETWORK_ID)"

	bh_mlo_support
	[ "$?" != "1" ] && return

	[ -z "$mlo_sets" ] && return
	[ -z "$device_if" ] && device_if="cfg80211tool"

	local sta_mlo_support=$(uci -q get misc.mld.sta_mlo)
	local is_tri_band=$(mesh_cmd is_tri_band)
	if [ "$is_tri_band" = "0" ]; then
		local mlo_membs=""
		for ele in ${mlo_sets//,/ }; do
			local mem=$(echo $ele | awk -F@ '{print $1}')
			[ -z "$mlo_membs" ] && mlo_membs="$mem" || mlo_membs="$mlo_membs $mem"
		done
		local uniq_membs="$(echo $mlo_membs|tr ' ' '\n'|sort -u|tr '\n' ' ')"
		local valid_cnts=0
		local valid_mems=""
		local tmp_mlo=" $sta_mlo_support "
		for ele in $uniq_membs; do
			if [ "${tmp_mlo%% $ele *}" != "$tmp_mlo" ]; then
				valid_cnts=$(( valid_cnts + 1 ))
				[ -z "$valid_mems" ] && valid_mems="$ele" || valid_mems="$valid_mems $ele"
			fi
		done
		if [ $valid_cnts -ge 2 ]; then
			echo -ne "$valid_mems"
		else
			echo -ne ""
		fi
		MIMESH_LOGD "mimesh_info<mlo_members>: mlo_sets=$mlo_sets, mlo_membs=$valid_mems"
		return
	fi

	local prev_metric=0
	local mld_link_cnts=0
	local best_metric_bssid=""
	local sta_mlo_max=$(uci -q get misc.mld.sta_mlo_max)
	[ -z "$sta_mlo_max" ] && sta_mlo_max=2

	for ele in ${mlo_sets//,/ }; do
		local band=$(echo $ele | awk -F@ '{print $1}')
		local bssid=$(echo $ele | awk -F@ '{print $2}')
		[ -z "$band" -o -z "$bssid" ] && continue
		local scan_iface=$(uci -q get misc.backhauls.backhaul_${band}_ap_iface)
		[ -z "$scan_iface" ] && continue

		if [ "$do_scan" != "no_scan" ]; then
			scan_result=$(meshd -s -i "$scan_iface" -e "$meshid" 2>>/dev/null | grep "$bssid")
			[ -z "$scan_result" ] && continue
			local rssi=$(echo "$scan_result" | sed -ne 's/.*rssi=\(.*\),.*$/\1/p')
			[ -z "$rssi" ] && continue
			case "$band" in
				2g)
					[ "$rssi" -lt $MLO_RSSI_THRESHOLD_2G ] && continue
					;;
				5g)
					[ "$rssi" -lt $MLO_RSSI_THRESHOLD_5G ] && continue
					;;
				5gh)
					[ "$rssi" -lt $MLO_RSSI_THRESHOLD_5GH ] && continue
					;;
			esac
		fi

		local bssid_metric=$($device_if $scan_iface g_bssid_metric $bssid|sed -ne 's/.*g_bssid_metric:\([0-9]\+\)/\1/p')
		[ -z "$bssid_metric" ] && continue

		local tmp_mlo=" $sta_mlo_support "
		if [ "${tmp_mlo%% $band *}" != "$tmp_mlo" ]; then
			mld_link_cnts=$(( mld_link_cnts + 1 ))
			metric_list="$metric_list $bssid_metric:$band"
			if [ $bssid_metric -gt $prev_metric ]; then
				best_metric_bssid="$band@$bssid"
			elif [ -z "$best_metric_bssid" ]; then
				best_metric_bssid="$band@$bssid"
			fi
			prev_metric=$bssid_metric
		fi
	done

	if [ "$mld_link_cnts" -lt 2 ]; then
		best_metric_bssid=""
		echo -ne "$best_metric_bssid"
	else
		local memb_cnts=0
		local mlo_membs=""
		local total_metric=0
		local sorted_metric_list=$(for metric in $metric_list; do echo "$metric"; done | sort -t':' -k1 -nr)
		for metric in $sorted_metric_list; do
			local mem=$(echo $metric | awk -F':' '{print $2}')
			local tmp_metric=$(echo $metric | awk -F':' '{print $1}')
			total_metric=$(( total_metric + tmp_metric ))

			[ -z "$mlo_membs" ] && mlo_membs="$mem" || mlo_membs="$mlo_membs $mem"
			memb_cnts=$(( memb_cnts + 1 ))
			[ $memb_cnts -eq $sta_mlo_max ] && break
		done

		local sta_iface=
		local cur_bh_mlo=$(uci -q get wireless.bh_sta_mlo.mlo)
		for band in $cur_bh_mlo; do
			sta_iface=$(uci -q get wireless.bh_sta_$band.ifname)
			break
		done

		local cur_total_metric=0
		local cur_bh_apmld="$($device_if $sta_iface g_mesh_mld | sed -ne 's/.*g_mesh_mld:\(.*\),.*$/\1/p')"
		if [ -n "$cur_bh_mlo" ] && [ -n "$cur_bh_apmld" ]; then
			for band in $cur_bh_mlo; do
				local scan_iface=$(uci -q get misc.backhauls.backhaul_${band}_ap_iface)
				local bssid=$(echo $cur_bh_apmld, | eval "sed -n 's/.*$band\@\([^,]*\),.*/\1/p'")
				local tmp_metric=$($device_if $scan_iface g_bssid_metric $bssid|sed -ne 's/.*g_bssid_metric:\([0-9]\+\)/\1/p')
				[ -z "$tmp_metric" ] && continue
				cur_total_metric=$(( cur_total_metric + tmp_metric ))
			done

			local metric_hyst=$(( cur_total_metric + (cur_total_metric * MLO_METRIC_HYST)/100 ))
			if [ "$metric_hyst" != "0" ] &&  [ $total_metric -le $metric_hyst ]; then
				echo -ne "$cur_bh_mlo"
				MIMESH_LOGD "mimesh_info<mlo_members>: bhsta_mlo not changed[$cur_bh_mlo][$metric_hyst >= $total_metric]"
				return
			fi
		fi

		local sorted_mlo_membs=$(for mem in $mlo_membs; do echo "$mem"; done | sort -nr | tr "\n" " ")
		echo -ne "$sorted_mlo_membs"
	fi
	MIMESH_LOGD "mimesh_info<mlo_members>: mlo_sets=$mlo_sets, best_metric_bssid=$best_metric_bssid, mlo_membs=$mlo_membs"
}

# check whether backhaul band changed
# if changed, switch the ap/sta ifname
wifi_bh_change()
{
	local cur_bh_chan="$1"
	local new_bh_ch="$2"
	local band_type="$3"
	local new_bh_band=""

	tri_band_check
	is_triband="$?"
	[ "$is_triband" != "1" ] && return 0

	[ -z "$band_type" ] && band_type="band"

	local cur_bh_band=$(mesh_backhaul get band)
	local cur_bh_band_upcase=$(echo "$cur_bh_band"|tr '[a-z]' '[A-Z]')
	local cur_bh_device=$(uci -q get misc.wireless.if_${cur_bh_band_upcase})

	[ "$cur_bh_chan" = "$new_bh_ch" ] && return
	if [ "$cur_bh_chan" = "auto" -o "$cur_bh_chan" = "0" ] \
		&& [ "$new_bh_ch" = "auto" -o "$new_bh_ch" = 0 ]; then
		return 0
	fi

	if [ "$cur_bh_band" = "5g" ]; then
		if [ $new_bh_ch -gt 64 ]; then
			WHC_LOGI " xq_whc_sync, backhaul $band_type changed from 5g to 5gh"
			new_bh_band="5gh"
		fi
	elif [ "$cur_bh_band" = "5gh" ]; then
		if [ $new_bh_ch -ge 36 -a $new_bh_ch -le 64 ]; then
			WHC_LOGI " xq_whc_sync, backhaul $band_type changed from 5gh to 5g"
			new_bh_band="5g"
		fi
	fi

	if [ -n "$new_bh_band" ]; then
		mesh_backhaul set "$band_type" "$new_bh_band"
		return 1
	fi
	return 0
}

support_mesh_version()
{
	local match_ver=$1
	local ver_list=$(uci -q get misc.mesh.version)

	if [ -z "$ver_list" ]; then
		return 0
	fi

	for v in $ver_list;
	do
		[ "$v" == "$match_ver" ] && return 1
	done

	return 0
}

max_mesh_version()
{
	local max_version=1
	local ver_list=$(uci -q get misc.mesh.version)

	if [ -z "$ver_list" ]; then
		return 0
	fi

	for v in $ver_list;
	do
		if [ "$v" -gt "$max_version" ]; then
			max_version=$v
		fi
	done

	return $max_version
}

mesh_suites()
{
	local peer_num=$(getmac peernum)
	local mesh_suite=$(uci -q get misc.features.meshSuites)

	[ "$mesh_suite" != "1" ] && return 0
	[ -z "$peer_num" -o "$peer_num" == "0" ] && return 0

	return $peer_num
}

tri_band_check()
{
	local if_count=$(uci -q get misc.wireless.wl_if_count)

	[ -z "$if_count" -o $if_count -ne 3 ] && return 0
	return 1
}

# iface for mesh_scan
# 5g & 5gh
mesh_iface()
{
	local itype="$1"
	[ -z "$itype" ] && itype="main_ap"

	mlo_support_check
	mlo_support="$?"

	tri_band_check
	is_triband="$?"

	list_append() {
		local list="$1"
		local append_ele="$2"

		local tmp_list=$(eval "echo \$${list}")

		[ -z "$append_ele" ] && return
		[ -z "$tmp_list" ] && eval "$list=$append_ele" || eval "$list=$tmp_list,$append_ele"
	}

	main_ap() {
		local ifname=
		local ifname_list=""

		#ifname=$(uci -q get misc.wireless.ifname_2G)
		#list_append ifname_list "$ifname"

		ifname=$(uci -q get misc.wireless.ifname_5G)
		list_append ifname_list "$ifname"

		if [ "$is_triband" -eq 1 ]; then
			ifname=$(uci -q get misc.wireless.ifname_5GH)
			list_append ifname_list "$ifname"
		fi
		echo "$ifname_list"
	}

	bh_ap() {
		local ifname=
		local ifname_list=""
		if [ "$is_triband" -eq 1 ]; then
			ifname=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
			list_append ifname_list "$ifname"

			ifname=$(uci -q get misc.backhauls.backhaul_5gh_ap_iface)
			list_append ifname_list "$ifname"
		else
			ifname_list=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
		fi
		#if [ "$mlo_support" = "1" ]; then
		#	ifname=$(uci -q get misc.backhauls.backhaul_2g_ap_iface)
		#	list_append ifname_list "$ifname"
		#fi
		echo "$ifname_list"
	}

	bh_sta() {
		local ifname=
		local ifname_list=""
		if [ "$is_triband" -eq 1 ]; then
			ifname=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
			list_append ifname_list "$ifname"

			ifname=$(uci -q get misc.backhauls.backhaul_5gh_sta_iface)
			list_append ifname_list "$ifname"
		else
			ifname_list=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
		fi
		#if [ "$mlo_support" = "1" ]; then
		#	ifname=$(uci -q get misc.backhauls.backhaul_2g_sta_iface)
		#	list_append ifname_list "$ifname"
		#fi
		echo "$ifname_list"
	}

	$itype
}

# dual: dual-band device, not mesh-suite
# dual-suite: dual-band mesh-suite device
# tri: tri-band usual device, not mesh-suite
# tri-suite: tri-band mesh-suite device
# mld-tri: tri-band wifi7 router
# mld-dul: dual-band wifi7 router
dev_type()
{
	local devtype=""

	tri_band_check
	[ $? -eq 1 ] && devtype="tri" || devtype="dual"

	#mlo_support_check
	#[ "$?" = "1" ] && devtype="${devtype:+${devtype}-}mld"

	mesh_suites
	[ $? -eq 1 ] && devtype="${devtype:+${devtype}-}suite"

	echo "$devtype"
}

mesh_backhaul()
{
	local CMD=$1
	local TYPE=$2

	local fac_bh_band=$(uci -q get misc.backhauls.backhaul)
	local cur_bh_band=$(uci -q get xiaoqiang.common.BACKHAUL)
	[ -z "$cur_bh_band" ] && cur_bh_band=$fac_bh_band

	case "$CMD" in
		set)
			case "$TYPE" in
				real_band)
					# current backhaul band used by cap
					# add for mlo to support meshing at all band(2G/5G/5G2)
					local band=$3
					[ -n "$band" ] && {
						uci -q set xiaoqiang.common.REAL_BACKHAUL=$band
						uci commit xiaoqiang
					}
					;;
				band)
					local band=$3
					local cur_band=$(mesh_backhaul get band)

					uci -q set xiaoqiang.common.BACKHAUL=$band
					uci commit xiaoqiang

					[ "$cur_band" != "$band" ] && {
						local ifname=$(uci -q get misc.backhauls.backhaul_${band}_ap_iface)
						ubus call miwifi-discovery bh_change {\"ifname\":\"$ifname\"} &
					}
					;;
			esac
			;;
		get)
			case "$TYPE" in
				real_band)
					# current backhaul band used by cap
					# add for mlo to support meshing at all band(2G/5G/5G2)
					local real_bh_band=$(uci -q get xiaoqiang.common.REAL_BACKHAUL)
					if [ -z "$real_bh_band" ]; then
						local mlo_sets=$(uci -q get wireless.bh_sta_mlo.mlo)
						if [ -n "$mlo_sets" ]; then
							local tmp_mlo=" $mlo_sets "
							if [ "${tmp_mlo##* 5gh }" != "${tmp_mlo}" ]; then
								real_bh_band="5gh"
							elif [ "${tmp_mlo##* 5g }" != "${tmp_mlo}" ]; then
								real_bh_band="5g"
							elif [ "${tmp_mlo##* 2g }" != "${tmp_mlo}" ]; then
								real_bh_band="2g"
							fi
							# update to config
							uci -q set xiaoqiang.common.REAL_BACKHAUL=$real_bh_band
							uci commit xiaoqiang
						else
							real_bh_band=$cur_bh_band
						fi
					fi
					echo -n "$real_bh_band"
					;;
				band)
					local iface=$3
					if [ -z "$iface" ]; then
						echo -n "$cur_bh_band"
					else
						local parent=
						if [ -f "/sys/class/net/$iface/parent" ]; then
							parent=$(cat /sys/class/net/$iface/parent)
						else
							local if_idx=$(uci show wireless | grep "\.ifname=\'$iface\'"|awk -F'.' '{print $2}')
							[ -z "$if_idx" ] && return
							parent=$(uci -q get wireless.$if_idx.device)
						fi
						local band=$(uci show misc.wireless | sed -n "s/.*wireless\.if_\(.*\)='$parent'/\1/p")
						echo -n "$(echo $band | tr '[A-Z]' '[a-z]')"
					fi
					;;
				device)
					local iface=$3
					local device=
					if [ -z "$iface" ]; then
						local band=$(echo $cur_bh_band | tr '[a-z]' '[A-Z]')
						[ -z "$band" ] && return
						device=$(uci -q get misc.wireless.if_$band)
					else
						if [ -f "/sys/class/net/$iface/parent" ]; then
							device=$(cat /sys/class/net/$iface/parent)
						else
							local if_idx=$(uci show wireless | grep "\.ifname=\'$iface\'"|awk -F'.' '{print $2}')
							[ -z "$if_idx" ] && return
							device=$(uci -q get wireless.$if_idx.device)
						fi
					fi
					echo -n "$device"
					;;
				*)
					;;
			esac
			;;
	esac
}

mesh_nbh_band()
{
	local nbh_band=""
	local bh_band=$(mesh_backhaul get band)
	local devtype=$(dev_type)

	case "$devtype" in
		dual|dual-suite) #dual band device
			nbh_band="$bh_band"
			;;
		*) #tri-band device
			[ "$bh_band" = "5g" ] && nbh_band="5gh" || nbh_band="5g"
			;;
	esac

	echo "$nbh_band"
}
