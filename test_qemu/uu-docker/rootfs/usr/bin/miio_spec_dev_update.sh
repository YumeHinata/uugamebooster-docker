#!/bin/ash

readonly MAX_IDLE=300

file=$1
mac=$2
res=0

# 1. Get recent update time
line=$(grep "^$mac" "$file" 2>/dev/null | tail -n 1)

if [ -n "$line" ]; then
	# 2. Check idle time
	pre_up=$(echo "$line" | cut -d' ' -f2)
	cur_up=$(cut -d '.' -f1 /proc/uptime)
	delta=$((cur_up - pre_up))

	if [ "$delta" -lt "$MAX_IDLE" ]; then
		res=1
	fi

	# 3. Update
	sed -i "s/^$mac.*/$mac $cur_up/" "$file"
else
	# 2. Check uptime
	cur_up=$(cut -d '.' -f1 /proc/uptime)
	if [ "$cur_up" -lt "$MAX_IDLE" ]; then
		# Ignore update after boot
		echo 1
		exit 0
	fi

	# 3. Add new entry
	echo "$mac $cur_up" >>"$file"
fi

echo "$res"
