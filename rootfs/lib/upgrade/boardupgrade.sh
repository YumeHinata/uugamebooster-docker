#!/bin/sh
#

# R3600 upgrade file

. /lib/upgrade/libupgrade.sh

klogger() {
    local msg1="$1"
    local msg2="$2"

    if [ "$msg1" = "-n" ]; then
        echo -n "$msg2" >> /dev/kmsg 2>/dev/null
        echo -n "$msg2"
    else
        echo "$msg1" >> /dev/kmsg 2>/dev/null
        echo "$msg1"
    fi

    return 0
}

detach_mtd(){
    local name="$1"
    local devn=$(grep \"${name}\" /proc/mtd | awk -F: '{print substr($1,4)}')

    if [ "$name" = "other" ];then
        for path in $(mount | grep "other/docker" | awk '{print $3}' | sort -r); do
            umount $path > /dev/null 2>&1
        done
        umount /data/$name > /dev/null 2>&1
        dmsetup remove other_enc > /dev/null 2>&1
        umount /data/other_vol > /dev/null 2>&1
    else
        umount /data/$name > /dev/null 2>&1
    fi

    [ -e /dev/ubi$devn ] && ubidetach -d $devn
}

board_prepare_upgrade() {
    # gently stop pppd, let it close pppoe session
    ifdown wan
    timeout=5
    while [ $timeout -gt 0 ]; do
        pidof pppd >/dev/null || break
        sleep 1
        let timeout=timeout-1
    done

    # down backhauls
    #ifconfig eth3 down
    #ifconfig wl01 down
    #ifconfig wl11 down

    # clean up upgrading environment
    # call shutdown scripts with some exceptions
    wait_stat=0
    klogger "@Shutdown service "
    for i in /etc/rc.d/*; do
        # filter out K01reboot-wdt and K99umount network dnsmasq

        case $i in
            *reboot-wdt | *umount | *network | *dnsmasq | *xqled)
                klogger "$i skipped"
                continue
            ;;
        esac

        [ -x "$i" ] || continue

        # wait for high-priority K* scripts to finish
        if echo "$i" | grep -qE "K7"; then
            if [ $wait_stat -eq 0 ]; then
                wait
                sleep 2
                wait_stat=1
            fi
            klogger "  service $i shutdown 2>&1"
            $i shutdown 2>&1
        else
            klogger "  service $i shutdown 2>&1 &"
            $i shutdown 2>&1
        fi
    done

    detach_mtd "docker"
    detach_mtd "central"
    detach_mtd "other"

    # flush cache and dump meminfo
    sync
    echo 3>/proc/sys/vm/drop_caches
    klogger "@dump meminfo"
    klogger "`cat /proc/meminfo | xargs`"
}

board_start_upgrade_led() {
    /usr/sbin/xqled sys_ota > /dev/null 2>&1
}

board_system_upgrade() {
    local filename=$1
	local secList="sbl1 tz devcfg cdt uboot firmware docker central"
	
	# update sections
	for sec in $secList; do
		flash_section $sec $filename
	done
	
	# update bootconfig
	[ -f "/tmp/bootconfig_update_needed" ] && {
		update_booconfig
		rm -rf "/tmp/bootconfig_update_needed"
	}
	
}
