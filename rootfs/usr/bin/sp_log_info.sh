#!/bin/ash

readonly INSTANT_LOG="/tmp/stat_points/rom.log"
readonly INSTANT_KW="stat_points_instant"

dTag="sp_lib"
dMod="local1.info"
gMod=$dMod
gKey=
gMsg=
gIns=
gFile=
gMaxLines=99999

usage() {
	cat <<-EOF
		Usage: $0 OPTION...
		log stat points msg.

		  -k      message keyword
		  -m      message payload
		  -p      use period mode instead event mode
		  -i      instant mode, ignore message convert and upload directly
		  -f      specifies the file path where messages are saved
		  -l      max of file lines
	EOF
}

log_to_file() {
	local file="$1"
	local msg="$2"
	local max_lines="$3"

	local dir="${file%/*}"
	[ ! -d "$dir" ] &&  mkdir -p "$dir"

	if [ -f "$file" ]; then
		local count=$(cat $file | wc -l)
		if [ "$count" -ge "$max_lines" ]; then
			local start=`expr $count - $max_lines + 2`
			sed -i -n "${start},\$p" "$file"
		fi
	fi

	echo "$msg" | tee -a "$file" >/dev/null
}

while getopts "k:m:f:l:pih" opt; do
	case "${opt}" in
	k)
		gKey=${OPTARG}
		;;
	m)
		gMsg=${OPTARG}
		;;
	p)
		gMod="local2.info"
		;;
	i)
		gIns=1
		;;
	f)
		gFile=${OPTARG}
		;;
	l)
		gMaxLines=${OPTARG}
		;;
	h)
		usage
		exit
		;;
	\?)
		usage >&2
		exit 1
		;;
	esac
done
shift $((OPTIND-1))

if [ -z "$gKey" ] || [ -z "$gMsg" ]; then
	exit 2
fi

if [ -n "$gFile" ]; then
	log_to_file "$gFile" "$gMsg" "$gMaxLines"
elif [ -n "$gIns" ]; then
	mkdir -p "${INSTANT_LOG%/*}"
	echo "$INSTANT_KW $gKey=$gMsg"|tee -a "$INSTANT_LOG" >/dev/null
else
	logger -p "$gMod" -t "$dTag" "$gKey=$gMsg"
fi
