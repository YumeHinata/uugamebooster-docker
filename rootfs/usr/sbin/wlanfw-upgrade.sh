#!/bin/bash
#
#  Copyright (c) 2018 Qualcomm Technologies, Inc.
#
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#
. /lib/functions.sh

# exit when any command fails
# stops the execution if a command has an error
# set -e

device="$(cat /tmp/sysinfo/model)"
new_fw_path="$1"
tmpdir="$(mktemp -d)"
tmpfile="$(mktemp)"
img="$2"

part_name="0:WIFIFW"
status="failed"
ubi_part_name="rootfs"

# if a subdevice is specified, eg. qcn9000
if [ "$#" -eq 3 ]; then
	subdev="$3"
fi

if echo "$device" | grep -q "IPQ807" ; then
	lib_fw=/lib/firmware/IPQ8074/WIFI_FW
	emmc_part=$(find_mmc_part $part_name 2> /dev/null)
	nand_part=$(find_mtd_part $part_name 2> /dev/null)
elif  echo "$device" | grep -q "IPQ6018" ; then
	lib_fw=/lib/firmware/IPQ6018/WIFI_FW
	nand_part=$(find_mtd_part $ubi_part_name 2> /dev/null)
	if [ -z "$nand_part" ]; then
		emmc_part=$(find_mmc_part $part_name 2> /dev/null)
	else
		part_name=ubi_part_name
	fi
elif  echo "$device" | grep -q "IPQ5018" ; then
	lib_fw=/lib/firmware/IPQ5018/WIFI_FW
	wififw_part=$(cat /proc/mtd | grep $part_name)
	mtd_dev=$(echo $wififw_part | awk '{print $1}' | sed 's/:$//')
	nor_flash=`find /sys/bus/spi/devices/*/mtd -name ${mtd_dev}`
	nand_part=$(find_mtd_part $ubi_part_name 2> /dev/null)
	if [ -z "$nand_part" ]; then
		emmc_part=$(find_mmc_part $part_name 2> /dev/null)
	else
		part_name=ubi_part_name
	fi
elif  echo "$device" | grep -q "IPQ9574" ; then
	lib_fw=/lib/firmware/IPQ9574/WIFI_FW
	nand_part=$(find_mtd_part $ubi_part_name 2> /dev/null)
	if [ -z "$nand_part" ]; then
		emmc_part=$(find_mmc_part $part_name 2> /dev/null)
	else
		part_name=ubi_part_name
	fi
elif  echo "$device" | grep -q "IPQ5332" ; then
	lib_fw=/lib/firmware/IPQ5332/WIFI_FW
	nand_part=$(find_mtd_part $ubi_part_name 2> /dev/null)
	if [ -z "$nand_part" ]; then
		emmc_part=$(find_mmc_part $part_name 2> /dev/null)
	else
		part_name=ubi_part_name
	fi
else
	echo "Unrecognized Device...\nCurrently Devices Supported: ipq807x & ipq6018 & ipq5018 & ipq9574 & ipq5332\n"
	exit 0;
fi

if [ -z "$new_fw_path" ]; then
	echo "Error:Firmware path is empty\n"
	echo "Usages:Please run as below command:\n"
	echo "wlanfw-upgrade.sh <path_to_fw_files> <fw_type(q6/m3/all)> <sub-device>\n"
	exit 0;
fi

printf " Copying firmware files to $tmpdir..\n"
cp -r $lib_fw/* $tmpdir/

if [ "$subdev" == "qcn9000" ] || [ "$subdev" == "qcn9224" ]; then
	if [ "$img" == "q6" ]; then
		printf " Copying $subdev Q6 images from $new_fw_path..\n"
		rm -rf $tmpdir/$subdev/amss.bin
		cp -r $new_fw_path/amss.bin $tmpdir/$subdev/
	elif [ "$img" == "m3" ]; then
		printf " Copying $subdev M3 images from $new_fw_path..\n"
		rm -rf $tmpdir/$subdev/m3.bin
		cp -r $new_fw_path/m3.bin $tmpdir/$subdev/
	else
		printf " Copying $subdev Q6 & M3 & all other files from $new_fw_path..\n"
		rm -f $tmpdir/$subdev/*
		cp $new_fw_path/* $tmpdir/$subdev/
	fi
elif [ "$subdev" == "qcn6122" ]; then
	printf " Copying $subdev M3 images from $new_fw_path..\n"
	rm -rf $tmpdir/$subdev/m3_*
	cp -r $new_fw_path/m3_* $tmpdir/$subdev/
elif [ "$subdev" == "qcn9160" ]; then
	printf " Copying $subdev M3 images from $new_fw_path..\n"
	rm -rf $tmpdir/$subdev/m3_*
	cp -r $new_fw_path/m3_* $tmpdir/$subdev/
elif [ "$img" == "q6" ]; then
	printf " Copying Q6 fw files from $new_fw_path..\n"
	rm -rf $tmpdir/q6_*
	cp -r $new_fw_path/q6_* $tmpdir/
elif [ "$img" == "m3" ]; then
	printf " Copying M3 fw files from $new_fw_path..\n"
	rm -rf $tmpdir/m3_*
	cp -r $new_fw_path/m3_* $tmpdir/
elif [ "$img" == "iu" ]; then
	printf " Copying IU fw files from $new_fw_path..\n"
	rm -rf $tmpdir/iu_*
	cp -r $new_fw_path/iu_* $tmpdir/
else
	printf " Copying Q6 , M3/IU fw and other files from $new_fw_path..\n"
	# For Internal Radio
	rm -f $tmpdir/*
	cp $new_fw_path/* $tmpdir/

	# For Attached Radio's
	subdev="qcn6122"
	if [[ -d "$lib_fw/$subdev" && -d "$tmpdir/$subdev" ]]; then
		printf " Copying $subdev M3/IU images from $new_fw_path/$subdev..\n"
		rm -f $tmpdir/$subdev/*
		cp $new_fw_path/$subdev/* $tmpdir/$subdev/
	else
		subdev=""
		if [ -d "$lib_fw/qcn9000" ]; then
			subdev="qcn9000"
			rm -f $tmpdir/$subdev/*
			cp $new_fw_path/* $tmpdir/$subdev/
		fi

		if [ -d "$lib_fw/qcn9224" ]; then
			subdev="qcn9224"
			rm -f $tmpdir/$subdev/*
			cp $new_fw_path/* $tmpdir/$subdev/
		fi

		if [ -d "$lib_fw/qcn9160" ]; then
			subdev="qcn9160"
			rm -f $tmpdir/$subdev/*
			cp $new_fw_path/* $tmpdir/$subdev/
		fi
	fi
fi

printf " Preparing squashfs image..\n"
mksquashfs4  $tmpdir/  $tmpfile -nopad -noappend -root-owned -comp xz -Xpreset 9 -Xe -Xlc 0 -Xlp 2 -Xpb 2 -Xbcj arm -b 256k -processors 1

if [ -n "$emmc_part" ]; then
	emmc_blk=$( echo $emmc_part | cut -c 6-15)
	emmc_partsize=$( cat /sys/class/block/$emmc_blk/size )

	printf " Unmounting $emmc_part \n"
	umount $emmc_part || true

	printf " Flashing squashfs image on $emmc_part ..\n"
	dd if=/dev/zero of=$emmc_part bs=512 count=$emmc_partsize
	dd if=$tmpfile of=$emmc_part

	printf " Mounting $emmc_part \n"
	/bin/mount -t squashfs $emmc_part $lib_fw
	status="completed"
elif [ -n "$nor_flash" ]; then
	printf " Unmounting $$mtd_dev \n"
	umount $lib_fw || true
	mtd -e /dev/$mtd_dev write $tmpfile /dev/$mtd_dev
	/bin/mount -t squashfs /dev/${mtd_dev//mtd/mtdblock} $lib_fw
	status="completed"
elif [ -n "$nand_part" ]; then
	mtdpart=$(grep "\"$part_name\"" /proc/mtd | awk -F: '{print $1}')

	size=$(ls -s $tmpfile | awk '{print $1 "KiB"}')

	printf " Unmounting $lib_fw \n"
	umount $lib_fw || true

	if [ "$part_name" == "0:WIFIFW" ]; then
		printf " Flash squashfs image on $nand_part\n"
		ubidetach -f -p /dev/$mtdpart || true
		sync

		printf " Formatting /dev/$mtdpart \n"
		ubiformat /dev/$mtdpart

		printf " Attaching ubi on /dev/$mtdpart \n"
		ubiattach -p /dev/${mtdpart}
		ubimkvol /dev/ubi1 -N wifi_fw -s $size
		ubiupdatevol /dev/ubi1_0 $tmpfile
	else
		printf " Flash squashfs image on wifi_fw vol in rootfs partition\n"
		ubirmvol /dev/ubi0 -N wifi_fw
		ubimkvol /dev/ubi0 -N wifi_fw -s $size
		volumes=$(ls /sys/class/ubi/ubi0/ | grep ubi._.*)
		for vol in ${volumes}
		do
			[ -f /sys/class/ubi/${vol}/name ] && name=$(cat /sys/class/ubi/${vol}/name)
			[ ${name} == "wifi_fw" ] && ubiupdatevol /dev/${vol} $tmpfile && break
		done

	fi

	ubi_part=$(find_mtd_part wifi_fw 2> /dev/null)

	printf " Mounting $ubi_part\n"
	/bin/mount -t squashfs $ubi_part $lib_fw
	status="completed"
else
	printf " Flash Type Not Supported \n"
fi

printf " Cleaning up temp files..\n"
rm -rf  $tmpfile $tmpdir/
printf " wlan fw upgrade $status !\n"
