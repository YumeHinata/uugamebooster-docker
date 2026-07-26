#!/bin/sh

[ -e /lib/modules/`uname -r`/mtd_stresstest.ko ] || return
[ -e /lib/modules/`uname -r`/mtd_readtest.ko ] || return

flashtest=`nvram get auto_flashtest`
if [ "$flashtest" = "once" ];then
	nvram unset auto_flashtest
	nvram commit
	echo "flashtest start only one time"
else
	echo "auto_flashtest unset"
	return
fi

while true;do
	boot_done=$(cat /tmp/boot_check_done)
	[ "$boot_done" = "boot_done" ] && break
	sleep 2
done

function print_uptime_date() {
	echo -n `uptime` >> /data/resofflashtest
	echo -n "    " >> /data/resofflashtest
	echo -n `date` >> /data/resofflashtest
	echo -n "    " >> /data/resofflashtest
	sync
}

function check_err_stress() {
	res=`dmesg | grep "mtd_stresstest: finished"`
	if [ -z "$res" ]; then
		xqled systest_fail
		nvram set flashtestres=STRESS_ERROR
		nvram commit
		return 1
	fi
	dmesg -c > /dev/null
	return 0
}

function check_err_read() {
	res=`dmesg | grep "mtd_readtest: finished"`
	if [ -z "$res" ]; then
		xqled systest_fail
		nvram set flashtestres=READ_ERROR
		nvram commit
		return 1
	fi
	dmesg -c > /dev/null
	return 0
}

xqled systest_ongo

stress_cnt=$1
let stress_cnt=$stress_cnt*90/100/2  #硬件同学测试需求：测试两次，且单次测试次数为寿命的90%的一半
read_cnt=$2

# use rootfs for flashtest
curr_os=`nvram get flag_last_success`
mtd_test=`cat /proc/mtd | grep "rootfs_1" | cut -d ":" -f 1 | cut -d "d" -f 2`
[ "0" != "$curr_os" ] && let mtd_test--
echo "flashtest uses mtd$mtd_test" >> /data/resofflashtest

stress_cnt_done=`nvram get stress_cnt_done`
[  "done" != "$stress_cnt_done" ] && {
	insmod /lib/modules/`uname -r`/mtd_stresstest.ko dev="$mtd_test" count=$stress_cnt
	rmmod mtd_stresstest.ko
	check_err_stress
	if [ "$?" = "0" ]; then
		print_uptime_date
		echo "    flash stress test done[count=$stress_cnt]" >> /data/resofflashtest
		sync
	else
		print_uptime_date
		echo "    flash stress test ERROR!!" >> /data/resofflashtest
		return 1
	fi
	[ "$stress_cnt" = "$stress_cnt_done" ] && nvram set stress_cnt_done=done
	[ -z $stress_cnt_done ] && nvram set stress_cnt_done=$stress_cnt
	nvram commit
}

cnt=0
while true;do
	let cnt++
	[ $cnt -gt $read_cnt ] && break
	
	insmod /lib/modules/`uname -r`/mtd_readtest.ko dev="$mtd_test"
	rmmod mtd_readtest.ko
	check_err_read
	if [ "$?" = "0" ]; then
		if [ $(($cnt % 100)) = 0 ]; then
			print_uptime_date
			echo "    flash read test done[count:$cnt]" >> /data/resofflashtest
			sync
		fi
	else
		print_uptime_date
		echo "    flash read test ERROR!![count:$cnt]" >> /data/resofflashtest
		return 1
	fi
done

print_uptime_date
echo "    flash read test SUCCESS!![$read_cnt]" >> /data/resofflashtest

xqled sys_ok

nvram set restore_defaults=1
nvram commit
return

