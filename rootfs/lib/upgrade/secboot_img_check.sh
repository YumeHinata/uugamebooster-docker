#!/bin/sh


_logger() {
    echo -e "[secboot image check] $*" > /dev/console
    return
}

_verify_common_mtd() {
    local package="$1"
    local mtd="$2"
    local check_times=3
    local file

    case "$mtd" in
        sbl*)           file="xbl_nand.elf";;
        xbl*)           file="xbl_nand.elf";;
        tz*)            file="tz.mbn";;
        devcfg*)        file="devcfg.mbn";;
        uboot*)         file="uboot.bin";;
        firmware|root*) file="root.ubi";;
        *)
            _logger "not support verify $mtd"
            return 0
            ;;
    esac

    # check
    mkxqimage -c "$image_path" -f "$file" || return 0

    # copy to kernel
    echo "$package $file" > /sys/sec_upgrade/miwifi_sec_auth || {
        _logger "$file verify failed"
        return 1
    }

    # check result
    while true; do
        usleep 1000
        grep -qsw "$file ok" /sys/sec_upgrade/miwifi_sec_auth && {
            _logger "$file verify success"
            return 0
        }

        check_times=$((check_times - 1))
        [ "0" = "$check_times" ] && break;
    done
    _logger "$file verify failed"
    return 1
}

_verify_extra_mtd() {
    local package="$1"
    local name="$2"
    local pem_file="/usr/share/xiaoqiang/verify_extra_mtd.pem"
    local work_dir="/tmp/upgrade_${name}"
    local ubi_file="$work_dir/${name}.ubi"
    local digest_file="$work_dir/${name}.digest"
    local mount_dir="$work_dir/mount_${name}"
    local sign_file="$mount_dir/${name}.digest.sign"
    local mtd_dev mtd_path file file_list clean_cmd
    local ubi_dev="1"

    # check
    mkxqimage -c "$package" -f "${name}.ubi" || return 0

    # prepare
    [ ! -f "$pem_file" ] && { _logger "not find pem file"; return 1; }
    /etc/init.d/mi_docker stop
    echo 3 > /proc/sys/vm/drop_caches
    rm -rf "$work_dir"
    mkdir -p "$work_dir"
    clean_cmd="rm -rf $work_dir;"
    mkdir -p "$mount_dir"

    # get ubi file
    mkxqimage -x "$package" -f "${name}.ubi" -n > "$ubi_file"
    [ ! -f "$ubi_file" ] && { _logger "not find $ubi_file"; return 1; }

    # create nand simulator
    insmod nandsim.ko first_id_byte=0x20 second_id_byte=0xa2 third_id_byte=0x00 fourth_id_byte=0x15 #64MiB, 2048 bytes page;
    clean_cmd="rmmod nandsim.ko; $clean_cmd"
    mtd_dev=$(grep -w "NAND simulator" /proc/mtd | awk -F: '{print substr($1,4)}')
    [ -z "$mtd_dev" ] && {
        _logger "nand simulator init failed"
        eval "$clean_cmd"
        return 1
    }

    # attach ubi
    mtd_path="/dev/mtd${mtd_dev}"
    mtd erase "$mtd_path"
    mtd write "$ubi_file" "$mtd_path"
    ubiattach -m "$mtd_dev" -d "$ubi_dev" -O 2048
    clean_cmd="ubidetach -m $mtd_dev; $clean_cmd"

    # mount ubi
    ubiblock -c /dev/ubi${ubi_dev}_0
    mount -o ro -t squashfs /dev/ubiblock${ubi_dev}_0 "$mount_dir"
    clean_cmd="umount $mount_dir; $clean_cmd"
    [ ! -f "$sign_file" ] && {
        _logger "not find sign: $sign_file"
        eval "$clean_cmd"
        return 1
    }

    # verify
    file_list=$(find "$mount_dir" -type f | LC_COLLATE=C sort)
    for file in $file_list; do
        [ "$file" = "$sign_file" ] && continue
        sha256sum "$file" | cut -d ' ' -f 1 >> "$digest_file"
    done

    if openssl dgst -sha256 -verify "$pem_file" -signature "$sign_file" "$digest_file"; then
        _logger "$name verify success"
        eval "$clean_cmd"
        return 0
    else
        _logger "$name verify failed"
        eval "$clean_cmd"
        echo 3 > /proc/sys/vm/drop_caches
        /etc/init.d/mi_docker restart
        return 1
    fi
}

_verify_all_common_mtd() {
    local image_path="$1"
    local common_mtd="xbl tz devcfg uboot root"
    local mtd

    for mtd in $common_mtd; do
        _verify_common_mtd "$image_path" "$mtd" || return 1
    done
    return 0
}

_verify_all_extra_mtd() {
    local image_path="$1"
    local extra_mtd="docker central"
    local mtd

    for mtd in $extra_mtd; do
        _verify_extra_mtd "$image_path" "$mtd" || return 1
    done
    return 0
}

# $FAIL_ACTION: "fail_return" or "fail_reboot"
# $IMAGE_PATH: /tmp/custom.bin
secboot_upgd_sign_check() {
    local fail_action="$1"
    local image_path="$2"
    local check_image="$3"
    local res=1

    _logger "strat secboot upgrade verify: $image_path $check_image"
    [ -f "$image_path" ] && {
        case "$check_image" in
        xbl|tz|devcfg|uboot|root)
            _verify_common_mtd "$image_path" "$check_image" && res=0
            ;;
        docker|central)
            _verify_extra_mtd "$image_path" "$check_image" && res=0
            ;;
        *)
            _verify_all_common_mtd "$image_path" && _verify_all_extra_mtd  "$image_path" && res=0
            ;;
        esac
    }

    _logger "finish secboot upgrade verify with $res"
    [ "fail_reboot" = "$fail_action" ] && [ "1" = "$res" ] && {
        reboot
    }
    return $res
}
