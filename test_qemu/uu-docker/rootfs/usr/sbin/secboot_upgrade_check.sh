#!/bin/sh

FAIL_ACTION=$1
IMAGE_PATH=$2
CHECK_IMAGE=$3

secboot_upgd_sign_check() {
    return 0
}

grep -qsw '1' /proc/xiaoqiang/secboot_enable && [ -f /lib/upgrade/secboot_img_check.sh ] && {
    . /lib/upgrade/secboot_img_check.sh
}

# $FAIL_ACTION: "fail_return" or "fail_reboot"
# $IMAGE_PATH: /tmp/custom.bin
secboot_upgd_sign_check "$FAIL_ACTION" "$IMAGE_PATH" "$CHECK_IMAGE"
