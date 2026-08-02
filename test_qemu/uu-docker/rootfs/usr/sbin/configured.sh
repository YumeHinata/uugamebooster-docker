#!/bin/sh

[ -d /etc/hotplug.d/inited ] && {
	for script in $(ls /etc/hotplug.d/inited/* 2>&-); do (
		[ -f $script ] && . $script
	); done
}

