#!/bin/sh

signal_good_cli_num=0
signal_accepted_cli_num=0
signal_bad_cli_num=0

for band in 2G 5G 5GH; do
	ifname=$(uci -q get misc.wireless.ifname_${band})
	if [ -z "$ifname" ]; then
		continue
	fi

	signal_info=$(iwinfo ${ifname} assoc 2>/dev/null \
			|sed '1,7d' \
			|sed 's|dBm||g' \
			|sed 's|MBit/s||g' \
			|awk '{print $4}')

	for signal in ${signal_info}; do
		if [ $signal -gt -55 ]; then
			signal_good_cli_num=$((signal_good_cli_num+1))
		elif [ $signal -lt -70 ]; then
			signal_bad_cli_num=$((signal_bad_cli_num+1))
		else
			signal_accepted_cli_num=$((signal_accepted_cli_num+1))
		fi
	done
done

echo "good:${signal_good_cli_num}"
echo "accepted:${signal_accepted_cli_num}"
echo "bad:${signal_bad_cli_num}"