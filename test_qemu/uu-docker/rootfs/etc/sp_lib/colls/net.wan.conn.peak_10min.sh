#!/bin/ash

if ! uci -q get network.wan.ifname|grep -qsE '[0-9]'; then
	exit 0
fi

max=$(sysctl -n net.netfilter.nf_conntrack_max)
cur=$(wc -l /proc/net/nf_conntrack|awk '{print $1}')

echo "${cur:-0} $max"|awk '{if($1/$2 > 0.95){print 1}else{print 0}}'
