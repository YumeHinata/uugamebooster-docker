IWPRIV="/usr/sbin/iwpriv"
WIFITOOL="/usr/sbin/wifitool"
ACSREPORT_FILE="/tmp/acsreport_file"
ACSREPORT_FILE_NO_QUOTES=/tmp/acsreport_file
#PUSH_JSON="matool --method notify --params  {\\\"type\\\":46,\\\"cscore\\\":%d,\\\"schannel\\\":\\\"%s\\\",\\\"sscore\\\":%d,\\\"cchannel\\\":\\\"%s\\\",\\\"ranking\\\":%d}"

show_usage()
{
	echo "$0 usage:"
	echo "$0 <wl0> <scan | getresult>"
	echo "	scan: scan channel, if channel selected is different with current channel, do matool cmd"
	echo "	getresult: get scan result after scanning"
	echo "	example: $0 wl0 scan"
	echo ""
}

#scan channel, if channel selected is different with current channel, do matool cmd
scan_channel()
{
	local n=0
	${IWPRIV} ${IFNAME} acsreport 1 > /dev/null

	while [ 1 ]
	do
		acs_state=`${IWPRIV} ${IFNAME} get_acs_state | awk -F ':' '{print $2}'`
		if [ ${acs_state} -eq 0 ]; then
			break;
		fi
		# scan over than 15 seconds, break out
		if [ $n -gt 15 ]; then
			break;
		fi
		
		n=$((n+1))
		sleep 1
	done

	${WIFITOOL} ${IFNAME} acsreport > ${ACSREPORT_FILE}

	local cchannel=$(iwinfo ${IFNAME} freqlist | grep "*" | awk '{printf "%d\n",$5}')
	local cscore="`awk -F ' ' '/ '"${cchannel}"')/{print $7}' ${ACSREPORT_FILE}`"
	local schannel=$cchannel
	local sscore=$cscore
	local ranking=1
	local numchannel="`awk -F ' ' '/number of channels/{print $10}' ${ACSREPORT_FILE}`"
	local linenum="`cat ${ACSREPORT_FILE} | wc -l`"
	linenum=$(($linenum-5))

	if [ ${numchannel} -gt ${linenum} ]; then
		numchannel=${linenum}
	fi

	for chan_index in `seq ${numchannel}`
	do
		line=$((15+$chan_index))
		channel_index="`awk -F '[\\\) ]+' 'NR=='${line}'{print $3}' ${ACSREPORT_FILE}`"
		score_index="`awk -F ' ' 'NR=='${line}' {print $7}' ${ACSREPORT_FILE}`"
		if [ ${score_index} -lt ${cscore} ]; then
			ranking=$(($ranking+1))
		fi
		if [ ${sscore} -gt ${score_index} ]; then
			sscore=$score_index
			schannel=$channel_index
		fi
	done

	tmp_score=$(expr $cscore - 20)

	if [ ${sscore} -gt ${tmp_score} ]; then
		schannel=${cchannel}
		sscore=${cscore}
	else
		push_json="matool --method notify --params  {\"type\":\"46\",\"cscore\":\"${cscore}\",\"schannel\":\"${schannel}\",\"sscore\":\"${sscore}\",\"cchannel\":\"${cchannel}\",\"ranking\":\"${ranking}\"}"
		echo ${push_json}
		eval ${push_json}
	fi

	return 0
}

get_scan_result()
{
	${WIFITOOL} ${IFNAME} acsreport > ${ACSREPORT_FILE}

	if [ ! -f ${ACSREPORT_FILE} ]; then
		return 1;
	fi

	local cchannel=$(iwinfo ${IFNAME} freqlist | grep "*" | awk '{printf "%d\n",$5}')
	local cchannel_line=$(expr $cchannel + 15)
	local cscore=$(awk NR==${cchannel_line} ${ACSREPORT_FILE_NO_QUOTES} | awk '{print $7}')
	local numchannel=$(cat ${ACSREPORT_FILE} | grep -c '(')
	local sscore=$cscore
	local schannel=$cchannel

	#remove channel 12 and 13
	numchannel=$(expr $numchannel - 2)

	for i in `seq ${numchannel}`
	do
		line=$((15+$i))
		channel_index="`awk -F '[\\\) ]+' 'NR=='${line}'{print $3}' ${ACSREPORT_FILE}`"
		score_index="`awk -F ' ' 'NR=='${line}'{print $7}' ${ACSREPORT_FILE}`"
		echo "Channel ${channel_index} : Score = ${score_index}"
		if [ ${sscore} -gt ${score_index} ]; then
			sscore=$score_index
			schannel=$channel_index
		fi
	done

	tmp_score=$(expr $cscore - 20)
	if [ ${sscore} -gt ${tmp_score} ]; then
		schannel=${cchannel}
		sscore=${cscore}
	fi

	echo "Current Channel ${cchannel} : Score = ${cscore}"
	echo "Select Channel ${schannel} : Score = ${sscore}"
	echo ""
	return 0
}

if [ ! $# -eq 2 ]; then
	show_usage
	exit 1
fi

IFNAME=$1
OPT=$2

[ "${IFNAME}" == "" ] && exit 1

[ "${OPT}" == "" ] && exit 1

#main
case $OPT in
	scan)
		scan_channel
		exit 0
	;;

	getresult)
		get_scan_result
		exit 0
	;;

	* )
		show_usage
		exit 0
	;;
esac

