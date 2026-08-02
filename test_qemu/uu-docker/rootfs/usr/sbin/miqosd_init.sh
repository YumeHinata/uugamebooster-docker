#!/bin/sh

QOS_FORWARD="miqos_fw"   # for XiaoQiang forward
QOS_INOUT="miqos_io"   # for XiaoQiang input/output
QOS_IP="miqos_id"	# for IP mark
QOS_FLOW="miqos_cg"   # for package flow recognization
QOS_TV="miqos_tv"   # for TV/MIBOX

IPT="/usr/sbin/iptables -w -t mangle"
SIP=$(uci -q get network.lan.ipaddr)
SMASK=$(uci -q get network.lan.netmask)
SIPMASK="$SIP/$SMASK"

guest_SIP=$(uci -q get network.guest.ipaddr)
guest_SMASK=$(uci -q get network.guest.netmask)
guest_SIPMASK="$guest_SIP/$guest_SMASK"

wan_if=$(uci -q get network.wan.ifname)

#路由优先端口，逗号分隔，最多15组，准许iptables-multiport规范
#port: 22 ssh/53 dns/123 ntp/1880:1890 msgagent/5353 mdns/514 syslog-ng
xq_prio_tcp_ports="22,53,123,1880:1890,5353"
xq_prio_udp_ports="53,123,514,1880:1890,5353"

#micloud port, 小强源端口,33330~33570 (共计240个端口，TODO:后续可用cgroup统一解决)
xq_micloud_ports="33330:33570"

#skb mark 占用情况：qos(17 bits：0xffff8000), mwan3(6 bits: 0x3f00), parentctrl(4 bits: 0xf), uu plugin(4 bits: 0xf0)
mark_GAME="0x00100000/0x00f00000"
mark_WEB="0x00200000/0x00f00000"
mark_VIDEO="0x00300000/0x00f00000"
mark_DOWNLOAD="0x00400000/0x00f00000"

mark_HIGHEST="0x00010000/0x000f0000"
mark_SPECIAL="0x00020000/0x000f0000"
mark_HOST_NET="0x00030000/0x000f0000"
mark_GUEST_NET="0x00040000/0x000f0000"
mark_XQ="0x00050000/0x000f0000"

#这里恢复相应的cotent-mark到skb上
mask_HWQOS="0x8000"
mask_QOS="0xffff8000"
mask_FLOW_TYPE="0x00f00000"
mask_SUBNET_TYPE="0x000f0000"
mask_IP_TYPE="0xff000000"
mask_FWD_TYPE="0xffff0000"

#punish if web connbytes > 3MB default
# closed if web connbytes = 0
threshold_of_punishment=3

#ip_set
set_skip_hwqos_name="SKIP_HWNAT4QOS"

#清除ipt规则
del_ipt_chain()
{
	for i in $(uci -q get miqos.settings.hook_point);do
		for j in $(uci -q get miqos."$i".name);do
			$IPT -D "$i" -j "$j" &>/dev/null
		done
	done

	#清除QOS规则链
	$IPT -F $QOS_FORWARD &>/dev/null
	$IPT -X $QOS_FORWARD &>/dev/null

	$IPT -F $QOS_INOUT &>/dev/null
	$IPT -X $QOS_INOUT &>/dev/null

	$IPT -F $QOS_FLOW &>/dev/null
	$IPT -X $QOS_FLOW &>/dev/null

	$IPT -F $QOS_IP &>/dev/null
	$IPT -X $QOS_IP &>/dev/null

	$IPT -F $QOS_TV &>/dev/null
	$IPT -X $QOS_TV &>/dev/null
}

create_ipt_chain()
{
	#新建QOS规则链
	$IPT -N $QOS_FORWARD &>/dev/null
	$IPT -N $QOS_FLOW &>/dev/null
	$IPT -N $QOS_IP &>/dev/null
	$IPT -N $QOS_INOUT &>/dev/null
	$IPT -N $QOS_TV &>/dev/null

	#连接QOS的几条规则链
	for i in $(uci -q get miqos.settings.hook_point);do
		for j in $(uci -q get miqos."$i".name);do
			$IPT -A "$i" -j "$j" &>/dev/null
		done
	done
}

#构建INOUT的规则框架 {}
create_input_rules()
{
	#已经打过mark的skb，直接return，不继续匹配后续规则。因为pptp的报文打过mark，经过pptp层的处理后，会进入output链，导致之前的mark被清掉。
	$IPT -A $QOS_INOUT -m mark ! --mark 0x0/$mask_FWD_TYPE -j RETURN

	$IPT -A $QOS_INOUT -j CONNMARK --restore-mark --nfmask $mask_QOS --ctmask $mask_QOS
	cgroup_mark=$(lsmod 2>/dev/null|grep xt_cgroup_MARK)
	if [ -n "$cgroup_mark" ]; then
		$IPT -A $QOS_INOUT -j cgroup_MARK --mask $mask_SUBNET_TYPE
		$IPT -A $QOS_INOUT -j CONNMARK --save-mark --nfmask $mask_QOS --ctmask $mask_QOS
	fi
	$IPT -A $QOS_INOUT -m mark ! --mark 0/$mask_SUBNET_TYPE -j RETURN
	#------------------------------
	#INOUT特定规则
	#APP<->XQ数据流
	$IPT -A $QOS_INOUT -p tcp -m multiport --ports $xq_prio_tcp_ports -j MARK --set-mark $mark_HIGHEST
	$IPT -A $QOS_INOUT -p udp -m multiport --ports $xq_prio_udp_ports -j MARK --set-mark $mark_HIGHEST
	#小强micloud备份源端口,TCP
	$IPT -A $QOS_INOUT -p tcp -m multiport --sports $xq_micloud_ports -j MARK --set-mark $mark_XQ
	#cgroup_mark=`lsmod 2>/dev/null|grep xt_cgroup_MARK `
	#if [ -n "$cgroup_mark" ]; then
	#    $IPT -A $QOS_INOUT -j cgroup_MARK --mask $mask_SUBNET_TYPE
	#fi
	#XQ默认数据类型
	$IPT -A $QOS_INOUT -m mark --mark 0/$mask_SUBNET_TYPE -j MARK --set-mark $mark_XQ
	#------------------------------
	$IPT -A $QOS_INOUT -j CONNMARK --save-mark --nfmask $mask_QOS --ctmask $mask_QOS
}
#构建FORWARD的规则框架 {}
create_forward_rules()
{
	if [ "$threshold_of_punishment" -gt "0" ]; then
		#connection bytes pulishment for web-flow
		threshold=$((threshold_of_punishment * 1024 * 1024))
		$IPT -A $QOS_FORWARD -m connmark --mark $mark_WEB -m connbytes --connbytes $threshold --connbytes-dir both --connbytes-mode bytes -j CONNMARK --set-mark $mark_DOWNLOAD
	fi

	$IPT -A $QOS_FORWARD -j CONNMARK --restore-mark --nfmask $mask_QOS --ctmask $mask_QOS
	$IPT -A $QOS_FORWARD -m mark --mark 0/$mask_FLOW_TYPE -j flowMARK --ip "$SIP" --mask "$SMASK"
	$IPT -A $QOS_FORWARD -j CONNMARK --save-mark --nfmask $mask_QOS --ctmask $mask_QOS
	$IPT -A $QOS_FORWARD -m mark ! --mark 0/$mask_IP_TYPE -j RETURN
	#------------------------------
	#FORWARD特定规则
	# to set ip mark
	$IPT -A $QOS_FORWARD -m mark --mark 0/$mask_IP_TYPE -j $QOS_IP
	# to set video/audio mark
	$IPT -A $QOS_FORWARD -m mark --mark 0/$mask_FLOW_TYPE -j $QOS_TV
	#to set special flow mark
	$IPT -A $QOS_FORWARD -m mark --mark 0/$mask_FLOW_TYPE -j flowMARK --ip "$SIP" --mask "$SMASK"
	#to set flow mark by tcp/udp port/tos
	$IPT -A $QOS_FORWARD -m mark --mark 0/$mask_FLOW_TYPE -j $QOS_FLOW
	#to set device type mark
	$IPT -A $QOS_FORWARD -m mark --mark 0/$mask_SUBNET_TYPE -j MARK --set-mark $mark_HOST_NET
	#------------------------------
	$IPT -A $QOS_FORWARD -j CONNMARK --save-mark --nfmask $mask_QOS --ctmask $mask_QOS
}

create_guest_rules_for_pc()
{
	[ -n "$guest_SIP" ] && [ -n "$guest_SMASK" ] && {
		$IPT -C "$QOS_IP" -d "$guest_SIPMASK" -j MARK --set-mark-return "$mark_GUEST_NET" || {
			$IPT -A "$QOS_IP" -d "$guest_SIPMASK" -j MARK --set-mark-return "$mark_GUEST_NET"
		}

		$IPT -C "$QOS_IP" -s "$guest_SIPMASK" -j MARK --set-mark-return "$mark_GUEST_NET" || {
			$IPT -A "$QOS_IP" -s "$guest_SIPMASK" -j MARK --set-mark-return "$mark_GUEST_NET"
		}
	}
}

#构建IP规则链
create_rules_for_pc()
{
	#构建GUEST网络的IP规则
	create_guest_rules_for_pc

	$IPT -A $QOS_IP -s "$SIPMASK" -j IP4MARK --addr src
	$IPT -A $QOS_IP -d "$SIPMASK" -j IP4MARK --addr dst
}

#构建数据流FLOW规则链
#1.game,2.web,3.video,4.download
create_rules_for_data_flows()
{
	CLASS_NUM=4
	for c in $(seq $CLASS_NUM); do
		TCP_PORTS=$(uci -q get miqos.p"$c".tcp_ports)
		UDP_PORTS=$(uci -q get miqos.p"$c".udp_ports)
		TOS=$(uci -q get miqos.p"$c".tos)
		if [ -n "$TCP_PORTS" ]; then
			$IPT -A $QOS_FLOW -p tcp -m mark --mark 0/$mask_FLOW_TYPE -m multiport --ports "$TCP_PORTS" -j MARK --set-mark-return 0x"$c"00000/$mask_FLOW_TYPE
		fi
		if [ -n "$UDP_PORTS" ]; then
			$IPT -A $QOS_FLOW -p udp -m mark --mark 0/$mask_FLOW_TYPE -m multiport --ports "$UDP_PORTS" -j MARK --set-mark-return 0x"$c"00000/$mask_FLOW_TYPE
		fi
		if [ -n "$TOS" ]; then
			$IPT -A $QOS_FLOW -p udp -m mark --mark 0/$mask_FLOW_TYPE -m tos --tos "$TOS" -j MARK --set-mark-return 0x"$c"00000/$mask_FLOW_TYPE
		fi
	done
}

#since 2015-8-10, content mark startup at init script.
#恒定开启http-content分流功能
#http_content_type_mark.sh on >/dev/null 2>&1

#开启web流量惩罚
create_rules_for_web_punish()
{
	proc_web_punish="/proc/sys/net/ipv4/mark_web_flow/mark_web_exceed_flow"
	if [ -f "$proc_web_punish" ]; then
		echo "$threshold_of_punishment:$mask_FLOW_TYPE:$mark_WEB:$mark_DOWNLOAD" > $proc_web_punish
	fi
}

#开启ipset, 使一部分IP不进HWQOS,而直接走soft-QoS
create_rules_for_hwqos()
{
	hwnat_dev="/dev/hwnat0"
	if [ -e /usr/sbin/ipset ] && [ -c $hwnat_dev ]; then
		/usr/sbin/ipset -q $set_skip_hwqos_name
		/usr/sbin/ipset -q create $set_skip_hwqos_name hash:ip

		$IPT -D PREROUTING -m set --match-set $set_skip_hwqos_name src -j MARK --set-mark $mask_HWQOS/$mask_HWQOS
		$IPT -I PREROUTING -m set --match-set $set_skip_hwqos_name src -j MARK --set-mark $mask_HWQOS/$mask_HWQOS
		$IPT -D POSTROUTING -m set --match-set $set_skip_hwqos_name dst -j MARK --set-mark $mask_HWQOS/$mask_HWQOS
		$IPT -I POSTROUTING -m set --match-set $set_skip_hwqos_name dst -j MARK --set-mark $mask_HWQOS/$mask_HWQOS
	fi
}

#dev redirect
dev_redirect_setting()
{
	[ -f /proc/sys/net/dev_redirect_map ] && [ -n "$wan_if" ] && {
		echo "+ $wan_if ifb0" > /proc/sys/net/dev_redirect_map
	}
}

create_ipt_for_miqos()
{
	#清除ipt规则
	del_ipt_chain

	#新建QOS规则链
	create_ipt_chain

	#构建INOUT的规则框架 {}
	create_input_rules

	#构建FORWARD的规则框架 {}
	create_forward_rules

	#构建IP规则链
	create_rules_for_pc

	#构建数据流FLOW规则链: 1.game,2.web,3.video,4.download
	create_rules_for_data_flows

	#开启web流量惩罚
	create_rules_for_web_punish

	#开启ipset, 使一部分IP不进HWQOS,而直接走soft-QoS
	create_rules_for_hwqos

	#dev redirect
	dev_redirect_setting
}

del_ipt_for_miqos()
{
	#清除ipt规则
	del_ipt_chain
}


# main
case "$1" in
init)
	if [ -z "$2" ]; then
		create_ipt_for_miqos
	else
		create_"$2"_rules_for_pc
	fi
	;;
clear)
	del_ipt_for_miqos
	;;
*)
	;;
esac
exit 0