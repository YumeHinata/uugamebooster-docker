#!/bin/sh

if [ "`cat /proc/xiaoqiang/model`" != "R4A" ] ;then
	echo 512 > /proc/sys/vm/min_free_kbytes
	sync
	echo 3 > /proc/sys/vm/drop_caches
fi


if [ -e /dev/cgroup/cpu/plugin ]
then
	for pid in $(cat /dev/cgroup/cpu/plugin/tasks); do
		kill -9 $pid
	done
fi
