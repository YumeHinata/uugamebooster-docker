#!/bin/sh
#
#  Copyright (c) 2022 Qualcomm Technologies, Inc.
#
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#
. /lib/functions.sh

licensepath="$1"
upgrade_mode="$2"
temp="/tmp"
license="/license"


part_name="0:LICENSE"


reboot_wifi()
{
	# Rebooting wifi to download the updated license files
	/sbin/wifi load
}


if [ -z "$licensepath" ]; then
	echo "Error: License path is empty"
	echo "Usages: Please run as below command:"
	echo "license-pfm-upgarde.sh <path_to_license_files> <ADD/UPGRADE>"
	echo "Default mode is ADD, use UPGRADE to replace entire license partition"
	exit 1;
fi

files=$(ls $licensepath/*.pfm | wc -l)

if [ $files -eq 0 ]; then
	echo "No license files in given directory $licensepath"
	exit 1;
fi

if [ "$upgrade_mode" != "UPGRADE" ]; then
        upgrade_mode="ADD"
fi

use_rootfs=$(cat /sys/module/license_manager/parameters/use_license_from_rootfs)

if [ $use_rootfs -gt 0 ]; then
	echo "Trying to upgrade license files in rootfs" > /dev/console
	. /etc/init.d/license-pfm
	read_licenses_from_rootfs $licensepath $upgrade_mode
	reboot_wifi
	exit 0;
fi

mtdblock=$(find_mtd_part 0:LICENSE)

if [ -z "$mtdblock" ]; then
        # read from mmc
	mtdblock=$(find_mmc_part 0:LICENSE)
fi

if [ -z "$mtdblock" ]; then
	echo "No License partition in device to upgrade" > /dev/console
        echo "Trying to upgrade license files in rootfs" > /dev/console
	. /etc/init.d/license-pfm
        read_licenses_from_rootfs $licensepath $upgrade_mode
	reboot_wifi
	exit 0;
fi

#------------------------------------------------------#

printf " Copying  license files to ${temp}/license/..\n"

mkdir -p ${temp}/license
rm -f ${temp}/license/*

#Copying license files from license partition
if [ "$upgrade_mode" == "ADD" ]; then


	mkdir -p ${temp}/license_part
	rm -f ${temp}/license_part/*
	rm -f ${temp}/license.tar.gz

	dd if=${mtdblock} of=${temp}/license.tar.gz bs=2K conv=sync
	tar -xzf ${temp}/license.tar.gz -C ${temp}/license_part/.


	cp ${temp}/license_part/*.pfm ${temp}/license/. 2> /dev/null

fi

#Copying user given license files
cp ${licensepath}/*.pfm ${temp}/license/. 2> /dev/null

#------------------------------------------------------#

printf " Preparing License tar file..\n"

rm -f ${temp}/license.tar.gz
cd ${temp}/license/

tar -czf ${temp}/license.tar.gz *.pfm

cd ../../

printf " Writing to flash..\n"

dd if=${temp}/license.tar.gz of=${mtdblock}

#------------------------------------------------------#

printf " Reloading the license partition..\n"

/etc/init.d/license-pfm boot

reboot_wifi
#------------------------------------------------------#

printf " Cleaning up temp files..\n"
rm -rf $temp/license $temp/license_part

printf " PFM licene upgrade done! \n"
