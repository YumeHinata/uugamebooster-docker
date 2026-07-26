#!/bin/ash

art_dev=$(grep "ART" /proc/mtd | awk -F: '{print $1}')
[ -z "${art_dev}" ] && return

dd if=/dev/${art_dev} of=/dev/null &> /dev/null

nand_dts=$(ls /sys/devices/platform/soc/| grep nand)
nand_dev=$(cat /sys/devices/platform/soc/${nand_dts}/nand_devid)

echo ${nand_dev}_$(cat /sys/class/mtd/${art_dev}/ecc_strength)"_"$(cat /sys/class/mtd/${art_dev}/max_bitflip)
