#!/bin/ash

netmode=$(uci -q get xiaoqiang.common.NETMODE)

if [ "$netmode" = "whc_cap" ] || [ "$netmode" = "whc_re" ] || \
		[ "$netmode" = "controller" ] || [ "$netmode" = "agent" ]; then
	echo "#whc general show:"
	mesh_cmd role|xargs echo

	echo "#brctl showmacs detail info:"
	brctl showmacs br-lan

	echo "#brctl showstp detail info:"
	brctl showstp br-lan

	echo "### swconfig info"
	swconfig dev switch0 show

	if [ "$netmode" = "agent" ]; then
		echo "# var run topomon"
		for file in $(ls /var/run/topomon); do echo "[$file]:";cat $file; done
	fi
fi
