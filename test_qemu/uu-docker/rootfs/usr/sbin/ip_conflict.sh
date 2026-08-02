#!/bin/sh
. /lib/functions/network.sh

lanip="192.168.31.1"
lanip_int=0
lannetmask="255.255.255.0"
lannetmask_int=0
lannetmask_bits=24

miotip="192.168.32.1"
miotip_int=0
miotnetmask="255.255.255.0"
miotnetmask_int=0
miotnetmask_bits=24

guestip="192.168.33.1"
guestip_int=0
guestnetmask="255.255.255.0"
guestnetmask_int=0
guestnetmask_bits=24

wanip_array=""
wanip_int_array=""
wannetmask_array=""
wannetmask_int_array=""
wannetmask_bits_array=""

chk_net_array=""
min_netmask_bits=24

usage() {
	echo "usage:"
	echo "ip_conflict.sh wan :"
	echo "    Detect lan/miot/guest-wifi/wan ip conflict and return new lanip if conflict."
	echo "    Otherwise resolve miot/guest-wifi/wan ip conflict and save new miot/guest-wifi ip to /etc/config/network."
	echo "ip_conflict.sh wan modify :"
	echo "    Detect lan/wan ip conflict, save new lanip to /etc/config/network if conlict, then return."
	echo "    Otherwise resolve miot/guest-wifi/wan ip conflict and save new miot/guest-wifi ip to /etc/config/network."
	echo "ip_conflict.sh br-lan :"
	echo "    Resolve lan/miot/guest-wifi ip conflict, and save new miot/guest-wifi ip to /etc/config/network."
	echo "ip_conflict.sh br-lan check <new_lanip> <new_lannetmask>:"
	echo "    Check new_lanip/new_lannetmask with wan ip conflict, return 1 if conflict, otherwise return 0."
	echo "ip_conflict.sh guest <guestip> <guestnetmask> :"
	echo "    Check guest-wifi/miot/lan/wan ip conflict, return new guest-wifi ip if conflict."
	echo ""
}

log() {
	logger -p info -t "ip_conflict.sh" "$1"
	#echo "ip_conflict.sh $1" > /dev/console
}

ip_aton() {
	echo $1 | awk '{c=256;split($0,str,".");print str[4]+str[3]*c+str[2]*c^2+str[1]*c^3}'
}

ip_ntoa() {
	local a1=$(($1 & 0xFF))
	local a2=$((($1 >> 8) & 0xFF))
	local a3=$((($1 >> 16) & 0xFF))
	local a4=$((($1 >> 24) & 0xFF))
	echo "$a4.$a3.$a2.$a1"
}

is_same_subnet() {
	local ip1=$1
	local ip2=$2
	local netmask1=$3
	local netmask2=$4

	[ $(($ip1 & $netmask1)) -eq $(($ip2 & $netmask1)) ] && return 1
	[ $(($ip1 & $netmask2)) -eq $(($ip2 & $netmask2)) ] && return 1

	return 0
}

calc_netmask_bits() {
	local bits=0
	local a=$(echo "$1" | awk -F "." '{print $1" "$2" "$3" "$4}')

	for num in $a
	do
		while [ $num != 0 ]
		do
			local re=$(($num % 2))
			[ $re -ne 0 ] && bits=$(($bits + 1))
			num=$(($num / 2))
		done
	done
	echo $bits
}


#get_new_ip() {
#	local ip=$1
#	local netmask1_bits=$2
#	local netmask2_bits=$3
#	local bits=$4
#
#	[ $netmask1_bits -gt $netmask2_bits ] && netmask1_bits=$netmask2_bits
#	[ $netmask1_bits -gt 32 -o $netmask1_bits -lt 8 ] && echo 0 && return
#	[ -z "$bits" ] && bits=3
#
#	bits=$(($bits << (32 - $netmask1_bits)))
#	echo $(($ip ^ $bits))
#}

get_lan_ip_info() {
	if [ -z "$1" -o -z "$2" ]; then
		lanip=$(uci -q get network.lan.ipaddr)
		lannetmask=$(uci -q get network.lan.netmask)
	else
		lanip=$1
		lannetmask=$2
	fi
	lanip_int=$(ip_aton $lanip)
	lannetmask_int=$(ip_aton $lannetmask)
	lannetmask_bits=$(calc_netmask_bits $lannetmask_int)
}

get_miot_ip_info() {
	miotip=$(uci -q get network.miot.ipaddr)
	miotnetmask=$(uci -q get network.miot.netmask)
	miotip_int=$(ip_aton $miotip)
	miotnetmask_int=$(ip_aton $miotnetmask)
	miotnetmask_bits=$(calc_netmask_bits $miotnetmask_int)
}

get_guest_ip_info() {
	if [ -z "$1" -o -z "$2" ]; then
		guestip=$(uci -q get network.guest.ipaddr)
		guestnetmask=$(uci -q get network.guest.netmask)
	else
		guestip=$1
		guestnetmask=$2
	fi
	[ -z "$guestip" -o -z "$guestnetmask" ] && return

	guestip_int=$(ip_aton $guestip)
	guestnetmask_int=$(ip_aton $guestnetmask)
	guestnetmask_bits=$(calc_netmask_bits $guestnetmask_int)
}

get_wan_ip_info() {
	wanip_array=""
	wanip_int_array=""
#	wannetmask_array=""
	wannetmask_int_array=""
	wannetmask_bits_array=""

	for interface in `awk '/^config.*interface/{print$3}' /etc/config/network|tr "\'\"" " " `
	do
		[ "$interface" = "wan" -o "${interface:0:4}" = "wan_" ] && {
			local wan_subnet=""
			network_get_subnet wan_subnet $interface

			eval "$(ipcalc.sh $wan_subnet)"
			[ -n "$IP" -a "$IP" != "0.0.0.0" ] && {
				wanip_array=${wanip_array}" $IP"
				wanip_int_array=${wanip_int_array}" $(ip_aton $IP)"
#				wannetmask_array=${wannetmask_array}" $NETMASK"
				wannetmask_int_array=${wannetmask_int_array}" $(ip_aton $NETMASK)"
				wannetmask_bits_array=${wannetmask_bits_array}" $PREFIX"
			}
		}
	done
}

lan_wan_ip_conflict_check() {
	local ip_int=$1
	local netmask_int=$2
	local i=1

	log "lan_wan_ip_conflict_check: wanlist=$wanip_array"
	for element in $wanip_int_array
	do
		local wanip_int=$element
		local wannetmask_int=$(echo $wannetmask_int_array | cut -d ' ' -f $i)
		local wanip=$(echo $wanip_array | cut -d ' ' -f $i)
		log "lan_wan_ip_conflict_check:$i, $wanip"
		is_same_subnet $ip_int $wanip_int $netmask_int $wannetmask_int
		[ "$?" = "1" ] && {
			log "ip conflict with wan: $wanip"
			return 1
		}
		let i=i+1
	done

	return 0
}

common_ip_conflict_check() {
	local ip1_int=$1
	local ip1netmask_int=$2
	local ip2_int=$3
	local ip2netmask_int=$4

	[ -z "$ip1_int" -o -z "$ip1netmask_int" -o -z "$ip2_int" -o -z "$ip2netmask_int" ] && return 0

	is_same_subnet $ip1_int $ip2_int $ip1netmask_int $ip2netmask_int
	[ "$?" = "1" ] && return 1
	return 0
}

check_net() {
	local ignore_net=$1
	local tmp_net
	local i=1

	chk_net_array=""
	min_netmask_bits=24

	[ "$ignore_net" != "lan" ] && {
		[ -n "$lanip" -a -n "$lannetmask" ] && {
			tmp_net=$lanip_int   #$(($lanip_int & $lannetmask_int))
			chk_net_array=${chk_net_array}" $tmp_net"
			[ $lannetmask_bits -lt $min_netmask_bits ] && min_netmask_bits=$lannetmask_bits
		}
	}
	[ "$ignore_net" != "miot" ] && {
		[ -n "$miotip" -a -n "$miotnetmask" ] && {
			tmp_net=$miotip_int   #$(($miotip_int & $miotnetmask_int))
			chk_net_array=${chk_net_array}" $tmp_net"
			[ $miotnetmask_bits -lt $min_netmask_bits ] && min_netmask_bits=$miotnetmask_bits
		}
	}
	[ "$ignore_net" != "guest" ] && {
		[ -n "$guestip" -a -n "$guestnetmask" ] && {
			tmp_net=$guestip_int   #$(($guestip_int & $guestnetmask_int))
			chk_net_array=${chk_net_array}" $tmp_net"
			[ $guestnetmask_bits -lt $min_netmask_bits ] && min_netmask_bits=$guestnetmask_bits
		}
	}

	for element in $wanip_int_array
	do
		local wanip_int=$element
		#local wannetmask_int=$(echo $wannetmask_int_array | cut -d ' ' -f $i)
		local wannetmask_bits=$(echo $wannetmask_bits_array | cut -d ' ' -f $i)

		tmp_net=$wanip_int   #$(($wanip_int & $wannetmask_int))
		log "check_net: $i, $(ip_ntoa $tmp_net)"
		chk_net_array=${chk_net_array}" $tmp_net"
		[ $wannetmask_bits -lt $min_netmask_bits ] && min_netmask_bits=$wannetmask_bits

		let i=i+1
	done

	log "min_netmask_bits: $min_netmask_bits"
}

calc_new_ip() {
	local conflict_ip=$1
	local prefix1=$(echo $conflict_ip | awk -F "." '{print $1}')
	local prefix2=$(echo $conflict_ip | awk -F "." '{print $2}')
	local prefix3=$(echo $conflict_ip | awk -F "." '{print $3}')
	local prefix4=$(echo $conflict_ip | awk -F "." '{print $4}')
	local idx=0

	while true; do
		if [ $min_netmask_bits -ge 24 ]; then
			prefix3=$idx
		elif [ $min_netmask_bits -ge 16 -a $min_netmask_bits -lt 24 ]; then
			prefix1=10
			prefix2=$idx
		else
			if [ "$prefix1" = "10" ]; then
				prefix1=172
				let prefix2=16+idx
			else
				prefix1=10
				prefix2=$idx
			fi
		fi

		local newip="$prefix1.$prefix2.$prefix3.$prefix4"
		eval "$(ipcalc.sh $newip/$min_netmask_bits)"
		local newnet=$NETWORK
		local newnet_int=$(ip_aton $NETWORK)
		local flg=0
		log "calc_new_ip: $chk_net_array"
		for element in $chk_net_array
		do
			eval "$(ipcalc.sh $element/$min_netmask_bits)"
			local tmpnet_int=$(ip_aton $NETWORK)
			log "calc_new_ip: $NETWORK, $newnet"
			[ "$tmpnet_int" = "$newnet_int" ] && flg=1 && break
		done
		[ $flg -eq 0 ] && {
			log "calc newip($newip) successed!"
			echo $newip
			return 
		}

		let idx=idx+1
	done
}

get_new_ip() {
	local conflict="$1-$2"
	local newip="0.0.0.0"

	check_net $1
	case $conflict in
		"lan-wan")
			newip=$(calc_new_ip $lanip $lanip_int)
			;;
		"miot-wan" | "miot-lan")
			newip=$(calc_new_ip $miotip $miotip_int)
			;;
		"guest-wan" | "guest-lan" | "guest-miot")
			newip=$(calc_new_ip $guestip $guestip_int)
			;;
	esac
	echo $newip
}

#################### wan ip changed   #######################
wan_conflict_detection() {
	local newip

	log "wan_conflict_detection======>"
	get_lan_ip_info
	get_miot_ip_info
	get_guest_ip_info
	get_wan_ip_info

	#br-lan: check br-lan/wan ip
	if [ -n "$lanip" -a -n "$lannetmask" ]; then
		log "br-lan($lanip/$lannetmask) and wan ip conflict check:"
		lan_wan_ip_conflict_check $lanip_int $lannetmask_int
		[ "$?" = "1" ] && {
			log "br-lan and wan ip conflict!"
			newip=$(get_new_ip lan wan)
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "change br-lan ipaddr: $lanip --> $newip!"
				echo "$newip"
			else
				log "calc new ip for br-lan failed!"
				echo "0.0.0.0"
			fi
			return
		}
	fi

	#miot: check miot/wan ip
	if [ -n "$miotip" -a -n "$miotnetmask" ]; then
		log "miot($miotip/$miotnetmask) and wan ip conflict check:"
		lan_wan_ip_conflict_check $miotip_int $miotnetmask_int
		[ "$?" = "1" ] && {
			log "miot and wan ip conflict!"
			newip=$(get_new_ip miot wan)
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "change miot ipaddr: $miotip --> $newip!"
				uci set network.miot.ipaddr=$newip
				uci commit network
				ubus call network reload
				/usr/sbin/ip_changed.sh miot 2>/dev/null
			else
				log "calc new ip for miot failed!"
			fi

			echo "0.0.0.0"
			return
		}
	fi

	#guest-wifi: check guest-wifi/wan ip
	if [ -n "$guestip" -a -n "$guestnetmask" ]; then
		log "guest-wifi($guestip/$guestnetmask) and wan ip conflict check:"
		lan_wan_ip_conflict_check $guestip_int $guestnetmask_int
		[ "$?" = "1" ] && {
			log "guest-wifi and wan ip conflict!"
			newip=$(get_new_ip guest wan)
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "change guest-wifi ipaddr: $guestip --> $newip!"
				uci set network.guest.ipaddr=$newip
				uci commit network
				ubus call network reload
				/usr/sbin/ip_changed.sh guest 2>/dev/null
			else
				log "calc new ip for guest-wifi failed!"
			fi
		}
	fi

	echo "0.0.0.0"
}

#set new lan ip
wan_conflict_resolution() {
	log "wan_conflict_resolution======>"

	local newip=$(wan_conflict_detection)

	[ -z "$newip" -o "$newip" = "0.0.0.0" ] && {
		echo "0.0.0.0"
		return
	}

	log "1 save br-lan ipaddr to /etc/config/network: $lanip --> $newip"
	uci set network.lan.ipaddr=$newip
	uci commit network
	echo $newip
}

#################### br-lan ip changed  #######################
lan_conflict_resolution() {
	local newip

	log "lan_conflict_resolution======>"
	get_lan_ip_info
	get_miot_ip_info
	get_guest_ip_info
	get_wan_ip_info

	#br-lan: check br-lan/wan ip
	if [ -n "$lanip" -a -n "$lannetmask" ]; then
		log "br-lan($lanip/$lannetmask) and wan ip conflict check:"
		lan_wan_ip_conflict_check $lanip_int $lannetmask_int
		[ "$?" = "1" ] && {
			log "2 br-lan and wan ip conflict!"
			newip=$(get_new_ip lan wan)
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "2 change br-lan ipaddr: $lanip --> $newip!"
				echo "$newip"
			else
				log "2 calc new ip for br-lan failed!"
				echo "0.0.0.0"
			fi
			return
		}
	fi

	#miot: check miot/br-lan ip
	if [ -n "$miotip" -a -n "$miotnetmask" ]; then
		log "miot($miotip/$miotnetmask) and br-lan($lanip/$lannetmask) ip conflict check:"
		common_ip_conflict_check $miotip_int $miotnetmask_int $lanip_int $lannetmask_int
		[ "$?" = "1" ] && {
			log "miot and br-lan ip conflict!"
			newip=$(get_new_ip miot lan)
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "save miot ipaddr to /etc/config/network: $miotip --> $newip!"
				uci set network.miot.ipaddr=$newip
				uci commit network
				ubus call network reload
				/usr/sbin/ip_changed.sh miot 2>/dev/null
			else
				log "calc new ip for miot failed!"
			fi
			echo "0.0.0.0"
			return
		}
	fi

	#guest-wifi: check guest-wifi/br-lan ip
	if [ -n "$guestip" -a -n "$guestnetmask" ]; then
		log "guest-wifi($guestip/$guestnetmask) and br-lan($lanip/$lannetmask) ip conflict check:"
		common_ip_conflict_check $guestip_int $guestnetmask_int $lanip_int $lannetmask_int
		[ "$?" = "1" ] && {
			log "guest-wifi and br-lan ip conflict!"
			newip=$(get_new_ip guest lan)
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "save guest-wifi ipaddr to /etc/config/network: $guestip --> $newip!"
				uci set network.guest.ipaddr=$newip
				uci commit network
				ubus call network reload
				/usr/sbin/ip_changed.sh guest 2>/dev/null
			else
				log "calc new ip for guest-wifi failed!"
			fi
		}
	fi

	echo "0.0.0.0"
}

lan_conflict_check() {
	[ -z "$1" -o -z "$2" ] && echo 0 && return

	get_lan_ip_info $1 $2
	get_wan_ip_info
	lan_wan_ip_conflict_check $lanip_int $lannetmask_int
	echo "$?"
}

#################### guest-wifi ip changed  #######################
guest_conflict_resolution() {
	local newip

	[ -z "$1" -o -z "$2" ] && return

	log "guest_conflict_resolution======>"
	get_guest_ip_info $1 $2
	get_lan_ip_info
	get_miot_ip_info
	get_wan_ip_info

	#wan: check guest-wifi/wan ip
	if [ -n "$guestip" -a -n "$guestnetmask" ]; then
		log "guest-wifi($guestip/$guestnetmask) and wan ip conflict check:"
		lan_wan_ip_conflict_check $guestip_int $guestnetmask_int
		[ "$?" = "1" ] && {
			log "guest-wifi and wan ip conflict!"
			newip=$(get_new_ip "guest" "wan")
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "change guest-wifi ipaddr: $guestip --> $newip!"
				echo "$newip"
			else
				log "calc new ip for guest-wifi failed!"
				echo "0.0.0.0"
			fi
			return
		}
	fi

	#br-lan: check guest-wifi/br-lan ip
	if [ -n "$lanip" -a -n "$lannetmask" ]; then
		log "guest-wifi and br-lan ip conflict check:"
		common_ip_conflict_check $guestip_int $guestnetmask_int $lanip_int $lannetmask_int
		[ "$?" = "1" ] && {
			log "guest-wifi($guestip/$guestnetmask) and br-lan($lanip/$lannetmask) ip conflict!"
			newip=$(get_new_ip "guest" "lan")
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "change guest-wifi ipaddr: $guestip --> $newip!"
				echo "$newip"
			else
				log "1 calc new ip for guest-wifi failed!"
				echo "0.0.0.0"
			fi
			return
		}
	fi

	#guest-wifi: check guest-wifi/miot ip
	if [ -n "$miotip" -a -n "$miotnetmask" ]; then
		log "guest-wifi($guestip/$guestnetmask) and miot($miotip/$miotnetmask) ip conflict check:"
		common_ip_conflict_check $guestip_int $guestnetmask_int $miotip_int $miotnetmask_int
		[ "$?" = "1" ] && {
			log "guest-wifi and miot ip conflict!"
			newip=$(get_new_ip "guest" "miot")
			if [ -n "$newip" -a "$newip" != "0.0.0.0" ]; then
				log "change guest-wifi ipaddr: $guestip --> $newip!"
				echo "$newip"
			else
				log "2 calc new ip for guest-wifi failed!"
				echo "0.0.0.0"
			fi
			return
		}
	fi

	echo "0.0.0.0"
}

[ $# -lt 1 ] && usage && exit 1
chg=$1

case $chg in
	wan)
		if [ "$2" = "modify" ]; then
			wan_conflict_resolution
		else
			wan_conflict_detection
		fi
		;;
	br-lan)
		if [ "$2" = "check" ]; then
			lan_conflict_check $3 $4
		else
			lan_conflict_resolution
		fi
		;;
	guest-wifi)
		guest_conflict_resolution $2 $3
		;;
	*)
		usage
		;;
esac
