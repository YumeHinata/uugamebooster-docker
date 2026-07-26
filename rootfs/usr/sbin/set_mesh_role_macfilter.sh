#!/bin/sh

MAC=$1

#清理mesh白名单接口
clear_mesh_white_macfilter()
{
	#获取mesh白名单列表
	list=$(uci -q get macfilter.wan.meshlist)
	[ -z "$list" ] && return
	for macaddr in $list
	do
		#查询mesh是否在arp表里
		cat /proc/net/arp | grep -i $macaddr >/dev/null
		[ $? -ne 0 ] && {
			#不在arp表里的，且mesh列表满了清掉
			local uci_mac=$(echo "$macaddr" | tr ':' '_')
			uci -q del macfilter.$uci_mac
			uci del_list macfilter.wan.meshlist=$macaddr
			local macfilter_num=$(uci -q get macfilter.wan."$mode"num)
			local mesh_filter_num=$(uci -q get macfilter.wan.mesh_filter_num)
			#数量递减
			[ $macfilter_num -gt 0 ] && uci -q set macfilter.wan."$mode"num=$((macfilter_num-1))
			[ $mesh_filter_num -gt 0 ] && uci -q set macfilter.wan.mesh_filter_num=$((mesh_filter_num-1))
			uci commit macfilter
		}
	done
}

set_mesh_device_macfilter()
{
	local macaddr=$1
	local mac_uci=$(echo "$macaddr" | tr ':' '_')
	local mode="white"
	local macfilter_enable=$(uci -q get macfilter.wan.enable)
	local macfilter_mode=$(uci -q get macfilter.wan.mode)
	local macfilter_num=$(uci -q get macfilter.wan."$mode"num)
	local maxrulenum=$(uci -q get macfilter.wan.maxrulenum)
	local mesh_filter_num=$(uci -q get macfilter.wan.mesh_filter_num)
	local max_mesh_num=9

	[ -z "$mac_uci" ] && return

	[ -z "$macfilter_num" ] && macfilter_num=0
	[ -z "$mesh_filter_num" ] && mesh_filter_num=0
	[ -z "$maxrulenum" ] && maxrulenum=64

	#mesh数量大于9个，需要清理mesh列表
	[ $mesh_filter_num -gt $max_mesh_num ] && {
		clear_mesh_white_macfilter
		macfilter_num=$(uci -q get macfilter.wan."$mode"num)
		mesh_filter_num=$(uci -q get macfilter.wan.mesh_filter_num)
		[ -z "$macfilter_num" ] && macfilter_num=0
		[ -z "$mesh_filter_num" ] && mesh_filter_num=0
	}

	[ $macfilter_num -gt $maxrulenum ] && return

	#mesh数量大于9个,不需要添加
	[ $mesh_filter_num -gt $max_mesh_num ] && return
	#mesh mac已经存在不需要添加
	uci -q get macfilter.$mac_uci >/dev/null && return

	uci batch <<-EOF
		set macfilter.$mac_uci=$mode
		set macfilter.$mac_uci.name=' @Mesh'
		set macfilter.wan."$mode"num=$((macfilter_num+1))
		set macfilter.wan.mesh_filter_num=$((mesh_filter_num+1))
		set macfilter.$mac_uci.ismesh=1
		add_list macfilter.wan.meshlist=$macaddr
		commit macfilter
	EOF

	[ "$macfilter_enable" = "1" -a "$macfilter_mode" = "$mode" ] && {
		/usr/sbin/macfilter add $mode $macaddr
	}
}

set_mesh_device_macfilter $MAC

