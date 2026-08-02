#!/bin/sh

klogger() {
	local msg1="$1"
	local msg2="$2"

	if [ "$msg1" = "-n" ]; then
		echo -n "$msg2" >> /dev/kmsg 2>/dev/null
	else
		echo "$msg1" >> /dev/kmsg 2>/dev/null
	fi

	return 0
}

hndmsg() {
	if [ -n "$msg" ]; then
		echo "$msg"
		echo "$msg" >> /dev/kmsg 2>/dev/null

		echo $log > /proc/sys/kernel/printk
		stty intr ^C
		exit 1
	fi
}

uperr() {
	exit 1
}

pipe_upgrade_generic() {
	local package=$1
	local segment_name=$2
	local mtd_dev=mtd$3
	local ret=0

	mkxqimage -c $package -f $segment_name
	if [ $? -eq 0 ]; then
		klogger -n "Burning $segment_name to $mtd_dev ..."

		exec 9>&1

		local pipestatus0=`( (mkxqimage -x $package -f $segment_name -n || echo $? >&8) | \
			mtd write - /dev/$mtd_dev ) 8>&1 >&9`
		if [ -z "$pipestatus0" -a $? -eq 0 ]; then
			ret=0
		else
			ret=1
		fi
		exec 9>&-
	fi

	return $ret
}

pipe_upgrade_uboot() {
	if [ $1 ]; then
		pipe_upgrade_generic $2 uboot.bin $1
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

pipe_upgrade_crash() {
	if [ $1 ]; then
		pipe_upgrade_generic $2 crash.bin $1
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

pipe_upgrade_kernel() {
	if [ $1 ]; then
		pipe_upgrade_generic $2 uImage.bin $1
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

pipe_upgrade_rootfs_ubi() {
	local mtd_dev=mtd$1
	local package=$2
	local segment_name="root.ubi"

	mkxqimage -c $package -f $segment_name
	if [ $? -eq 0 -a $1 ]; then
		local segment_size=$(mkxqimage -c $package -f $segment_name)
		segment_size=${segment_size##*length = }
		segment_size=${segment_size%%, partition*}

		klogger -n "Burning rootfs image to $mtd_dev ..."

		exec 9>&1
		local pipestatus0=`((mkxqimage -x $package -f $segment_name -n || echo $? >&8) | \
			ubiformat /dev/$mtd_dev -f - -S $((segment_size)) -s 2048 -O 2048 -y) 8>&1 >&9`

		if [ -z "$pipestatus0" -a $? -eq 0 ]; then
			exec 9>&-
			klogger "Done"
		else
			exec 9>&-
			klogger "Error"
			uperr
		fi
	fi
}

pipe_upgrade_docker_ubi() {
	local mtd_dev=mtd$1
	local package=$2
	local segment_name="docker.ubi"

	mkxqimage -c $package -f $segment_name
	if [ $? -eq 0 -a $1 ]; then
		local segment_size=$(mkxqimage -c $package -f $segment_name)
		segment_size=${segment_size##*length = }
		segment_size=${segment_size%%, partition*}

		klogger -n "Burning docker image to $mtd_dev ..."

		exec 9>&1
		local pipestatus0=`((mkxqimage -x $package -f $segment_name -n || echo $? >&8) | \
			ubiformat /dev/$mtd_dev -f - -S $((segment_size)) -s 2048 -O 2048 -y) 8>&1 >&9`

		if [ -z "$pipestatus0" -a $? -eq 0 ]; then
			exec 9>&-
			klogger "Done"
		else
			exec 9>&-
			klogger "Error"
			uperr
		fi
	fi
}

pipe_upgrade_central_ubi() {
	local mtd_dev=mtd$1
	local package=$2
	local segment_name="central.ubi"

	mkxqimage -c $package -f $segment_name
	if [ $? -eq 0 -a $1 ]; then
		local segment_size=$(mkxqimage -c $package -f $segment_name)
		segment_size=${segment_size##*length = }
		segment_size=${segment_size%%, partition*}

		klogger -n "Burning central image to $mtd_dev ..."

		exec 9>&1
		local pipestatus0=`((mkxqimage -x $package -f $segment_name -n || echo $? >&8) | \
			ubiformat /dev/$mtd_dev -f - -S $((segment_size)) -s 2048 -O 2048 -y) 8>&1 >&9`

		if [ -z "$pipestatus0" -a $? -eq 0 ]; then
			exec 9>&-
			klogger "Done"
		else
			exec 9>&-
			klogger "Error"
			uperr
		fi
	fi
}

upgrade_uboot() {
	local mtd_dev=mtd$1

	if [ -f uboot.bin -a $1 ]; then
		klogger -n "Burning uboot image to $mtd_dev ..."
		mtd write uboot.bin /dev/$mtd_dev
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

upgrade_crash() {
	local mtd_dev=mtd$1

	if [ -f crash.bin -a $1 ]; then
		klogger -n "Burning crash image to $mtd_dev ..."
		mtd write crash.bin /dev/$mtd_dev
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

upgrade_kernel() {
	local mtd_dev=mtd$1

	if [ -f uImage.bin -a $1 ]; then
		klogger -n "Burning kernel image to $mtd_dev ..."
		mtd write uImage.bin /dev/$mtd_dev
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

upgrade_rootfs_ubi() {
	local mtd_dev=mtd$1

	if [ -f root.ubi -a $1 ]; then
		klogger -n "Burning rootfs image to $mtd_dev ..."
		ubiformat /dev/$mtd_dev -f root.ubi -s 2048 -O 2048 -y
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

verify_rootfs_ubifs() {
	local mtd_devn=$1
	local temp_ubi_data_devn=9
	klogger "Check if mtd$mtd_devn can be attached as an ubi device ..."
	# Try attach the device
	ubiattach /dev/ubi_ctrl -d $temp_ubi_data_devn -m $mtd_devn -O 2048
	if [ "$?" == "0" ]; then
		klogger "PASSED"
		ubidetach -d $temp_ubi_data_devn
		return 0
	else
		klogger "FAILED"
		return 1
	fi
}

# $1=mtd device name
# $2=src file name
upgrade_mtd_generic() {
	local mtd_dev="$1"
	local src_file="$2"

	if [ -f "$src_file" -a $mtd_dev ]; then
		klogger -n "Burning "$src_file" to $mtd_dev ..."
		mtd write "$src_file" $mtd_dev
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

# $1=mtd device name
# $2=src file name
upgrade_mtd_ubi() {
	local mtd_dev="$1"
	local src_file="$2"
	local mtd_node="$(grep $mtd_dev /proc/mtd | awk -F: '{print $1}')"

	if [ -f "$src_file" -a $mtd_dev ]; then
		klogger -n "Burning "$src_file" to $mtd_dev ..."
		ubiformat /dev/$mtd_node -f "$src_file" -s 2048 -O 2048 -y
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

do_flash_failsafe_partition() {
	local bin=$1
	local segment_name=$2
	local mtdname=$3
	local primaryboot
	local mtd_dev=""
	local ret=0

	mkxqimage -c $bin -f $segment_name
	if [ $? -eq 0 ]; then
		# Fail safe upgrade
		default_mtd=$mtdname
		[ -f /proc/boot_info/bootconfig0/$default_mtd/upgradepartition ] && {
			mtdname=$(cat /proc/boot_info/bootconfig0/$default_mtd/upgradepartition)
			primaryboot=$(cat /proc/boot_info/bootconfig0/$default_mtd/primaryboot)
			if [ $primaryboot -eq 0 ]; then
				echo 1 > /proc/boot_info/bootconfig0/$default_mtd/primaryboot
				echo 1 > /proc/boot_info/bootconfig1/$default_mtd/primaryboot
			else
				echo 0 > /proc/boot_info/bootconfig0/$default_mtd/primaryboot
				echo 0 > /proc/boot_info/bootconfig1/$default_mtd/primaryboot
			fi
		}

		mtd_dev=$(grep "\"${mtdname}\"" /proc/mtd | awk -F: '{print $1}')

		klogger -n "Burning $segment_name to $mtd_dev ..."

		exec 9>&1

		local pipestatus0=`( (mkxqimage -x $package -f $segment_name -n || echo $? >&8) | \
			mtd write - /dev/$mtd_dev ) 8>&1 >&9`
		if [ -z "$pipestatus0" -a $? -eq 0 ]; then
			ret=0
		else
			ret=1
		fi
		exec 9>&-

		[ $ret -eq 0 ] && {
			touch "/tmp/bootconfig_update_needed"
		}
	fi

	return $ret
}

do_flash_sbl1(){
	local package=$1
	local segment_name="xbl_nand.elf"
	local mtdpart=$(grep "\"0:SBL1\"" /proc/mtd | awk -F: '{print substr($1,4)}')

	if [ $1 ]; then
		pipe_upgrade_generic $package ${segment_name} $mtdpart
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

do_flash_tz() {
	local package=$1
	local segment_name="tz.mbn"

	do_flash_failsafe_partition ${package} ${segment_name} "0:QSEE"
	if [ $? -eq 0 ]; then
		klogger "Done"
	else
		klogger "Error"
		uperr
	fi
}

do_flash_devcfg(){
	local package=$1
	local segment_name="devcfg.mbn"

	do_flash_failsafe_partition ${package} ${segment_name} "0:DEVCFG"
	if [ $? -eq 0 ]; then
		klogger "Done"
	else
		klogger "Error"
		uperr
	fi
}

do_flash_ddr() {
	local package=$1
	local segment_name="cdt-AP-MI01.2_512M16_DDR4.bin"

	do_flash_failsafe_partition ${package} ${segment_name} "0:CDT"
	if [ $? -eq 0 ]; then
		klogger "Done"
	else
		klogger "Error"
		uperr
	fi
}

do_flash_uboot() {
	local package=$1
	local segment_name="uboot.bin"

	do_flash_failsafe_partition ${package} ${segment_name} "0:APPSBL"
	if [ $? -eq 0 ]; then
		klogger "Done"
	else
		klogger "Error"
		uperr
	fi
}

do_flash_firmware(){
	local package=$1
	local rootfs0_mtd=$(grep '"rootfs"' /proc/mtd | awk -F: '{print substr($1,4)}')
	local rootfs1_mtd=$(grep '"rootfs_1"' /proc/mtd | awk -F: '{print substr($1,4)}')

	local os_idx=$(nvram get flag_boot_rootfs)
	local rootfs_mtd_current=$(($rootfs0_mtd+${os_idx:-0}))
	local rootfs_mtd_target=$(($rootfs0_mtd+$rootfs1_mtd-$rootfs_mtd_current))

	pipe_upgrade_rootfs_ubi $rootfs_mtd_target $package
}

do_flash_docker(){
	local package=$1
	local mtd=$(grep '"docker"' /proc/mtd | awk -F: '{print substr($1,4)}')

	pipe_upgrade_docker_ubi $mtd $package
}

do_flash_central(){
	local package=$1
	local mtd=$(grep '"central"' /proc/mtd | awk -F: '{print substr($1,4)}')

	pipe_upgrade_central_ubi $mtd $package
}

do_flash_bootconfig() {
	local bootconfig=$1
	local mtdname=$2
	local append=""
	local mtdpart=$(grep "\"${mtdname}\"" /proc/mtd | awk -F: '{print $1}')
	local pgsz=$(cat /sys/class/mtd/${mtdpart}/writesize)

	klogger -n "Burning ${bootconfig}.bin to /dev/${mtdpart} ..."

	# Fail safe upgrade
	if [ -f /proc/boot_info/$bootconfig/getbinary_bootconfig ]; then
		cat /proc/boot_info/$bootconfig/getbinary_bootconfig > /tmp/${bootconfig}.bin
		dd if=/tmp/${bootconfig}.bin bs=${pgsz} conv=sync | mtd $append -e "/dev/${mtdpart}" write - "/dev/${mtdpart}"
	fi
}

flash_section() {
	local sec=$1
	local package=$2

	case "${sec}" in
		sbl1*) do_flash_sbl1 $package;;
		tz*) do_flash_tz $package;;
		devcfg*) do_flash_devcfg $package;;
		cdt*) do_flash_ddr $package;;
		uboot*) do_flash_uboot $package;;
		firmware*) do_flash_firmware $package;;
		docker*) do_flash_docker $package;;
		central*) do_flash_central $package;;
		*) echo "Section ${sec} ignored"; return 1;;
	esac

	#klogger "Flashed ${sec}"
}

update_booconfig(){
	do_flash_bootconfig bootconfig0 "0:BOOTCONFIG"
	if [ $? -eq 0 ]; then
		klogger "Done"
	else
		klogger "Error"
		uperr
	fi

	do_flash_bootconfig bootconfig1 "0:BOOTCONFIG1"
	if [ $? -eq 0 ]; then
		klogger "Done"
	else
		klogger "Error"
		uperr
	fi
}