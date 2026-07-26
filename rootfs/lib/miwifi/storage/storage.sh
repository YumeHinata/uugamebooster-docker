#!/bin/sh

###############################################
# File : storage.sh
# Version: 1.0
# Author: Hanjiayan
###############################################

. /lib/functions.sh

STORAGE_CONFIG_PATH="/tmp/etc"

log(){
	echo "[storage] $@" > /dev/console
}

trim(){
    local string="$1"
	local result=""

	result=$(echo "${string}" | grep -o "[^ ]\+\( \+[^ ]\+\)*")
	result=$(echo "${result}" | sed -r 's/[\t ]\+/ /g')
	result=$(echo "${result}" | sed -r 's/ /_/g')

	echo "$result"
}

is_valid_string(){
	local string="$1"
	local result=0

	if ! echo "$string" | egrep '[^-_.[:alnum:]]'; then

		result=1
	fi

	echo "$result"
}

# $1 : device uuid
storage_generate_name_by_uuid(){
	local uuid="$1"
	local result=""

	result=$(echo "${uuid}" | grep -o "[^ ]\+\( \+[^ ]\+\)*")
	result=$(echo "${result}" | sed -r 's/[\t ]\+/ /g')
	result=$(echo "${result}" | sed -r 's/ /_/g')
	result=$(echo "${result}" | sed -r 's/-/_/g')
	result=$(echo "${result}" | head -c 16)

	echo "$result"
}

storage_get_block_device_param_value(){
	local param1="$1"
	local param2="$2"
	local value=""

	value=$(block info | grep "${param1}" | grep "${param2}")
	value=${value#*${param2}=\"}
	value=${value%%\"*}
	value=$(trim "${value}")

	echo "${value}"
}

storage_get_usb_device_param_value(){
	local dev="$1"
	local param="$2"
	local value=""

	value=$(basename "$(cat /sys/class/block/$dev/device/${param})")
	value=$(trim "${value}")

	[ "$(is_valid_string ${value})" != "1" ] && value=""

	echo "${value}"
}

storage_get_usb_device_partition_size(){
	local dev="${1#_}"
	local size=0

	size="$(cat /sys/class/block/$dev/size)"

	echo "${size}"
}

storage_list_partition(){
	local label size uuid target type

	config_get label $1 label unknown
	config_get uuid $1 uuid 0
	config_get target $1 target "/mnt/$1"
	config_get size $1 size 0
	config_get type $1 type unknown

	echo "	$1"
	echo "		label: $label"
	echo "		size: $size"
	echo "		uuid: $uuid"
	echo "		type: $type"
	echo "		target: $target"
	echo
}

storage_list_device(){
	local model vendor size

	config_get vendor $1 vendor unknown
	config_get model $1 model unknown
	config_get size $1 size 0

	echo "DEVICE：$1"
	echo "  vendor: $vendor"
	echo "  model: $model"
	echo "  size: $size"
	echo "  partitions:"

	config_list_foreach $1 partition storage_list_partition
}

storage_dump(){
	config_foreach storage_list_device device
}

# $1 : partition device
storage_get_used_size(){
	local partition="${1#_}"
	local used_size=0

	used_size=$(df "/dev/$partition" | grep "$partition" | awk '{print $3}')

	echo "$used_size"
}

# $1 : partition device
storage_get_available_size(){
	local partition="${1#_}"
	local available_size=0

	available_size=$(df "/dev/$partition" | grep "$partition" | awk '{print $4}')

	echo "$available_size"
}

# $1 : partition device
storage_get_label_by_device(){
	local partition="/dev/${1#_}"
	local label=""

	label="$(storage_get_block_device_param_value $partition LABEL)"
	[ "$(is_valid_string ${label})" != "1" ] && label=""

	echo "$label"
}

# $1 : partition device
storage_get_uuid_by_device(){
	local partition="/dev/${1#_}"
	local uuid=""

	uuid="$(storage_get_block_device_param_value $partition UUID)"
	[ "$(is_valid_string ${uuid})" != "1" ] && uuid=""

	echo "$uuid"
}

# $1 : partition device
storage_get_fstype_by_device(){
	local partition="/dev/${1#_}"
	local type=""

	type="$(storage_get_block_device_param_value $partition TYPE)"
	[ "$(is_valid_string ${type})" != "1" ] && type=""

	if [ "$type" = "vfat" ]; then
		type="$(storage_get_block_device_param_value $partition VERSION)"
		[ -z "$type" ] && type="fat32"
		[ "$(is_valid_string ${type})" != "1" ] && type="fat32"
	fi

	echo "$type"
}

# $1 : partition device
storage_get_mount_path_by_device(){
	local partition="/dev/${1#_}"
	local target=""

	target="$(storage_get_block_device_param_value $partition MOUNT)"

	echo "$target"
}

# $1 : device uuid
storage_get_mount_path_by_uuid(){
	local uuid="$1"
	local target=""

	target="$(storage_get_block_device_param_value $uuid MOUNT)"

	echo "$target"
}

# $1 : partition device
storage_get_uuid_by_config(){
	local partition="$1"
	local uuid=""

	# for ext4, partition = '_' + device, check partition exist first
	if uci -c ${STORAGE_CONFIG_PATH} -q get "storage.$partition" | grep -sqx partition; then
		uuid=$(uci -c ${STORAGE_CONFIG_PATH} -q get "storage.$partition.uuid")
	elif uci -c ${STORAGE_CONFIG_PATH} -q get "storage._$partition" | grep -sqx partition; then
		uuid=$(uci -c ${STORAGE_CONFIG_PATH} -q get "storage._$partition.uuid")
	fi

	echo "$uuid"
}

# $1 : partition device
storage_get_main_device(){
	local partition="$1"
	local main_dev=""

	main_dev=$(echo "$partition" | sed 's/[0-9]*$//')

	echo "$main_dev"
}

# $1 : device
storage_add_device(){
	local device="$1"
	local model vendor

	[ -f "${STORAGE_CONFIG_PATH}/storage" ] || {
		[ -d "${STORAGE_CONFIG_PATH}" ] || mkdir -p "${STORAGE_CONFIG_PATH}"
		touch "${STORAGE_CONFIG_PATH}/storage"
	}

	vendor="$(storage_get_usb_device_param_value $device vendor)"
	model="$(storage_get_usb_device_param_value $device model)"

	log "storage_add_device: device = $device, vendor = $vendor, model = $model"

	uci -c "${STORAGE_CONFIG_PATH}" -q batch <<-EOF >/dev/null
		set storage.$device='device'
		set storage.$device.vendor="$vendor"
		set storage.$device.model="$model"
		commit storage
EOF

}

# $1 : device
storage_del_device(){
	local device="$1"

	log "storage_del_device: device = $device"

	[ -n "$(uci -c ${STORAGE_CONFIG_PATH} -q get storage.$device)" ] || return

	uci -c "${STORAGE_CONFIG_PATH}" -q batch <<-EOF >/dev/null
		del storage.$device
		commit storage
EOF

}

# $1 : partition device
storage_add_device_partition(){
	local partition="$1"
	local main_dev size label uuid target type target

	[ -f "${STORAGE_CONFIG_PATH}/storage" ] || {
		[ -d "${STORAGE_CONFIG_PATH}" ] || mkdir -p "${STORAGE_CONFIG_PATH}"
		touch "${STORAGE_CONFIG_PATH}/storage"
	}

	label="$(storage_get_label_by_device $partition)"
	uuid="$(storage_get_uuid_by_device $partition)"
	type="$(storage_get_fstype_by_device $partition)"
	target="$(storage_get_mount_path_by_device $partition)"
	size="$(storage_get_usb_device_partition_size $partition)"
	main_dev=$(storage_get_main_device "$partition")
	[ "$main_dev" = "$partition" ] && partition="_${partition}"

	log "storage_add_device_partition: partition = $partition, label = $label, uuid = $uuid, target = $target, size = $size"

	uci -c "${STORAGE_CONFIG_PATH}" -q batch <<-EOF >/dev/null
		add_list storage.${main_dev}.partition='$partition'
		set storage.$partition='partition'
		set storage.$partition.label="$label"
		set storage.$partition.uuid="$uuid"
		set storage.$partition.type="$type"
		set storage.$partition.target="$target"
		set storage.$partition.size="$size"
		commit storage
EOF
}

# $1 : partition device
storage_del_device_partition(){
	local partition="$1"
	local label main_dev

	log "storage_del_device_partition: partition = $partition"

	main_dev=$(storage_get_main_device "$partition")
	[ "$main_dev" = "$partition" ] && partition="_${partition}"
	[ -n "$(uci -c ${STORAGE_CONFIG_PATH} -q get storage.$partition)" ] || return

	uci -c "${STORAGE_CONFIG_PATH}" -q batch <<-EOF >/dev/null
		del_list storage.${main_dev}.partition='$partition'
		del storage.$partition
		commit storage
EOF
}

storage_set_device_partition(){
	local partition="$1"
	local option="$2"
	local value="$3"
	local main_dev

	log "storage_set_device_partition: partition = $partition, option = $option, value = $value"

	main_dev=$(storage_get_main_device "$partition")
	[ "$main_dev" = "$partition" ] && partition="_${partition}"
	[ -n "$(uci -c ${STORAGE_CONFIG_PATH} -q get storage.$partition)" ] || return

	uci -c "${STORAGE_CONFIG_PATH}" -q batch <<-EOF >/dev/null
		set storage.$partition.$option="$value"
		commit storage
EOF

}

storage_bind_partition_mount_path(){
	local name="$1"
	local uuid="$2"
	local target="$3"

	uci -q batch <<-EOF >/dev/null
		set fstab.$name='mount'
		set fstab.$name.target="$target"
		set fstab.$name.uuid="$uuid"
		set fstab.$name.enable='1'
		commit fstab
EOF
}

storage_unbind_partition_mount_path(){
	local name="$1"

	[ -n "$(uci -q get fstab.$name)" ] || return

	uci -q batch <<-EOF >/dev/null
		del fstab.$name
		commit fstab
EOF
}

storage_hotplug(){
	local action=$1
	local devname=$2

	env -i ACTION="$action" DEVNAME="$devname" /sbin/hotplug-call block

	return $?
}

storage_remove_device() {
	local devname=$1
	local action="remove"
	local partitions

	partitions=$(uci -c ${STORAGE_CONFIG_PATH} -q get storage.$devname.partition)
	[ -n "$partitions" ] || return

	for partition in $partitions
	do
		[ "_$devname" = "$partition" ] && partition="${devname}"
		storage_hotplug $action $partition
	done
	storage_hotplug $action $devname
}
