#!/bin/sh


# stub function
mipctl_add_guest_wifi_interface() {
    return 0
}

mipctl_del_guest_wifi_interface() {
    return 0
}

[ -f /usr/sbin/mipctl_priv.sh ] && {
    . /usr/sbin/mipctl_priv.sh
}


OPT=$1
case $OPT in
	add_guest_wifi_if)
		mipctl_add_guest_wifi_interface
		return $?
	;;
    del_guest_wifi_if)
		mipctl_del_guest_wifi_interface
		return $?
	;;
	* )
		echo "[mipctl] unkown opts"
		return 0
	;;
esac

