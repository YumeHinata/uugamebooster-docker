#!/bin/ash

arch_mesh_bh_rssi() {
	local bh_type=
	local ifname_bh=
	local band=

	bh_type=$(topomon_action.sh current_status bh_type)
	if [ "${bh_type}" = "wireless" ]; then
		band=$(mesh_cmd backhaul get real_band)
		ifname_bh=$(uci -q get "misc.backhauls.backhaul_${band}_sta_iface")

		iwinfo "${ifname_bh}" info 2>/dev/null |
			grep "Signal" |
			sed 's|dBm||g' |
			awk '{print $2}'
	fi
}

arch_wlan_ch_usage() {
	local band=
	local device=
	local chan_util=

	for band in 2G 5G; do
		device=$(uci -q get misc.wireless.if_${band})
		[ -z "$device" ] && continue

		chan_util=$(iwpriv "${device}" g_chanutil 2>/dev/null | awk -F: '{print $2/100}')
		echo "${band}:${chan_util}"
	done
}

parse_width_from_mode()
{
	width=$(echo $1 | grep 160)
	if [ ! -z $width ]; then
		width="160MHz"
	else
		width=$(echo $1 | grep 80)
		if [ ! -z $width ]; then
			width="80MHz"
		else
			width=$(echo $1 | grep 40)
			if [ ! -z $width ]; then
				width="40MHz"
			else
				width="20MHz"
			fi
		fi
	fi

	echo -n "$width"
}

arch_get_tx_mcs() {
	local device=$1
	local tx_mcs_file=$2
	local tx_mcs=$(wifistats $device 9 | grep -w tx_mcs)
	local org_data
	local temp_mcs=0
	local cur_data
	local len

	if [ -f $tx_mcs_file ]; then
		line_data=$(sed -n "1p" $tx_mcs_file)
		org_data=$(echo $line_data | tr -s ' ''\n')
	fi

	while [ -n "$tx_mcs" ]; do
		tx_mcs="${tx_mcs#*,}"
		item="${tx_mcs%%,*}"
		len=$(expr length "$tx_mcs")
		if [ $len -lt 2 ]; then
			break
		fi

		local num=$(echo $item | cut -d ':' -f 1)
		local data=$(echo $item | cut -d ':' -f 2)

		if [ "$num" -gt 0 ]; then
			cur_data="$cur_data $data"
		fi
	done

	local max=0
	local i=1
	for num2 in $cur_data; do
		num1=$(echo $org_data | cut -d " " -f $i)
		local diff=0

		[ $num2 -gt $num1 ] && {
			diff=$((num2 - num1))
		}

		[ $diff -gt $max ] && {
			max=$diff
			temp_mcs=$i
		}

		i=$((i+1))
	done

	#echo "temp_mcs=$temp_mcs,cur_data=$cur_data" > /dev/console
	echo "$cur_data" > $tx_mcs_file

	echo -n "$temp_mcs"
}

arch_get_rx_mcs() {
	local device=$1
	local rx_mcs_file=$2
	local rx_mcs=$(wifistats $device 10 | grep -w rx_mcs)
	local org_data
	local temp_mcs=0
	local cur_data
	local len

	if [ -f $rx_mcs_file ]; then
		line_data=$(sed -n "1p" $rx_mcs_file)
		org_data=$(echo $line_data | tr -s ' ''\n')
	fi

	while [ -n "$rx_mcs" ]; do
		rx_mcs="${rx_mcs#*,}"
		item="${rx_mcs%%,*}"

		len=$(expr length "$rx_mcs")
		if [ $len -lt 2 ]; then
			break
		fi

		local num=$(echo $item | cut -d ':' -f 1)
		local data=$(echo $item | cut -d ':' -f 2)

		if [ "$num" -gt 0 ]; then
			cur_data="$cur_data $data"
		fi
	done

	local max=0
	local i=1
	for num2 in $cur_data; do
		num1=$(echo $org_data | cut -d " " -f $i)
		local diff=0
		[ $num2 -gt $num1 ] && {
			diff=$((num2 - num1))
		}

		[ $diff -gt $max ] && {
			max=$diff
			temp_mcs=$i
		}

		i=$((i+1))
	done

	#echo "temp_mcs=$temp_mcs,cur_data=$cur_data" > /dev/console
	echo "$cur_data" > $rx_mcs_file

	echo -n "$temp_mcs"
}

__get_cpu_temp_max() {
	local max_temp=0

	for temp in $(cat /sys/devices/virtual/thermal/thermal_zone*/temp); do
		[ "$temp" -gt "$max_temp" ] && max_temp="$temp"
	done

	echo -n "$((max_temp / 1000))"
}

arch_sys_thermal_data() {
	local wifi_num=2 #2G,5G
	local threshold_temp=65

	local if_2g='wl1'
	local if_5g='wl0'

	local device_2g='wifi1'
	local device_5g='wifi0'

	#date
	local date_sec=$(date +%s)

	#temperature
	local temp_cpu=$(__get_cpu_temp_max)
	local temp_5g=$(thermaltool -i wifi0 -get | grep temperature | awk '{print $3}' | tr -d [,])
	local temp_2g=$(thermaltool -i wifi1 -get | grep temperature | awk '{print $3}' | tr -d [,])

	#5G mcs/nss/bw
	local rx_nss_5g=$(iwpriv $if_5g get_nss | awk -F '[:]' '{print $NF}' | sed 's/[ \t]*$//g')
	local tx_nss_5g=$(iwpriv $if_5g get_nss | awk -F '[:]' '{print $NF}' | sed 's/[ \t]*$//g')
	local mode_5g="$(iwpriv $if_5g get_mode | awk -F '[:]' '{print $NF}')"
	local rx_bw_5g=$(parse_width_from_mode $mode_5g)
	local tx_bw_5g=$(parse_width_from_mode $mode_5g)
	local tx_mcs_file_5g="/tmp/last_wlan_tx_mcs_5g"
	local rx_mcs_file_5g="/tmp/last_wlan_rx_mcs_5g"
	local tx_mcs_5g=$(arch_get_tx_mcs $device_5g $tx_mcs_file_5g)
	local rx_mcs_5g=$(arch_get_rx_mcs $device_5g $rx_mcs_file_5g)

	#2.4G mcs/nss/bw
	local rx_nss_2g=$(iwpriv $if_2g get_nss | awk -F '[:]' '{print $NF}' | sed 's/[ \t]*$//g')
	local tx_nss_2g=$(iwpriv $if_2g get_nss | awk -F '[:]' '{print $NF}' | sed 's/[ \t]*$//g')
	local mode_2g="$(iwpriv $if_2g get_mode | awk -F '[:]' '{print $NF}')"
	local rx_bw_2g=$(parse_width_from_mode $mode_2g)
	local tx_bw_2g=$(parse_width_from_mode $mode_2g)
	local tx_mcs_file_2g="/tmp/last_wlan_tx_mcs_2g"
	local rx_mcs_file_2g="/tmp/last_wlan_rx_mcs_2g"
	local tx_mcs_2g=$(arch_get_tx_mcs $device_2g $tx_mcs_file_2g)
	local rx_mcs_2g=$(arch_get_rx_mcs $device_2g $rx_mcs_file_2g)

	#5G rx/tx
	local cur_rx_bytes=0
	local last_rx_bytes=0
	local rx_bytes_5g=0
	local rx_bytes_file_5g="/tmp/last_wlan_rx_bytes_5g"
	cur_rx_bytes=$(ip -s link show dev $if_5g | awk 'NR==4 {print $1}')

	[ -e "$rx_bytes_file_5g" ] && {
		last_rx_bytes=$(cat $rx_bytes_file_5g)
		[ $cur_rx_bytes -gt $last_rx_bytes ] && {
			rx_bytes_5g=$((cur_rx_bytes - last_rx_bytes))
		}
	}
	echo "$cur_rx_bytes" > "$rx_bytes_file_5g"

	local cur_tx_bytes=0
	local last_tx_bytes=0
	local tx_bytes_5g=0
	local tx_bytes_file_5g="/tmp/last_wlan_tx_bytes_5g"
	local cur_tx_bytes=$(ip -s link show dev $if_5g | awk 'NR==6 {print $1}')

	[ -e "$tx_bytes_file_5g" ] && {
		last_tx_bytes=$(cat $tx_bytes_file_5g)
		[ $cur_tx_bytes -gt $last_tx_bytes ] && {
			tx_bytes_5g=$((cur_tx_bytes - last_tx_bytes))
		}
	}
	echo "$cur_tx_bytes" > "$tx_bytes_file_5g"

	#2.4G rx/tx
	cur_rx_bytes=0
	last_rx_bytes=0
	local rx_bytes_2g=0
	local rx_bytes_file_2g="/tmp/last_wlan_rx_bytes_2g"
	cur_rx_bytes=$(ip -s link show dev $if_2g | awk 'NR==4 {print $1}')

	[ -e "$rx_bytes_file_2g" ] && {
		last_rx_bytes=$(cat $rx_bytes_file_2g)
		[ $cur_rx_bytes -gt $last_rx_bytes ] && {
			rx_bytes_2g=$((cur_rx_bytes - last_rx_bytes))
		}
	}
	echo "$cur_rx_bytes" > "$rx_bytes_file_2g"

	cur_tx_bytes=0
	last_tx_bytes=0
	local tx_bytes_2g=0
	local tx_bytes_file_2g="/tmp/last_wlan_tx_bytes_2g"

	cur_tx_bytes=$(ip -s link show dev $if_2g | awk 'NR==6 {print $1}')
	[ -e "$tx_bytes_file_2g" ] && {
		last_tx_bytes=$(cat $tx_bytes_file_2g)
		[ $cur_tx_bytes -gt $last_tx_bytes ] && {
			tx_bytes_2g=$((cur_tx_bytes - last_tx_bytes))
		}
	}
	echo "$cur_tx_bytes" > "$tx_bytes_file_2g"

	#eth rx/tx
	cur_rx_bytes=0
	cur_tx_bytes=0
	last_rx_bytes=0
	last_tx_bytes=0
	local eth_rx_bytes=0
	local eth_tx_bytes=0
	local rx_bytes_file_eth="/tmp/last_eth_rx_bytes"
	local tx_bytes_file_eth="/tmp/last_eth_tx_bytes"
	local lan_eth_list=$(brctl show | grep -o "eth.*")
	for ifname in ${lan_eth_list}; do
		local rx_bytes=$(ip -s link show dev $ifname | awk 'NR==4 {print $1}')
		local tx_bytes=$(ip -s link show dev $ifname | awk 'NR==6 {print $1}')
		cur_rx_bytes=$((cur_rx_bytes + rx_bytes))
		cur_tx_bytes=$((cur_tx_bytes + tx_bytes))
	done

	[ -e "$rx_bytes_file_eth" ] && {
		last_rx_bytes=$(cat $rx_bytes_file_eth)
		[ $cur_rx_bytes -gt $last_rx_bytes ] && {
			eth_rx_bytes=$((cur_rx_bytes - last_rx_bytes))
		}
	}
	echo "$cur_rx_bytes" > "$rx_bytes_file_eth"

	[ -e "$tx_bytes_file_eth" ] && {
		last_tx_bytes=$(cat $tx_bytes_file_eth)
		[ $cur_tx_bytes -gt $last_tx_bytes ] && {
			eth_tx_bytes=$((cur_tx_bytes - last_tx_bytes))
		}
	}
	echo "$cur_tx_bytes" > "$tx_bytes_file_eth"

	local phy_speed_total=0
	local phy_dump=$(phyhelper dump)
	local phy_up_num=$(echo "$phy_dump" | grep "Link:up" -c)
	local speed_list=$(echo "$phy_dump" | grep "Link:up" | grep -o "Speed:\d*" | awk -F: '{print $2}')

	for speed in ${speed_list}; do
		phy_speed_total=$((phy_speed_total + speed))
	done

	[ "$temp_5g" -lt "$threshold_temp" -a "$temp_2g" -lt "$threshold_temp" ] && return

	#params:
	#date_sec                - seconds of date.
	#temp_cpu                - temperature of cpu.
	#wifi_num                - number of wifi.
	#temp_5g/temp_2g         - temperature of 5g/2g wifi chip.
	#rx_mcs_5g/rx_mcs_2g     - mcs of 5g/2g rx.
	#rx_nss_5g/rx_nss_2g     - nss of 5g/2g rx.
	#rx_bw_5g/rx_bw_52g      - bindwith of 5g/2g rx.
	#tx_mcs_5g/tx_mcs_2g     - mcs of 5g/2g tx.
	#tx_nss_5g/tx_nss_2g      - nss of 5g/2g tx.
	#tx_bw_5g/tx_bw_2g       - bindwith of 5g/2g tx.
	#rx_bytes_5g/rx_bytes_2g - bytes incremented of rx.
	#tx_bytes_5g/tx_bytes_2g - bytes incremented of tx.

	#format:
	#The ';' as a class separator, The ',' as a parameter separator
	echo "$date_sec;$temp_cpu;$wifi_num;"\
"$temp_5g,${rx_mcs_5g:=*},${rx_nss_5g:=*},${rx_bw_5g:=*},${tx_mcs_5g:=*},${tx_nss_5g:=*},${tx_bw_5g:=*},$rx_bytes_5g,$tx_bytes_5g;"\
"$temp_2g,${rx_mcs_2g:=*},${rx_nss_2g:=*},${rx_bw_2g:=*},${tx_mcs_2g:=*},${tx_nss_2g:=*},${tx_bw_2g:=*},$rx_bytes_2g,$tx_bytes_2g;"\
"$phy_up_num,$phy_speed_total,$eth_rx_bytes,$eth_tx_bytes;"
}

get_bw_sum() {
	local bw_str="$1"
	local bw_sum=

	bw_sum=$(echo "$bw_str" | awk -F= '{
		split($2, a, ",");
		sum = 0;
		for (i in a) {
			gsub(/^[ \t]+|[ \t]+$/, "", a[i]);
			split(a[i], b, ":");
			sum += b[2];
		}
		print sum;
	}')
	echo "$bw_sum"
}

arch_wlan_ax_tx_mu_data() {
	local band=
	local device=
	local tx_str=
	local tx_bw_str=
	local tx_ofdma_bw_str=
	local tx_mimo_bw_str=
	local tx_sum=
	local tx_ofdma_sum=
	local tx_mimo_sum=

	local tx_ofdma_persent=
	local tx_mimo_persent=

	for band in 2G 5G; do
		device=$(uci -q get misc.wireless.if_${band})
		[ -z "$device" ] && continue

		tx_str=$(wifistats "${device}" 9)
		tx_bw_str=$(echo "$tx_str" | grep -w tx_bw)
		tx_ofdma_bw_str=$(echo "$tx_str" | grep -w ofdma_tx_bw)
		tx_mimo_bw_str=$(echo "$tx_str" | grep -w ax_mu_mimo_tx_bw)

		tx_sum=$(get_bw_sum "$tx_bw_str")
		tx_ofdma_sum=$(get_bw_sum "$tx_ofdma_bw_str")
		tx_mimo_sum=$(get_bw_sum "$tx_mimo_bw_str")
		if [ "$tx_sum" -eq 0 ]; then
			tx_ofdma_persent=0
			tx_mimo_persent=0
		else
			tx_ofdma_persent=$(awk "BEGIN { printf \"%.2f\", ($tx_ofdma_sum / $tx_sum) * 100 }")
			tx_mimo_persent=$(awk "BEGIN { printf \"%.2f\", ($tx_mimo_sum / $tx_sum) * 100 }")
		fi
		echo "${band}:${tx_ofdma_persent},${tx_mimo_persent}"
	done
}

arch_wlan_ax_rx_mu_data() {
	local band=
	local device=
	local rx_str=
	local rx_bw_str=
	local rx_ofdma_bw_str=
	local rx_sum=
	local rx_ofdma_sum=
	local rx_mimo_sum=

	local rx_ofdma_persent=
	local rx_mimo_persent=

	for band in 2G 5G; do
		device=$(uci -q get misc.wireless.if_${band})
		[ -z "$device" ] && continue
		rx_str=$(wifistats "${device}" 10)
		rx_bw_str=$(echo "$rx_str" | grep -w rx_bw)
		rx_ofdma_bw_str=$(echo "$rx_str" | grep -w ul_ofdma_rx_bw)

		rx_sum=$(get_bw_sum "$rx_bw_str")
		rx_ofdma_sum=$(get_bw_sum "$rx_ofdma_bw_str")
		rx_mimo_sum=$(echo "$rx_str" | grep -w rx_11ax_mumimo)

		if [ "$rx_sum" -eq 0 ]; then
			rx_ofdma_persent=0
			rx_mimo_persent=0
		else
			rx_ofdma_persent=$(awk "BEGIN { printf \"%.2f\", ($rx_ofdma_sum / $rx_sum) * 100 }")
			rx_mimo_persent=$(awk "BEGIN { printf \"%.2f\", ($rx_mimo_sum / $rx_sum) * 100 }")
		fi
		echo "${band}:${rx_ofdma_persent},${rx_mimo_persent}"
	done
}