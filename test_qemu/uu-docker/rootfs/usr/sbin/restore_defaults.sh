#!/bin/sh

nvram set restore_defaults=1
nvram set web_restore=1
nvram commit

[ -f "/usr/sbin/at_cmd.sh" ] && {
	/usr/sbin/at_cmd.sh "restore_defaults"
	sleep 5
}

reboot
