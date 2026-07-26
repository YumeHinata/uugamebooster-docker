#
# Copyright (c) 2017-2023 Qualcomm Technologies, Inc.
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#
#!/bin/sh
#
# Copyright (c) 2014, 2016, The Linux Foundation. All rights reserved.
#
. /usr/share/libubox/jshn.sh
append DRIVERS "qcawificfg80211"
log_file="/tmp/qcawificfg80211_commands.txt"
print_rl_set=0

# cnss-daemon and cnsscli related global variables
g_platform_features="enable_cold_boot_support enable_hds_support enable_regdb_support enable_qdss_tracing"
g_pci_targets="qcn9000 qcn6122 qcn9224 qcn9160"
g_pci_slots="pci0 pci1 pci2 pci3"
g_qdss_tracing=0
g_cold_boot_support=0
fw_ini_file=""
board_name=""
board_name_prefix=""
daemon_features_default_string=""
gdevice=""
mbss_tx_check_var=0
mld_netdev=0

get_ap_sdxpinn_ko_path() {
	release=$(uname -r | awk -F '.' '{print $1,$2}' | tr ' ' '.')
	if [ -d /lib/modules/$release-debug ]; then
		echo "/lib/modules/$release-debug/extra"
	elif [ -d /lib/modules/$release-perf ]; then
		echo "/lib/modules/$release-perf/extra"
	else
		echo ""
	fi
}

configure_service_param() {
	enable_service=$2
	json_load "$1"
	json_get_var app_name app_name
	json_get_var svc_id svc_id
	json_get_var disable disable
	json_get_var min_thruput_rate min_thruput_rate
	json_get_var max_thruput_rate max_thruput_rate
	json_get_var burst_size burst_size
	json_get_var service_interval service_interval
	json_get_var delay_bound delay_bound
	json_get_var msdu_ttl msdu_ttl
	json_get_var priority priority
	json_get_var tid tid
	json_get_var msdu_rate_loss msdu_rate_loss
	json_get_var ul_burst_size ul_burst_size
	json_get_var ul_service_interval ul_service_interval
	json_get_var ul_disabled_modes ul_disabled_modes
	json_get_var dl_disabled_modes dl_disabled_modes

	[ -z "$min_thruput_rate" ] && min_thruput_rate='X'
	[ -z "$max_thruput_rate" ] && max_thruput_rate='X'
	[ -z "$burst_size" ] && burst_size='X'
	[ -z "$service_interval" ] && service_interval='X'
	[ -z "$delay_bound" ] && delay_bound='X'
	[ -z "$msdu_ttl" ] && msdu_ttl='X'
	[ -z "$priority" ] && priority='X'
	[ -z "$tid" ] && tid='X'
	[ -z "$msdu_rate_loss" ] && msdu_rate_loss='X'
	[ -z "$disable" ] && disable='0'
	[ -z "$ul_burst_size" ] && ul_burst_size='X'
	[ -z "$ul_service_interval" ] && ul_service_interval='X'
	[ -z "$ul_disabled_modes" ] && ul_disabled_modes='X'
	[ -z "$dl_disabled_modes" ] && dl_disabled_modes='X'
	[ -z "$ul_min_tput" ] && ul_min_tput='X'
	[ -z "$ul_max_latency" ] && ul_max_latency='X'

	if [ $enable_service -eq 1 ] && [ "$disable" -eq 0 ]; then
		wlanconfig wifi0 service_class create "$svc_id" "$app_name" "$min_thruput_rate" "$max_thruput_rate" "$burst_size" "$service_interval" "$delay_bound" "$msdu_ttl" "$priority" "$tid" "$msdu_rate_loss" "$ul_burst_size" "$ul_service_interval" "$ul_disabled_modes" "$dl_disabled_modes" "$ul_min_tput" "$ul_max_latency"
	elif [ $enable_service -eq 0 ]; then
		wlanconfig wifi0 service_class disable "$svc_id"
	fi
}

set_umac_reset_affinity() {
	num_irq=`cat /proc/interrupts | grep umac_hw_reset_irq | cut -d ':' -f 1 | tr -d ' ' | wc -l`
	num_cpu=`cat /proc/cpuinfo | grep processor | wc -l`
	cpu_index=1;

	echo "Number of Umac reset irqs detected : $num_irq and number of cpus detected $num_cpu" > /dev/console
	list=`cat /proc/interrupts | grep umac_hw_reset_irq | cut -d ':' -f 1 | tr -d ' '`
	for irq in $list
	do
		echo "Assigning Umac reset $irq to cpu# $cpu_index" > /dev/console
		echo $cpu_index > /proc/irq/$irq/smp_affinity
		cpu_index=$((cpu_index+1))
		if [ $cpu_index -gt $num_cpu ]
		then
			cpu_index=1
		fi

	done
}

set_umac_reset_affinity() {
	num_irq=`cat /proc/interrupts | grep umac_hw_reset_irq | cut -d ':' -f 1 | tr -d ' ' | wc -l`
	num_cpu=`cat /proc/cpuinfo | grep processor | wc -l`
	cpu_index=1;

	echo "Number of Umac reset irqs detected : $num_irq and number of cpus detected $num_cpu" > /dev/console
	list=`cat /proc/interrupts | grep umac_hw_reset_irq | cut -d ':' -f 1 | tr -d ' '`
	for irq in $list
	do
		echo "Assigning Umac reset $irq to cpu# $cpu_index" > /dev/console
		echo $cpu_index > /proc/irq/$irq/smp_affinity
		cpu_index=$((cpu_index+1))
		if [ $cpu_index -gt $num_cpu ]
		then
			cpu_index=1
		fi

	done
}

configure_service_class() {
	json_init
	json_set_namespace default_ns
	json_load_file /sawf/def_service_classes.json
	json_select service_class
	json_get_keys svc_class_indexes
	svc_class_index=0
	enable_svc=$1

	svc_class_index_count=$(echo "$svc_class_indexes" | wc -w)

	echo "Default Service Class Count: $svc_class_index_count" > /dev/console

	while [ $svc_class_index -lt $svc_class_index_count ]
	do
		svc_class_json=$(jsonfilter -i /sawf/def_service_classes.json -e "@.service_class[$svc_class_index]")
		configure_service_param "$svc_class_json" "$enable_svc"

		svc_class_index=$(expr $svc_class_index + 1)
	done

	json_set_namespace default_ns
	json_load_file /sawf/service_classes.json
	json_select service_class
	json_get_keys svc_class_indexes
	svc_class_index=0

	svc_class_index_count=$(echo "$svc_class_indexes" | wc -w)

	echo "Custom Service Class Count: $svc_class_index_count" > /dev/console
	while [ $svc_class_index -lt $svc_class_index_count ]
	do
		svc_class_json=$(jsonfilter -i /sawf/service_classes.json -e "@.service_class[$svc_class_index]")
		configure_service_param "$svc_class_json" "$enable_svc"
		svc_class_index=$(expr $svc_class_index + 1)
	done
}

configure_sla_param() {
	json_load "$1"
	json_get_var svc_id svc_id
	json_get_var disable disable
	json_get_var min_thruput_rate min_thruput_rate
	json_get_var max_thruput_rate max_thruput_rate
	json_get_var burst_size burst_size
	json_get_var service_interval service_interval
	json_get_var delay_bound delay_bound
	json_get_var msdu_ttl msdu_ttl
	json_get_var msdu_rate_loss msdu_rate_loss

	[ -z "$min_thruput_rate" ] && min_thruput_rate='X'
	[ -z "$max_thruput_rate" ] && max_thruput_rate='X'
	[ -z "$burst_size" ] && burst_size='X'
	[ -z "$service_interval" ] && service_interval='X'
	[ -z "$delay_bound" ] && delay_bound='X'
	[ -z "$msdu_ttl" ] && msdu_ttl='X'
	[ -z "$msdu_rate_loss" ] && msdu_rate_loss='X'
	[ -z "$disable" ] && disable='0'

	if [ "$disable" -eq 0 ]; then
		wlanconfig wifi0 sawf_sla "$svc_id" "$min_thruput_rate" "$max_thruput_rate" "$burst_size" "$service_interval" "$delay_bound" "$msdu_ttl" "$msdu_rate_loss"
		echo "$svc_id" "$min_thruput_rate" "$max_thruput_rate" "$burst_size" "$service_interval" "$delay_bound" "$msdu_ttl" "$msdu_rate_loss"
	fi
}

configure_sawf_sla() {
	json_init
	json_set_namespace sla_ns
	json_load_file /sawf/telemetry/sla.json
	json_select sla
	json_get_keys sla_indexes
	sla_index=0

	sla_index_count=$(echo "$sla_indexes" | wc -w)

	echo "SLA Count: $sla_index_count" > /dev/console

	while [ $sla_index -lt $sla_index_count ]
	do
		sla_json=$(jsonfilter -i /sawf/telemetry/sla.json -e "@.sla[$sla_index]")
		configure_sla_param "$sla_json"

		sla_index=$(expr $sla_index + 1)
	done
}

configure_sla_detect() {
	json_init
	json_load_file /sawf/telemetry/sla_detect.json
	json_select x_packet
		json_get_var delay_x_packet delay
		json_get_var msdu_loss_x_packet msdu_loss
		json_get_var ttl_drop_x_packet ttl_drop
	json_select ..
	json_select 1_second
		json_get_var min_throutput min_throutput
		json_get_var max_throughput max_throughput
	json_select ..
	json_select mov_average
		json_get_var delay_mov_avg delay
	json_select ..
	json_select x_second
		json_get_var service_interval service_interval
		json_get_var burst_size burst_size
		json_get_var msdu_loss_x_sec msdu_loss
		json_get_var ttl_drop_x_sec ttl_drop
	json_select ..

	wlanconfig wifi0 sawf_sla_detect num_packet 0 0 0 0 $delay_x_packet $ttl_drop_x_packet $msdu_loss_x_packet
	wlanconfig wifi0 sawf_sla_detect per_second $min_throutput $max_throughput 0 0 0 0 0
	wlanconfig wifi0 sawf_sla_detect moving_avg 0 0 0 0 $delay_mov_avg 0 0
	wlanconfig wifi0 sawf_sla_detect num_second 0 0 $burst_size $service_interval 0 $ttl_drop_x_sec $msdu_loss_x_sec
}

configure_sawf_telemetry() {
	json_init
	json_load_file /sawf/telemetry/config.json

# Parsing the moving average params
	json_get_var mavg_num_packet mavg_num_packet
	json_get_var mavg_num_window mavg_num_window

# Parsing the sla params
	json_get_var sla_num_packet sla_num_packet
	json_get_var sla_time_secs sla_time_secs

	wlanconfig wifi0 sawf_telemetry "$mavg_num_packet" "$mavg_num_window" "$sla_num_packet" "$sla_time_secs"
}

sysctl_cmd() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo "sysctl -w $1=$2" >> $log_file
	sysctl -w $1=$2 >/dev/null 2>/dev/null
}

echo_cmd() {
	if [[ $# == 3 ]] ; then
		[ -n "${CFG80211_UPDATE_FILE}" ] && echo "echo $1 $2 > $3" >> $log_file
		echo $1 $2 > $3
	else
		[ -n "${CFG80211_UPDATE_FILE}" ] && echo "echo $1 > $2" >> $log_file
		echo $1 > $2
	fi
}

insmod_cmd() {
	local module_name="${1}"
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	# SDX boards need absolute path of ko for insmod
	# SDX65 will have ko's in /lib/modules/<version>/extra/<ko>
	# SDX75 will have ko's in /lib/modules/<version>-<variant>/extra/<ko>
	case "$board_name" in
	ap-sdxlemur*)
		module_name="/lib/modules/$(uname -r)/extra/${1}.ko"
	;;
	ap-sdxpinn*)
		module_name="$(get_ap_sdxpinn_ko_path)/${1}.ko"
	;;
	*)
	;;
	esac

	if [[ $# == 2 ]] ; then
		[ -n "${CFG80211_UPDATE_FILE}" ] && echo "insmod $1 $2" >> $log_file
		insmod ${module_name} $2
	else
		[ -n "${CFG80211_UPDATE_FILE}" ] && echo "insmod $1" >> $log_file
		insmod ${module_name}
	fi
}

rmmod_cmd() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo "rmmod $1" >> $log_file
	rmmod $1
}

do_acs_wait() {
	count=5
	while [ $count -gt 0 ]
	do
		acs_state=$("$device_if" "$ifname" get_acs_state 2>/dev/null | awk -F ':' '{print $2}')
		if [ $acs_state -eq 0 ] || [ -z $acs_state ]; then
			break;
		fi
		echo "$ifname acs_state:$acs_state wating" >&2
		sleep 1
		let "count--"
	done
}

#for miwifi
mesh_set_low_power()
{
	local max_power=0
	local need_low_power=0
	local sub_power=0
	local mesh_power=0

	max_power=$(uci -q get misc.wireless.if_5g_maxpower)
	if [ -z "$max_power" ]; then
		max_power=26
	fi
	max_power="${max_power%%.*}"

	need_low_power=$(uci -q get misc.mesh.need_lower_power)
	if [ -z "$need_low_power" ]; then
		need_low_power=0
	fi

	if [ "$need_low_power" == "1" ]; then
		sub_power=$(uci -q get misc.mesh.sub_power)
		if [ -z "$sub_power" ]; then
			sub_power=6
		fi
		mesh_power=$(expr $max_power - $sub_power)

		iwconfig $1 txpower ${mesh_power}
	fi
}

get_config_file_path() {
	local file_type board_name
	local ini_path cfg_def_path

	if [[ $# -ne 1 ]]; then
		return
	fi

	file_type="$1"

	case "$file_type" in
	ini | cfg_default) ;;
	*) return ;;
	esac

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	# For QCA boards, ini files are in /ini and /ini/internal
	#                 cfg/default is in /
	# for SDX65/75 boards, ini files are in /etc/misc/ipq/ini and /etc/misc/ipq/ini/internal
	#		       cfg/default is in /data/vendor/ipq
	case "$board_name" in
	ap-sdxlemur* | ap-sdxpinn*)
		ini_path="/etc/misc/ipq/ini"
		cfg_def_path="/data/vendor/ipq/cfg/default"
	;;
	*)
		ini_path="/ini"
		cfg_def_path="/cfg/default"
	;;
	esac

	if [ "$file_type" == "ini" ]; then
		echo "$ini_path"
	else
		echo "$cfg_def_path"
	fi
}

update_global_daemon_coldboot_qdss_support_variables() {
	local board_prefix=""
	local version=0
	local custom_ini_file=""
	local default_ini_file=""
	local qdss_tracing=""

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	[ -z "$board_name"  ] && {
		echo "******Unable to find board name******" > /dev/console
		return
	}

	if [ -e /sys/firmware/devicetree/base/MP_512 ]
	then
		custom_ini_file=/ini/firmware_rdp_feature_512P.ini
		default_ini_file=/lib/firmware/firmware_rdp_feature_512P.ini
	elif [ -e /sys/firmware/devicetree/base/MP_256 ]
	then
		# 256MB profile will use the same file as 512MB profile,
		# but coldboot calibration support will be skipped.
		custom_ini_file=/ini/firmware_rdp_feature_512P.ini
		default_ini_file=/lib/firmware/firmware_rdp_feature_512P.ini
	else
		custom_ini_file=/etc/misc/ipq/ini/firmware_rdp_feature.ini
		case "$board_name" in
		ap-sdxlemur*)
			default_ini_file=/firmware/image/qcn9000/firmware_rdp_feature.ini
			;;
		ap-sdxpinn*)
			default_ini_file=/firmware/image/qcn9224/firmware_rdp_feature.ini
			;;
		*)
			default_ini_file=/lib/firmware/firmware_rdp_feature.ini
			;;
		esac
	fi

	if [ -f $custom_ini_file ]
	then
		fw_ini_file=$custom_ini_file
	elif [ -f $default_ini_file ]
	then
		fw_ini_file=$default_ini_file
	else
		echo "******FW ini file not found******" > /dev/console
		return
	fi


	#INI file has strings with the below format
	#  <board_name>_<feature>=0/1   or
	#  <board_name>_<PCI_device_id>_<PCI_Slot_number>_<feature>=0/1
	# Append a "_" to the board_name here so that grep would be able to
	# differentiate boards with similar names like ap-mp03.1 and
	# ap-mp03.1-c2
	board_name_prefix=${board_name}_

	board_prefix=$(echo $board_name | sed 's/[0-9].*//g')

	case "$board_name" in
	ap-hk*)
		[ -f /sys/firmware/devicetree/base/soc_version_major ] && {
			version="$(cat /sys/module/ipq_cnss2/parameters/soc_version_major)"
		}

		daemon_features_default_string=$board_prefix"_v"$version"_default"
		;;
	*)
		daemon_features_default_string=$board_prefix"_default"
		;;
	esac

	#Grep the board_name_prefix in the fw_ini_file, if its not found, use the
	#default string
	boardname_grep_result=`grep -ci $board_name_prefix $fw_ini_file`
	default_grep_result=`grep -ci $daemon_features_default_string $fw_ini_file`

	if [ $boardname_grep_result != 0 ]
	then
		g_cold_boot_support=`grep -i $board_name_prefix $fw_ini_file | grep "enable_cold_boot_support" | awk -F '=' '{print $2}' | grep -c 1`
		qdss_tracing=`grep -i $board_name_prefix $fw_ini_file | grep "enable_qdss_tracing" | awk -F'=' '($2 != 0) {print $2}' | head -n 1`
		[ -n "${qdss_tracing}" ] && g_qdss_tracing=1 || g_qdss_tracing=0
	elif [ $default_grep_result != 0 ]
	then
		g_cold_boot_support=`grep -i $daemon_features_default_string $fw_ini_file | grep "enable_cold_boot_support" | awk -F'=' '{print $2}' | cut -c 1`
		qdss_tracing=`grep -i $daemon_features_default_string $fw_ini_file | grep "enable_qdss_tracing" | awk -F'=' '($2 != 0) {print $2}' | head -n 1`
		[ -n "${qdss_tracing}" ] && g_qdss_tracing=1 || g_qdss_tracing=0
	else
		echo "***** No coldboot or daemon support for $board_name******" > /dev/console
	fi

	# Force disable Coldboot Calibration for 256MB profile.
	# Daemon support and QDSS are only supported.
	[ -e /sys/firmware/devicetree/base/MP_256 ] && {
		g_cold_boot_support=0
	}
}

iw() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo iw "$@" >> $log_file
	/usr/sbin/iw "$@"
}

wlanconfig() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo wlanconfig "$@" >> $log_file
	/usr/sbin/wlanconfig "$@"
}

iwconfig() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo iwconfig "$@" >> $log_file
	/usr/sbin/iwconfig "$@"
}

iwpriv() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo iwpriv "$@" >> $log_file
	/usr/sbin/iwpriv "$@"
}

cfg80211tool() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo cfg80211tool "$@" >> $log_file
	/usr/sbin/cfg80211tool "$@"
}

ifconfig() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo ifconfig "$@" >> $log_file
	/sbin/ifconfig "$@"
}

wpa_cli() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo wpa_cli "$@" >> $log_file
	/usr/sbin/wpa_cli "$@"
}

hostapd() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo hostapd "$@" >> $log_file
	/usr/sbin/hostapd "$@"
}

hostapd_cli() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo hostapd_cli "$@" >> $log_file
	/usr/sbin/hostapd_cli "$@"
}

retrieve_current_hw_mode() {
    local primary_if=$1
    if [[ "$primary_if" != "wifi0" && "$primary_if" != "wifi2" ]]; then
        primary_if="wifi0"
    fi
    local device=$primary_if
    config_get device_if "$device" device_if "cfg80211tool"
    current_hwmode=`$device_if $device get_hw_mode | awk -F'hw_mode:' '{print $2}'`
    echo "$current_hwmode"
}

switch_hw_mode() {
    local hwmode=$1
    local primary_if=$2
    if [[ "$primary_if" != "wifi0" && "$primary_if" != "wifi2" ]]; then
        primary_if="wifi0"
    fi
    local device=$primary_if
    config_get device_if "$device" device_if "cfg80211tool"
    `$device_if $device hw_mode $hwmode`
}

start_recovery_daemon() {
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo starting recovery daemon > /dev/console
	killall acfg_tool
	/usr/sbin/acfg_tool -e -s > /dev/console &
}

find_qcawifi_phy() {
	local device="$1"

	local macaddr="$(config_get "$device" macaddr | tr 'A-Z' 'a-z')"
	config_get phy "$device" phy
	[ -z "$phy" -a -n "$macaddr" ] && {
		cd /sys/class/net
		for phy in $(ls -d wifi* 2>&-); do
			[ "$macaddr" = "$(cat /sys/class/net/${phy}/address)" ] || continue
			config_set "$device" phy "$phy"
			break
		done
		config_get phy "$device" phy
	}
	[ -n "$phy" -a -d "/sys/class/net/$phy" ] || {
		echo "phy for wifi device $1 not found"
		return 1
	}
	[ -z "$macaddr" ] && {
		config_set "$device" macaddr "$(cat /sys/class/net/${phy}/address)"
	}
	return 0
}

enable_qdss_tracing() {
	local qdss_tracing=0

	[ $g_qdss_tracing = 0 ] && {
		return
	}

	#For Integrated Radio
	qdss_tracing=`grep -i $board_name_prefix $fw_ini_file | grep "enable_qdss_tracing" | grep -v pci | awk -F'=' '($2 != 0) {print $2}' | head -n 1`

	[ -z "${qdss_tracing}" ] && {
		qdss_tracing=`grep -i $daemon_features_default_string $fw_ini_file | grep "enable_qdss_tracing" | awk -F'=' '($2 != 0) {print $2}' | head -n 1`
	}
	[ -z "${qdss_tracing}" ] && {
		return
	}

	# QDSS in IPQ5332 will have already been started soon after mode message is sent.
	# In 11ax family, integrated radios will have QDSS started after VAP-up and PCI radios will have QDSS
	# started soon after mode message is sent to FW. In 11be family, all radios will have QDSS started
	# soon after mode message is sent to FW, so going forward, integrated radios in 11be family
	# would need to be added in the case below to return.
	case "$board_name" in
	ap-mi*)
		return
		;;
	esac

	mode=`cat /sys/module/ipq_cnss2/parameters/driver_mode`
	[ $(( $qdss_tracing & $((1 << $mode)) )) != 0 ] && {
		case "$board_name" in
		ap-al*)
			# WAR to get QDSS started in IPQ9574.
			# Apply the settings after QDSS start.
			# Make sure to disable Coresight STM first, and then enable it after applying the settings.
			# This needs to be done at every wifi firmware reload.
			# Funnel configs will be done at firmware.
			cnsscli -i integrated --qdss_start > /dev/null
			echo 0 > /sys/bus/coresight/devices/coresight-stm/enable
			echo "q6mem" > /sys/bus/coresight/devices/coresight-tmc-etr/out_mode
			echo 1 > /sys/bus/coresight/devices/coresight-tmc-etr/curr_sink
			echo 1 > /sys/bus/coresight/devices/coresight-stm/enable
			echo "***** QDSS Tracing Configuration completed *******" > /dev/console
			;;
		ap-mi*)
			echo "***** QDSS Trace start for IPQ5332 *****" > /dev/console
			cnsscli -i integrated --qdss_start > /dev/null
			;;
		*)
			[ ! -f /tmp/qdss_sink_config_done ] && {
				echo_cmd "q6mem" /sys/bus/coresight/devices/coresight-tmc-etr/out_mode
				echo_cmd 1 /sys/bus/coresight/devices/coresight-tmc-etr/curr_sink
				echo_cmd 5 /sys/bus/coresight/devices/coresight-funnel-mm/funnel_ctrl
				case "$board_name" in
				ap-mp*)
					echo_cmd 7 /sys/bus/coresight/devices/coresight-funnel-in0/funnel_ctrl
					;;
				*)
					echo_cmd 6 /sys/bus/coresight/devices/coresight-funnel-in0/funnel_ctrl
					;;
				esac
				echo_cmd 1 /sys/bus/coresight/devices/coresight-stm/enable
				echo "***** QDSS Tracing Configuration completed *******" > /dev/console
				touch /tmp/qdss_sink_config_done
			}
			cnsscli -i integrated --qdss_start > /dev/null
			;;
		esac
		echo "****** Starting QDSS for Integrated ********" > /dev/console
	}
}

update_platform_features_support_to_plat_priv() {
	local value=0

	for feature in $g_platform_features
	do
		# 256MB profile does not support Coldboot Calibration
		[ "$feature" = "enable_cold_boot_support" ] && {
			[ -e /sys/firmware/devicetree/base/MP_256 ] && {
				continue
			}
		}

		# Update for PCIe Radios
		for target in $g_pci_targets
		do
			for slot in $g_pci_slots
			do
				value=`grep -i $board_name_prefix $fw_ini_file | grep $feature | grep -i $target | grep -i $slot | awk -F'=' '{print $2}'`
				[ -n "$value" ] && {
					cnsscli -i $target\_$slot --$feature $value > /dev/null
				}
			done
		done

		# enable_qdss_tracing will automatically start QDSS after QMI
		# mode message from CNSS2. This is supported for all radios in 11be family
		# and all PCI radios in 11ax family. So skip this for all 11ax family integrated radios.
		[ "$feature" = "enable_qdss_tracing" ] && {
			case "$board_name" in
			ap-mi*)
				echo "QDSS will be started soon after mode message is sent to FW." > /dev/console
				;;
			*)
				continue
				;;
			esac
		}

		# Update for Integrated Radio
		value=`grep -i $board_name_prefix $fw_ini_file | grep $feature | grep -v pci | awk -F'=' '{print $2}' | cut -c 1`
		[ -z $value ] && {
			value=`grep -i $daemon_features_default_string $fw_ini_file | grep $feature | awk -F'=' '{print $2}' | grep -c 1`
		}

		[ $value = 1 ] && {
			cnsscli -i integrated --$feature $value > /dev/null
		}
	done
}

do_cold_boot_calibration_qcawificfg80211() {
	#Update the daemon, coldboot and qdss support variables from FW INI
	update_global_daemon_coldboot_qdss_support_variables

	# Set cnss-daemon OOM score to -1000 to prevent it from getting killed
	cnssd_pid=$(pgrep cnssdaemon)
	[ ! -z "$cnssd_pid" ] && {
		echo_cmd -1000 "/proc/$cnssd_pid/oom_score_adj"
		echo "*****cnssdaemon pid=$cnssd_pid*********" > /dev/console
	}

        # Set hostapd OOM score to -1000 to prevent it from getting killed
        hostapd_pid=$(pgrep hostapd)
        [ ! -z "$hostapd_pid" ] && {
                echo_cmd -1000 "/proc/$hostapd_pid/oom_score_adj"
                echo "*****hostapd pid=$hostapd_pid*********" > /dev/console
        }

        # Set supplicant OOM score to -1000 to prevent it from getting killed
        supplicant_pid=$(pgrep supplicant)
        [ ! -z "$supplicant_pid" ] && {
                echo_cmd -1000 "/proc/$supplicant_pid/oom_score_adj"
                echo "*****supplicant pid=$supplicant_pid*********" > /dev/console
        }

	update_platform_features_support_to_plat_priv
}

is_son_enabled()
{
	local son_is_enabled=""
	local is_son_hyd_enabled=""
	local is_son_lbd_enabled=""

	config_load lbd
	config_get is_son_lbd_enabled config "Enable" 0

	config_load hyd
	config_get is_son_hyd_enabled config "Enable" 0

	config_load repacd
	config_get is_repacd_enabled repacd "Enable" 0

	if [ $is_son_hyd_enabled = "1" ] ||
		[ $is_son_lbd_enabled = "1" ] || [ $is_repacd_enabled = "1" ]
	then
		son_is_enabled=1
		echo $son_is_enabled
	else
		son_is_enabled=0
		echo $son_is_enabled
	fi
}

get_vif() {
	[ -e /lib/functions.sh ] && . /lib/functions.sh
	wifi_dev=$1
	local vifs1=

	DEVICES=
		config_cb() {
			local type="$1"
			local section="$2"

			config_get device1 "$CONFIG_SECTION" device
			# Make sure each vif for $wifi_dev is processed only once
			if [ "$device1" == "$wifi_dev" ] && [ "$config_bkp" != "$CONFIG_SECTION" ]; then
				config_get TYPE "$CONFIG_SECTION" TYPE
				case "$TYPE" in
					wifi-iface)
						append vifs1 "$CONFIG_SECTION"
						vif=$vifs1
					;;
				esac
			# Hold the config item that has been processed
			config_bkp=$CONFIG_SECTION
			fi
		}
	config_load wireless
}

monitor_scan_qcawificfg80211() {
	local device="$1"
	local wds
	local adhoc sta ap monitor lite_monitor ap_monitor ap_smart_monitor mesh ap_lp_iot disabled
	local owrt_versn
	local ini_path
	local vap_mode=""

	get_vap_mode
	# wifi reload_legacy
	[ "$vap_mode" = "1" ] && [ -f /tmp/event_vap_nop ] && return

	[ "$vap_mode" = "1" ] && [ -f /tmp/this_is_event ] && [ ! -f /tmp/event_fast_boot_in_progress ] && return

	config_get vifs "$device" vifs
	for vif in $vifs; do {
		config_get ifname "$vif" ifname
		[ ${ifname//[0-9]} = "wl" ] && config_set "$vif" ifname ""
	}; done

	ini_path=$(get_config_file_path "ini")

	# Ap in dynamic mode means 3 radios will always be present
	# If in DBS mode then wifi2 should not be using cfg80211tool functions
	dynamic_hw_mode=`grep "dynamic_hw_mode" $ini_path/internal/global_i.ini | grep -m1 -v "^[#]" | awk -F'=' '{print $2}'`
	if [ "$dynamic_hw_mode" = "1" ]; then
		if [ $device = "wifi2" ]; then
			hw_mode_id=`retrieve_current_hw_mode`
			if [ $hw_mode_id -eq 1 ]; then
				return 0
			fi
		fi
	fi

	[ ${device%[0-9]} = "wifi" ] && config_set "$device" phy "$device"

	local ifidx=0
	local radioidx=${device#wifi}
	local son_enabled=""

	son_enabled=$( is_son_enabled )

	# From openwrt v19.07 onward needs differet handling while fetching vifs
	owrt_versn=`cat /etc/openwrt_release | grep 'RELEASE' | grep -Eo '[+-]?[0-9]+([.][0-9]+)?'`
	if (awk -v a="$owrt_versn" -v b="18.06" 'BEGIN{print(a>=b)}'); then
		get_vif $device
		config_set "$device" vifs "$vif"
		config_get vifs "$device" vifs
	else
		config_get vifs "$device" vifs
	fi

	for vif in $vifs; do
		config_get_bool disabled "$vif" disabled 0
		[ $disabled = 0 ] || continue

		config_get mode "$vif" mode
		[[ $mode != *"monitor"* ]] && ifidx=$(($ifidx + 1)) && continue

		local vifname
		local ifname
		local ifname_idx

		[ $ifidx -gt 0 ] && vifname="wl${radioidx}$ifidx" || vifname="wl${radioidx}"

		if [ $son_enabled = "1" ]
		then
			config_set "$vif" ifname $vifname
		else
			config_get ifname "$vif" ifname "$vifname"
			config_set "$vif" ifname $ifname
			#If vap interfaces are manually added to the existing
			#config file, the ifname of the last vap of a radio
			#is picked up by the subsequent radio's 1st vap.
			#Validate the ifname for a vif for such case.
			if [ $ifname != $vifname ] && [ "wl" == "${ifname:0:3}" ] ; then
				ifname_idx=${ifname:3:1}
				if [ $ifname_idx != $radioidx ] ; then
					config_set "$vif" ifname $vifname
				fi
			fi
		fi

		config_get mode "$vif" mode
		case "$mode" in
			monitor|lite_monitor|ap_monitor|ap_smart_monitor)
				append "$mode" "$vif"
			;;
			wds)
				config_get ssid "$vif" ssid
				[ -z "$ssid" ] && continue

				config_set "$vif" wds 1
				config_set "$vif" mode sta
				mode="sta"
				addr="$ssid"
				${addr:+append "$mode" "$vif"}
			;;
			*) echo "$device($vif): Invalid mode, ignored."; continue;;
		esac

		ifidx=$(($ifidx + 1))
	done

	case "${adhoc:+1}:${sta:+1}:${ap:+1}" in
		# valid mode combinations
		1::) wds="";;
		1::1);;
		:1:1)config_set "$device" nosbeacon 1;; # AP+STA, can not use beacon timers for STA
		:1:);;
		::1);;
		::);;
		*) echo "$device: Invalid mode combination in config"; return 1;;
	esac

	config_set "$device" vifs "${ap:+$ap }${ap_monitor:+$ap_monitor }${mesh:+$mesh }${ap_smart_monitor:+$ap_smart_monitor }${wrap:+$wrap }${sta:+$sta }${adhoc:+$adhoc }${wds:+$wds }${monitor:+$monitor}${lite_monitor:+$lite_monitor }${ap_lp_iot:+$ap_lp_iot}"
}

scan_qcawificfg80211() {
	local device="$1"
	local wds
	local adhoc sta ap monitor lite_monitor ap_monitor ap_smart_monitor mesh ap_lp_iot disabled
	local owrt_versn
	local ini_path
	local vap_mode=""
	local qwrap_enable=0

	get_vap_mode
	# wifi reload_legacy
	[ "$vap_mode" = "1" ] && [ -f /tmp/event_vap_nop ] && return

	[ "$vap_mode" = "1" ] && [ -f /tmp/this_is_event ] && [ ! -f /tmp/event_fast_boot_in_progress ] && return

	config_get vifs "$device" vifs
	for vif in $vifs; do {
		config_get ifname "$vif" ifname
		[ ${ifname//[0-9]} = "wl" ] && config_set "$vif" ifname ""
	}; done

	ini_path=$(get_config_file_path "ini")

	# Ap in dynamic mode means 3 radios will always be present
	# If in DBS mode then wifi2 should not be using cfg80211tool functions
	dynamic_hw_mode=`grep "dynamic_hw_mode" $ini_path/internal/global_i.ini | grep -m1 -v "^[#]" | awk -F'=' '{print $2}'`
	if [ "$dynamic_hw_mode" = "1" ]; then
		if [ $device = "wifi2" ]; then
			hw_mode_id=`retrieve_current_hw_mode`
			if [ $hw_mode_id -eq 1 ]; then
				return 0
			fi
		fi
	fi

	[ ${device%[0-9]} = "wifi" ] && config_set "$device" phy "$device"

	local ifidx=0
	local radioidx=${device#wifi}
	local son_enabled=""

	son_enabled=$( is_son_enabled )

	# From openwrt v19.07 onward needs differet handling while fetching vifs
	owrt_versn=`cat /etc/openwrt_release | grep 'RELEASE' | grep -Eo '[+-]?[0-9]+([.][0-9]+)?'`
	if (awk -v a="$owrt_versn" -v b="18.06" 'BEGIN{print(a>=b)}'); then
		get_vif $device
		config_set "$device" vifs "$vif"
		config_get vifs "$device" vifs
	else
		config_get vifs "$device" vifs
	fi

	for vif in $vifs; do
		config_get_bool disabled "$vif" disabled 0
		[ $disabled = 0 ] || continue

		local vifname
		local ifname
		local ifname_idx

		[ $ifidx -gt 0 ] && vifname="wl${radioidx}$ifidx" || vifname="wl${radioidx}"

		if [ $son_enabled = "1" ]
		then
			config_set "$vif" ifname $vifname
		else
			config_get ifname "$vif" ifname "$vifname"
			config_set "$vif" ifname $ifname
			#If vap interfaces are manually added to the existing
			#config file, the ifname of the last vap of a radio
			#is picked up by the subsequent radio's 1st vap.
			#Validate the ifname for a vif for such case.
			if [ $ifname != $vifname ] && [ "wl" == "${ifname:0:3}" ] ; then
				ifname_idx=${ifname:3:1}
				if [ $ifname_idx != $radioidx ] ; then
					config_set "$vif" ifname $vifname
				fi
			fi
		fi

		config_get mode "$vif" mode
		case "$mode" in
			adhoc|sta|ap|monitor|lite_monitor|wrap|ap_monitor|ap_smart_monitor|mesh|ap_lp_iot)
				append "$mode" "$vif"
			;;
			wds)
				config_get ssid "$vif" ssid
				[ -z "$ssid" ] && continue

				config_set "$vif" wds 1
				config_set "$vif" mode sta
				mode="sta"
				addr="$ssid"
				${addr:+append "$mode" "$vif"}
			;;
			*) echo "$device($vif): Invalid mode, ignored."; continue;;
		esac

		ifidx=$(($ifidx + 1))
	done

	case "${adhoc:+1}:${sta:+1}:${ap:+1}" in
		# valid mode combinations
		1::) wds="";;
		1::1);;
		:1:1)config_set "$device" nosbeacon 1;; # AP+STA, can not use beacon timers for STA
		:1:);;
		::1);;
		::);;
		*) echo "$device: Invalid mode combination in config"; return 1;;
	esac

	config_get qwrap_enable "$device" qwrap_enable 0
	[ $qwrap_enable -eq 0 ] && config_set "$device" vifs "${ap:+$ap }${ap_monitor:+$ap_monitor }${mesh:+$mesh }${ap_smart_monitor:+$ap_smart_monitor }${wrap:+$wrap }${sta:+$sta }${adhoc:+$adhoc }${wds:+$wds }${monitor:+$monitor}${lite_monitor:+$lite_monitor }${ap_lp_iot:+$ap_lp_iot}"
}

# The country ID is set at the radio level. When the driver attaches the radio,
# it sets the default country ID to 840 (US STA). This is because the desired
# VAP modes are not known at radio attach time, and STA functionality is the
# common unit of 802.11 operation.
# If the user desires any of the VAPs to be in AP mode, then we set a new
# default of 840 (US AP with TDWR) from this script. Even if any of the other
# VAPs are in non-AP modes like STA or Monitor, the stricter default of 840
# will apply.
# No action is required here if none of the VAPs are in AP mode.
set_default_country() {
	local device="$1"
	local mode

	config_get device_if "$device" device_if "cfg80211tool"
	find_qcawifi_phy "$device" || return 1
	config_get phy "$device" phy

	config_get vifs "$device" vifs
	for vif in $vifs; do
		config_get_bool disabled "$vif" disabled 0
		[ $disabled = 0 ] || continue

		config_get mode "$vif" mode
		case "$mode" in
			ap|wrap|ap_monitor|ap_smart_monitor|ap_lp_iot)
				# "$device_if" "$phy" setCountryID 840
				"$device_if" "$phy" setCountryID 156
				return 0;
			;;
		*) ;;
		esac
	done

	return 0
}

config_low_targ_clkspeed() {
        local board_name
        [ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
        }

        case "$board_name" in
                ap147 | ap151)
                   echo "true"
                ;;
                *) echo "false"
                ;;
        esac
}

function update_ini_file()
{
	local ini_path board_name

	ini_path=$(get_config_file_path "ini")

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	[ -f "$ini_path/global.ini" ] && {
		update_ini_cmd="grep -q $1 $ini_path/global.ini && sed -i '/$1=/c $1=$2' $ini_path/global.ini || echo $1=$2 >> $ini_path/global.ini"

		case "$board_name" in
		ap-sdxlemur*)
			eval "grep -q $1 $ini_path/global.ini"
			if [ "$?" -eq 0 ]; then
				cp $ini_path/global.ini /tmp
				eval "sed -i '/$1=/c $1=$2' /tmp/global.ini"
				cp /tmp/global.ini $ini_path/
				rm -f /tmp/global.ini
			else
				echo $1=$2 >> "$ini_path/global.ini"
			fi
		;;
		*)
			eval $update_ini_cmd
		;;
		esac

		[ -n "${CFG80211_UPDATE_FILE}" ] && echo $update_ini_cmd >> $log_file
		sync
	}
}

function update_internal_ini()
{
	local ini_path board_name
	local file
	ini_path=$(get_config_file_path "ini")

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	[ -f "$ini_path/internal/$1" ] && {
		file="$ini_path/internal/$1"
		update_ini_cmd="grep -q $2 $file && sed -i '/$2=/c $2=$3' $file || echo \"\$(awk '/.*\\[.*\\].*/ && !s { s = 1; print \"'\$2'='\$3'\"}1' \$file)\" > $file"

		case "$board_name" in
		ap-sdxlemur*)
			eval "grep -q $2 $ini_path/internal/$1"
			if [ "$?" -eq 0 ]; then
				cp $ini_path/internal/$1 /tmp/$1
				eval "sed -i '/$2=/c $2=$3' /tmp/$1"
				cp /tmp/$1 $ini_path/internal/$1
				rm -f /tmp/$1
			else
				echo $2=$3 >> "$ini_path/internal/$1"
			fi
		;;
		*)
			eval $update_ini_cmd
		;;
		esac

		[ -n "${CFG80211_UPDATE_FILE}" ] && echo $update_ini_cmd >> $log_file
		sync
	}
}

function update_ini_for_hk_sbs()
{
	update_internal_ini $1 dp_tx_device_limit 49152
	sync
}

function update_ini_for_hk_dbs()
{
	update_internal_ini $1 dp_tx_device_limit 49152
	sync
}

function update_ini_nss_info()
{
	[ -f /lib/wifi/wifi_nss_hk_olnum ] && { \
		local hk_ol_num="$(cat /lib/wifi/wifi_nss_hk_olnum)"
		if [ -e /sys/firmware/devicetree/base/MP_512 ]; then
			if [ $hk_ol_num -eq 3 ]; then
				update_internal_ini QCA8074V2_i.ini dp_nss_3radio_ring 1
				update_internal_ini QCA6018_i.ini dp_nss_3radio_ring 1
			else
				update_internal_ini QCA8074V2_i.ini dp_nss_3radio_ring 0
				update_internal_ini QCA6018_i.ini dp_nss_3radio_ring 0
			fi
		fi
	}
	sync
}

function update_ini_ppe_vp_core_mask()
{
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	case "$board_name" in
	ap-mi*)
		[ -f /ini/internal/QCN9224_i.ini ] && {
			update_internal_ini QCN9224_i.ini ppe_vp_core_mask 0x7
		}
		[ -f /ini/internal/QCA5332_i.ini ] && {
			update_internal_ini QCA5332_i.ini ppe_vp_core_mask 0x7
		}
		;;
	esac
}

function update_ini_reo_remap()
{
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	case "$board_name" in
	ap-hk01-c6*)
		[ -f /ini/internal/QCN9000_i.ini ] && {
			update_internal_ini QCN9000_i.ini dp_reo_rings_map 0x8
		}
		;;

	ap-hk14* | ap-al*)
		[ -f /ini/internal/QCN9000_i.ini ] && {
			update_internal_ini QCN9000_i.ini dp_reo_rings_map 0xC
		}
		;;

	ap-mi*)
		[ -f /ini/internal/QCN9224_i.ini ] && {
			update_internal_ini QCN9224_i.ini dp_reo_rings_map 0x7
		}
		[ -f /ini/internal/QCA5332_i.ini ] && {
			update_internal_ini QCA5332_i.ini dp_reo_rings_map 0x7
		}
		;;
	esac
}

function update_ini_napi_scale_factor()
{
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	case "$board_name" in
	ap-al*)
		[ -f /ini/internal/QCN9000_i.ini ] && {
			update_internal_ini QCN9000_i.ini dp_napi_scale_factor 2
		}
		[ -f /ini/internal/QCN9224_i.ini ] && {
			update_internal_ini QCN9224_i.ini dp_napi_scale_factor 1
		}
		[ -f /ini/internal/QCA9574_i.ini ] && {
			update_internal_ini QCA9574_i.ini dp_napi_scale_factor 2
		}
		[ -f /ini/internal/QCA5332_i.ini ] && {
			update_internal_ini QCA5332_i.ini dp_napi_scale_factor 2
		}
		;;
	ap-mi*)
		[ -f /ini/internal/QCN9224_i.ini ] && {
			update_internal_ini QCN9224_i.ini dp_napi_scale_factor 1
		}
		[ -f /ini/internal/QCA5332_i.ini ] && {
			update_internal_ini QCA5332_i.ini dp_napi_scale_factor 1
		}
		;;
	esac
}

function update_ini_refill_ring_size()
{
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	case "$board_name" in
	ap-al*)
		[ -f /ini/internal/QCN9000_i.ini ] && {
			update_internal_ini QCN9000_i.ini dp_rxdma_refill_ring 2048
		}
		[ -f /ini/internal/QCA9574_i.ini ] && {
			update_internal_ini QCA9574_i.ini dp_rxdma_refill_ring 2048
		}
		;;
	esac
}

function update_ini_target_dp_rx_hash_reset()
{
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	case "$board_name" in
	ap-hk14* | ap-hk01-c6*)
		update_internal_ini QCA8074V2_i.ini dp_rx_hash 0
		;;
	ap-al*)
		update_internal_ini QCA9574_i.ini dp_rx_hash 0xF
		;;
	esac
}

function update_ini_target_dp_default_reo_reset()
{
	local board_name ini_path
	local nss_wifi_olcfg

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	ini_path=$(get_config_file_path "ini")
	config_get nss_wifi_olcfg qcawifi nss_wifi_olcfg

	# on RDP 430 ( Four Radio RDP restrict both 5G interfaces from 8074V2 to single REO
	case "$board_name" in
	ap-hk01-c6*)
		[ -f $ini_path/internal/QCA8074V2_i.ini ] && {
		if [ -n "$nss_wifi_olcfg" ] && [ "$nss_wifi_olcfg" == "0" ]; then
			update_internal_ini QCA8074V2_i.ini dp_nss_4radio_rdp_reo 1
		else
			update_internal_ini QCA8074V2_i.ini dp_nss_4radio_rdp_reo 0
		fi
		}
		;;
	esac
}

function update_ini_for_512MP_dp_tx_desc()
{
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	if [ $1 != "QCN9000_i.ini" ] && [ $1 != "QCN6122_i.ini" ] && [ $1 != "QCN9224_i.ini" ] && [ $1 != "QCN9160_i.ini" ]; then
		# For RDPs that have QCN9000, internal radio config in 512M
		# profile is on par with 256M profile values
		case "$board_name" in
		ap-cp01-c3|ap-hk10*|ap-hk14*|ap-al*)
			update_internal_ini $1 dp_tx_desc_use_512p 1
			;;
		*)
			update_internal_ini $1 dp_tx_desc_use_512p 0
			;;
		esac
	fi
	sync
}

function update_ini_for_512MP_P_build()
{
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	if [ $1 != "QCN9000_i.ini" ] && [ $1 != "QCN6122_i.ini" ] && [ $1 != "QCN9224_i.ini" ] && [ $1 != "QCN9160_i.ini" ]; then
		case "$board_name" in
		ap-cp*|ap-mp*)
			update_internal_ini $1 dp_mon_ring_per_512M 1
			;;
		*)
			update_internal_ini $1 dp_mon_ring_per_512M 0
			;;
		esac
	fi
	sync
}

is_cnss_diag_logging_enabled()
{
	local cnss_diag_log=""

	config_load cnss_diag
	config_get_bool cnss_logging_enable global enable 0

	if [ -n "$cnss_logging_enable" ] && [ "$cnss_logging_enable" != "0" ]
	then
		cnss_diag_log=1
		echo $cnss_diag_log
	else
		cnss_diag_log=0
		echo $cnss_diag_log
	fi
}

function update_ini_for_tx_vdev_id_check()
{
	config_get dp_tx_allow_per_pkt_vdev_id_check qcawifi dp_tx_allow_per_pkt_vdev_id_check
	if [ -n "$dp_tx_allow_per_pkt_vdev_id_check" ]; then
		update_internal_ini QCA8074_i.ini dp_tx_allow_per_pkt_vdev_id_check "$dp_tx_allow_per_pkt_vdev_id_check"
		update_internal_ini QCA8074V2_i.ini dp_tx_allow_per_pkt_vdev_id_check "$dp_tx_allow_per_pkt_vdev_id_check"
		update_internal_ini QCA6018_i.ini dp_tx_allow_per_pkt_vdev_id_check "$dp_tx_allow_per_pkt_vdev_id_check"
		update_internal_ini QCA5018_i.ini dp_tx_allow_per_pkt_vdev_id_check "$dp_tx_allow_per_pkt_vdev_id_check"
		update_internal_ini QCN9000_i.ini dp_tx_allow_per_pkt_vdev_id_check "$dp_tx_allow_per_pkt_vdev_id_check"
	else
		update_internal_ini QCA8074_i.ini dp_tx_allow_per_pkt_vdev_id_check 0
		update_internal_ini QCA8074V2_i.ini dp_tx_allow_per_pkt_vdev_id_check 0
		update_internal_ini QCA6018_i.ini dp_tx_allow_per_pkt_vdev_id_check 0
		update_internal_ini QCA5018_i.ini dp_tx_allow_per_pkt_vdev_id_check 0
		update_internal_ini QCN9000_i.ini dp_tx_allow_per_pkt_vdev_id_check 0
	fi
}

#Each radio is mapped to 4 bit priority. Higher value has high priority.
#Based on number of radios in board, priority is aggregated and
#populated into global ini.
#Eg: Board ap-hk10-c2 - 0x01. First radio is higher priority than second.
config_nss_wifi_radio_pri_map()
{
	local board_name="$1"
	local nss_wifi_radio_pri_map=0

	case "$board_name" in
		ap-hk10-c1) nss_wifi_radio_pri_map=$((0x110));;
		ap-hk10-c2) nss_wifi_radio_pri_map=$((0x01));;
		ap-hk14) nss_wifi_radio_pri_map=$((0x101));;
		ap-cp01-c3) nss_wifi_radio_pri_map=$((0x101));;
		ap-mp*) nss_wifi_radio_pri_map=$((0x110));;
		*) nss_wifi_radio_pri_map=$((0x1101));;
	esac
	update_internal_ini global_i.ini nss_wifi_radio_pri_map $nss_wifi_radio_pri_map
}

load_qcawificfg80211() {
	local umac_args
	local qdf_args
	local ol_args
	local cfg_low_targ_clkspeed
	local qca_da_needed=0
	local device
	local board_name
	local def_pktlog_support=1
	local hk_ol_num=0
	local def_iot_sim=0
	local cnssd_log=""
	local load_ol_mod=0
	local wmi_dir
	local recover=$1
	local ini_path cfg_def_path
	local force_hostapd_attach
	local sawf_telemetry=0
	local vap_mode=""

	get_vap_mode

	[ -f /tmp/sysinfo/board_name  ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	if [ "$recover" != "1" ]; then
		[ "$vap_mode" = "1" ] && [ "$1" = "wifi_load" ] && touch /tmp/event_fast_boot_in_progress
	fi

	ini_path=$(get_config_file_path "ini")
	case "$board_name" in
	ap-sdxlemur*) ;;
	*)
		echo_cmd -n "$ini_path" /sys/module/firmware_class/parameters/path
	;;
	esac

	case "$board_name" in
	ap-sdxpinn*)
		if [ -e /firmware/image/qcn9224 ]; then
			ln -s /firmware/image/qcn9224/ /lib/firmware/
		fi
	;;
	esac

	is_wal=`grep waltest_mode /proc/cmdline | wc -l`
	[ $is_wal = 1 ] && waltest_qcawificfg80211 $recover && return

	cfg_def_path=$(get_config_file_path "cfg_default")
	case "$board_name" in
	ap-sdxlemur*)
		# Due to SE Linux permissions, SDX board will always have
		# cfg-default directory created. So, copy ini files when
		# the directory is empty
		if [ -z "$(ls -A $cfg_def_path)" ]; then
			cp -rf $ini_path/ $cfg_def_path/
		fi
	;;
	*)
		if [ ! -d "$cfg_def_path" ]; then
			mkdir -p "$cfg_def_path"
			cp -rf $ini_path/ $cfg_def_path/
		fi
	;;
	esac

	case "$board_name" in
	ap-al*|ap-mi*)
		echo "***Service Aware Wifi: 0 in Alder platfrom***" > /dev/console
		update_internal_ini QCN9000_i.ini sawf 0
		update_internal_ini QCA9574_i.ini sawf 0
		update_internal_ini QCN9224_i.ini sawf 0
		update_internal_ini QCA5332_i.ini sawf 0
		update_internal_ini QCN9000_i.ini dp_sawf_stats 0
		update_internal_ini QCA9574_i.ini dp_sawf_stats 0
		update_internal_ini QCN9224_i.ini dp_sawf_stats 0
		update_internal_ini QCA5332_i.ini dp_sawf_stats 0
		if [ -d /sys/module/umac ]; then
			[ -d /sys/module/ecm_wifi_plugin ] || insmod_cmd ecm-wifi-plugin
		fi
		sawf_telemetry=1

		echo 0 > /sys/kernel/debug/ecm/ecm_classifier_emesh/sawf_enabled
		echo 1 > /sys/kernel/debug/ecm/ecm_classifier_dscp/enabled
	;;
	esac

	# Reset the global ini on wifi load. All relevent params will get updated via update_ini_file [config items] [value]
	# cp $cfg_def_path/ini/global.ini  $ini_path/global.ini

	local enable_cfg80211=`uci show qcacfg80211.config.enable |grep "qcacfg80211.config.enable='0'"`
	[ -n "$enable_cfg80211" ] && echo "qcawificfg80211 configuration is disable" > /dev/console && return 1;

	# Making sure all the radio types are 'qcawificfg80211'
	local check_qcawifi=`cat /etc/config/wireless | grep -Eo "\s*option\s*type\s*['\\s]*qcawifi['\\s]*$"`
	[ -n "$check_qcawifi" ] && sed -ie "s/\\soption\\stype.*$/\\toption type 'qcawificfg80211'/" /etc/config/wireless

	if [ "$recover" != "1" ]; then
		lock /var/run/wifilock
	fi

	update_ini_file cfg80211_config "1"
	config_get_bool testmode qcawifi testmode
	[ -n "$testmode" ] && append ol_args "testmode=$testmode"

	config_get vow_config qcawifi vow_config
	[ -n "$vow_config" ] && update_ini_file vow_config "$vow_config"

	config_get dpd_support qcawifi dpd_support
	[ -n "$dpd_support" ] && update_ini_file dpd_support "$dpd_support"

	config_get carrier_vow_config qcawifi carrier_vow_config
	[ -n "$carrier_vow_config" ] && update_ini_file carrier_vow_config "$carrier_vow_config"

	config_get fw_vow_stats_enable qcawifi fw_vow_stats_enable
	[ -n "$fw_vow_stats_enable" ] && update_ini_file fw_vow_stats_enable "$fw_vow_stats_enable"

	config_get ol_bk_min_free qcawifi ol_bk_min_free
	[ -n "$ol_bk_min_free" ] && update_ini_file OL_ACBKMinfree "$ol_bk_min_free"

	config_get ol_be_min_free qcawifi ol_be_min_free
	[ -n "$ol_be_min_free" ] && update_ini_file OL_ACBEMinfree "$ol_be_min_free"

	update_ini_for_tx_vdev_id_check

	config_get ol_vi_min_free qcawifi ol_vi_min_free
	[ -n "$ol_vi_min_free" ] && update_ini_file OL_ACVIMinfree "$ol_vi_min_free"

	config_get ol_vo_min_free qcawifi ol_vo_min_free
	[ -n "$ol_vo_min_free" ] && update_ini_file OL_ACVOMinfree "$ol_vo_min_free"

	config_get_bool ar900b_emu qcawifi ar900b_emu
	[ -n "$ar900b_emu" ] && append ol_args "ar900b_emu=$ar900b_emu"

	config_get frac qcawifi frac
	[ -n "$frac" ] && append ol_args "frac=$frac"

	config_get intval qcawifi intval
	[ -n "$intval" ] && append ol_args "intval=$intval"

	config_get atf_mode qcawifi atf_mode
	[ -n "$atf_mode" ] && append umac_args "atf_mode=$atf_mode"

	config_get atf_msdu_desc qcawifi atf_msdu_desc
	[ -n "$atf_msdu_desc" ] && append umac_args "atf_msdu_desc=$atf_msdu_desc"

	config_get atf_peers qcawifi atf_peers
	[ -n "$atf_peers" ] && append umac_args "atf_peers=$atf_peers"


	config_get atf_max_vdevs qcawifi atf_max_vdevs
	[ -n "$atf_max_vdevs" ] && append umac_args "atf_max_vdevs=$atf_max_vdevs"

	config_get fw_dump_options qcawifi fw_dump_options
	[ -n "$fw_dump_options" ] && update_ini_file fw_dump_options "$fw_dump_options"

	config_get enableuartprint qcawifi enableuartprint
	[ -n "$enableuartprint" ] && update_ini_file enableuartprint "$enableuartprint"

	config_get ar900b_20_targ_clk qcawifi ar900b_20_targ_clk
	[ -n "$ar900b_20_targ_clk" ] && append ol_args "ar900b_20_targ_clk=$ar900b_20_targ_clk"

	config_get qca9888_20_targ_clk qcawifi qca9888_20_targ_clk
	[ -n "$qca9888_20_targ_clk" ] && append ol_args "qca9888_20_targ_clk=$qca9888_20_targ_clk"

	cfg_low_targ_clkspeed=$(config_low_targ_clkspeed)
	[ -z "$qca9888_20_targ_clk" ] && [ $cfg_low_targ_clkspeed = "true" ] && append ol_args "qca9888_20_targ_clk=300000000"

	config_get max_descs qcawifi max_descs
	[ -n "$max_descs" ] && update_ini_file max_descs "$max_descs"

	config_get max_peers qcawifi max_peers
	if [ -n "$max_peers" ]; then
		update_ini_file max_peers "$max_peers"
	else
		update_ini_file max_peers 0
	fi

	config_get cce_disable qcawifi cce_disable
	[ -n "$cce_disable" ] && update_ini_file cce_disable "$cce_disable"

	config_get qwrap_enable qcawifi qwrap_enable 0
	[ -n "$qwrap_enable" ] && update_ini_file qwrap_enable "$qwrap_enable"

	echo "MLD Single Netdev is ENABLED" > /dev/console
	mld_netdev=1

	case "$board_name" in
	ap-al*|ap-mi*)
		case "$board_name" in
		ap-al01-c1|ap-al02-c1|ap-al02-c2|ap-al02-c3)
			config_get wds_ext qcawifi wds_ext 0
		;;
		*)
			if [ $mld_netdev == 1 ]; then
				config_get wds_ext qcawifi wds_ext 1
			else
				config_get wds_ext qcawifi wds_ext 0
			fi
		;;
		esac
	;;
	*)
		config_get wds_ext qcawifi wds_ext 0
	;;
	esac

	case "$wds_ext" in
		1|on|enabled)	wds_ext=1
			;;
		*)	wds_ext=0
			;;
	esac
	update_ini_file wds_ext "$wds_ext" >/dev/null 2>&1

	config_get mldev_mode_ap qcawifi mldev_mode_ap
	[ -n "$mldev_mode_ap" ] && update_ini_file mldev_mode_ap "$mldev_mode_ap"

	config_get mldev_mode_sta qcawifi mldev_mode_sta
	[ -n "$mldev_mode_sta" ] && update_ini_file mldev_mode_sta "$mldev_mode_sta"

	config_get otp_mod_param qcawifi otp_mod_param
	[ -n "$otp_mod_param" ] && update_ini_file otp_mod_param "$otp_mod_param"

	config_get max_active_peers qcawifi max_active_peers
	[ -n "$max_active_peers" ] && update_ini_file max_active_peers "$max_active_peers"

	config_get enable_smart_antenna qcawifi enable_smart_antenna
	[ -n "$enable_smart_antenna" ] && update_ini_file enable_smart_antenna "$enable_smart_antenna"

	config_get sa_validate_sw qcawifi sa_validate_sw
	[ -n "$sa_validate_sw" ] && update_ini_file sa_validate_sw "$sa_validate_sw"

	config_get peer_ext_stats qcawifi peer_ext_stats
	[ -n "$peer_ext_stats" ] && update_ini_file peer_ext_stats "$peer_ext_stats"

	config_get peer_jitter_stats qcawifi peer_jitter_stats
	[ -n "$peer_jitter_stats" ] && update_ini_file peer_jitter_stats "$peer_jitter_stats"

	config_get peer_link_stats qcawifi peer_link_stats
	[ -n "$peer_link_stats" ] && update_ini_file peer_link_stats "$peer_link_stats"

	config_get sawf qcawifi sawf
	if [ "$sawf" -eq 1 ]; then
		update_internal_ini QCN9000_i.ini sawf 1
		update_internal_ini QCA9574_i.ini sawf 1
		update_internal_ini QCN9224_i.ini sawf 1
		update_internal_ini QCA5332_i.ini sawf 1
		config_get sawf_stats qcawifi sawf_stats
		if [ -z "$sawf_stats" ]; then
			sawf_stats=7
		else
			if [ "$sawf_stats" -lt "0" -o "$sawf_stats" -gt "7" ]; then
				sawf_stats=0
			fi
		fi
		update_internal_ini QCN9000_i.ini dp_sawf_stats $sawf_stats
		update_internal_ini QCA9574_i.ini dp_sawf_stats $sawf_stats
		update_internal_ini QCN9224_i.ini dp_sawf_stats $sawf_stats
		update_internal_ini QCA5332_i.ini dp_sawf_stats $sawf_stats
		echo 3 > /sys/kernel/debug/ecm/ecm_classifier_emesh/sawf_enabled
		echo 0 > /sys/kernel/debug/ecm/ecm_classifier_dscp/enabled
	fi
	# Enable the radio scheme flag
	update_ini_file nss_wifi_radio_scheme_enable 1

	[ -e /sys/firmware/devicetree/base/MP_256 ] && {
		# Force all the radios in NSS offload mode on 256M profile
		case "$board_name" in
		ap-hk*|ap-ac*|ap-oa*|ap-cp*|ap-mp*)
			[ ! -f /lib/wifi/wifi_nss_olcfg ] && {
				echo_cmd 7 /lib/wifi/wifi_nss_olcfg
			}
			;;
		esac
	}

	#IPA related INI params, also enable IPA by default for 1x Pine if not configured by user
	config_get gIPAConfig qcawifi gIPAConfig
	if [ -n "$gIPAConfig" ]; then
		update_ini_file gIPAConfig "$gIPAConfig"
	fi

	config_get gIPADescSize qcawifi gIPADescSize
	if [ -n "$gIPADescSize" ]; then
		update_ini_file gIPADescSize "$gIPADescSize"
	fi

	config_get gIPAVlanEnable qcawifi gIPAVlanEnable
	if [ -n "$gIPAVlanEnable" ]; then
		update_ini_file gIPAVlanEnable "$gIPAVlanEnable"
	fi

	# INI to enable MLO link add reassoc for client
	config_get mlme_mlo_reconfig_reassoc_enable qcawifi mlme_mlo_reconfig_reassoc_enable
	if [ -n "$mlme_mlo_reconfig_reassoc_enable" ]; then
		update_ini_file mlme_mlo_reconfig_reassoc_enable "$mlme_mlo_reconfig_reassoc_enable"
	fi

	local mldev_mode
	local ini_p
	ini_p=$(get_config_file_path "ini")
	mldev_mode="$(grep "mldev_mode_ap" \
			$ini_p/global.ini | awk -F '=' '{print $2}')"
	# Disable PPE for unified non-bond and hybrid non-bond mlo models
	if [ $mldev_mode -eq 0 ] || [ $mldev_mode -eq 2 ]; then
		update_internal_ini QCN9224_i.ini ppe_ds_enable 0
	elif [ "$board_name" = "ap-al02-c11" ]; then
		update_internal_ini QCN9224_i.ini ppe_ds_enable 0
	fi
	# Disable HW offload stats in Hybrid MLO model
	if [ $mldev_mode -eq 2 ]; then
		update_internal_ini QCN9224_i.ini vdev_stats_hw_offload_config 0
	fi

	#limit no of clients supported by SDX_PINE
	case "$board_name" in
	ap-sdxlemur*)
		update_internal_ini QCN9000_i.ini num_peers 128
		config_get gIPAWds qcawifi gIPAWds
		if [ $gIPAWds != 0 ]; then
			update_internal_ini QCN9000_i.ini num_vdev 7
		else
			update_internal_ini QCN9000_i.ini num_vdev 2
		fi
		update_internal_ini QCN9000_i.ini num_monitor_vaps 0
		update_internal_ini QCN9000_i.ini dp_reo_cmd_ring 1024
	;;
	esac

	config_get gIPAWds qcawifi gIPAWds
	if [ -n "$gIPAWds" ]; then
		update_ini_file gIPAWds "$gIPAWds"
	fi

	config_get nss_wifi_olcfg qcawifi nss_wifi_olcfg
	if [ -n "$nss_wifi_olcfg" ]; then
		[ -e /sys/firmware/devicetree/base/MP_256 ] && {
			if [ $nss_wifi_olcfg = 0 ]; then
				echo "****** HOST mode not supported in low memory profile ******" > /dev/console
				if [ "$recover" != "1" ]; then
					lock -u /var/run/wifilock
				fi
				return
			fi
		}
		update_ini_file nss_wifi_olcfg "$nss_wifi_olcfg"
		if [ $nss_wifi_olcfg != 0 ]; then
			update_ini_file dp_rx_hash 0
		else
			update_ini_file dp_rx_hash 1
		fi
		config_get nss_wifi_nxthop_cfg qcawifi nss_wifi_nxthop_cfg
		if [ -n "$nss_wifi_nxthop_cfg" ]; then
		    update_ini_file nss_wifi_nxthop_cfg "$nss_wifi_nxthop_cfg"
		fi
	elif [ -f /lib/wifi/wifi_nss_olcfg ]; then
		nss_wifi_olcfg="$(cat /lib/wifi/wifi_nss_olcfg)"

		if [ $nss_wifi_olcfg != 0 ]; then
			if [ -f /lib/wifi/wifi_nss_override ] && [ $(cat /lib/wifi/wifi_nss_override) = 1 ]; then
				echo "NSS offload disabled due to unsupported config" >&2
				update_ini_file nss_wifi_olcfg 0
				update_ini_file dp_rx_hash 1
			else
				update_ini_file nss_wifi_olcfg "$nss_wifi_olcfg"
				update_ini_file dp_rx_hash 0
			fi
		else
			update_ini_file nss_wifi_olcfg 0
			update_ini_file dp_rx_hash 1
		fi
	fi

	config_get ppeds_wifi_soc_cfg qcawifi ppeds_wifi_soc_cfg
	[ -n "$ppeds_wifi_soc_cfg" ] && update_ini_file ppeds_wifi_soc_cfg "$ppeds_wifi_soc_cfg"

	config_get max_clients qcawifi max_clients
	[ -n "$max_clients" ] && update_ini_file max_clients "$max_clients"

	config_get enable_peer_extended_rate_stats qcawifi enable_peer_extended_rate_stats
	[ -n "$enable_peer_extended_rate_stats" ] && update_ini_file enable_peer_extended_rate_stats "$enable_peer_extended_rate_stats"

	config_get enable_peer_extended_link_stats qcawifi enable_peer_extended_link_stats
	[ -n "$enable_peer_extended_link_stats" ] && update_ini_file enable_peer_extended_link_stats "$enable_peer_extended_link_stats"

	config_get max_vaps qcawifi max_vaps
	[ -n "$max_vaps" ] && update_ini_file max_vaps "$max_vaps"

	config_get enable_smart_antenna_da qcawifi enable_smart_antenna_da
	[ -n "$enable_smart_antenna_da" ] && update_ini_file enable_smart_antenna_da "$enable_smart_antenna_da"

	config_get reset_scan_spcl_vap_stats_enable qcawifi reset_scan_spcl_vap_stats_enable
	[ -n "$reset_scan_spcl_vap_stats_enable" ] && update_ini_file reset_scan_spcl_vap_stats_enable "$reset_scan_spcl_vap_stats_enable"

	config_get prealloc_disabled qcawifi prealloc_disabled
	[ -n "$prealloc_disabled" ] && append qdf_args "prealloc_disabled=$prealloc_disabled"

	config_get mem_debug_disabled qcawifi mem_debug_disabled
	if [ -n "$mem_debug_disabled" ]; then
		append qdf_args "mem_debug_disabled=$mem_debug_disabled"
	else
		append qdf_args "mem_debug_disabled=1"
	fi

	cnssd_log=$( is_cnss_diag_logging_enabled )
	config_get dump_at_kernel_enable qcawifi dump_at_kernel_enable

	if [ $cnssd_log = "1" ]
	then
		if [ -n "$dump_at_kernel_enable" ]; then
			append qdf_args "qdf_log_dump_at_kernel_enable=$dump_at_kernel_enable"
		else
			append qdf_args "qdf_log_dump_at_kernel_enable=0"
		fi
	fi

	config_get flush_timer_period qcawifi flush_timer_period
	if [ $cnssd_log = "1" ]
	then
		if [ -n "$flush_timer_period" ]; then
			append qdf_args "qdf_log_flush_timer_period=$flush_timer_period"
		else
			append qdf_args "qdf_log_flush_timer_period=50"
		fi
	fi

	config_get logger_enable_mask qcawifi logger_enable_mask
	if [ $cnssd_log = "1" ]
	then
		if [ -n "$logger_enable_mask" ]; then
			update_ini_file logger_enable_mask "$logger_enable_mask"
		else
			update_ini_file logger_enable_mask "14"
		fi
	else
		update_ini_file logger_enable_mask "0"
	fi

	if [ -n "$nss_wifi_olcfg" ] && [ "$nss_wifi_olcfg" != "0" ]; then
	local kasan="$(zcat /proc/config.gz | grep -rw "CONFIG_KASAN=y")"
	local mp_256="$(ls /proc/device-tree/ | grep -rw "MP_256")"
	local mp_512="$(ls /proc/device-tree/ | grep -rw "MP_512")"
	sysctl dev.nss.n2hcfg.n2h_high_water_core0 >/dev/null 2>/dev/null
	[ -n "${CFG80211_UPDATE_FILE}" ] && echo "sysctl dev.nss.n2hcfg.n2h_high_water_core0" >> $log_file
	#update the ini nss info
	update_ini_nss_info

	#If this is a first time load, then remove the one radio up file
	if [ ! -d /sys/module/qca_ol ] && [ -f /tmp/wifi_nss_up_one_radio ]; then
		rm /tmp/wifi_nss_up_one_radio
	fi

	if [ "$mp_256" == "MP_256" ]; then
		hk_ol_num="$(cat /lib/wifi/wifi_nss_hk_olnum)"
		if [ $hk_ol_radio -eq 3 ]; then
			sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 1900000
			sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 23504
			sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 0
		else
		#total pbuf size is 160 bytes,allocate memory for 4616 pbufs
			sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 800000
			sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 16336
			sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 0
		fi
	elif [ "$mp_512" == "MP_512" -a "$kasan" == "CONFIG_KASAN=y" ]; then
		hk_ol_num="$(cat /lib/wifi/wifi_nss_hk_olnum)"
		if [ $hk_ol_radio -eq 3 ]; then
			sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 1900000
			sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 23504
			sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 0
		else
		#total pbuf size is 160 bytes,allocate memory for 4616 pbufs
			sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 800000
			sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 16336
			sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 0
		fi
	elif [ "$mp_512" == "MP_512" ]; then
			if [ ! -f /tmp/wifi_nss_up_one_radio ]; then
				touch /tmp/wifi_nss_up_one_radio
			hk_ol_num="$(cat /lib/wifi/wifi_nss_hk_olnum)"
			if [ $hk_ol_num -eq 3 ]; then
				#total pbuf size is 160 bytes,allocate memory for 19928 pbufs
				sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 3200000
				sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 31648
				sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 0
			else
				#total pbuf size is 160 bytes,allocate memory for 18904 pbufs
				sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 3100000
				sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 30624
				sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 8192
			fi
		fi
	else
	case "$board_name" in
	ap-hk09*)
			local soc_version_major="$(cat /sys/module/ipq_cnss2/parameters/soc_version_major)"

			if [ $soc_version_major = 2 ];then
				if [ ! -f /tmp/wifi_nss_up_one_radio ]; then
					touch /tmp/wifi_nss_up_one_radio
					#total pbuf size is 160 bytes,allocate memory for 55672 pbufs
					sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 9000000
					sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 67392
					#initially after init 4k buf for 5G and 4k for 2G will be allocated, later range will be configured
					sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 40960
				fi
			else
				#total pbuf size is 160 bytes,allocate memory for 57184 pbufs
				sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 9200000
				sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 68904
				sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 32768
			fi
	;;
	ap-hk* | ap-oak* | ap-ac* | ap-mp* | ap-cp*)
		hk_ol_num="$(cat /lib/wifi/wifi_nss_hk_olnum)"
		if [ ! -f /tmp/wifi_nss_up_one_radio ]; then
			touch /tmp/wifi_nss_up_one_radio
			if [ $hk_ol_num -ge 3 ]; then
				#total pbuf size is 160 bytes,allocate memory for 93560 pbufs
				#NSS general payload(8000),Rx Buffer per radio(4k),Tx queue buffer per radio(1k), intial TX allocation per radio(4k)
				#Radio     TxDescRange0   TxDescRange1     TxDescRange2        TxDescRange3
				#           (<=64 clients) (<=128 clients) (<=256 clients)    (>256 clients)
				#5G-Hi        24k          24k                  24k                  32k
				#2G           16k          16k                  16k                  16k
				#5G-Low       24k          24k                  24k                  32k
				#Absolute high water=NSS payloads + Rx buf per radio + Tx queue per radio + TxDescRange3(5g-low/5g-hi/2g)
				#wifi pool buff = Min(Total tx desc at range 3, device_limit) - total intial tx allocation
				#extra pbuf core0 = (high_water_core0 - (NSS + OCM buffers)) * pbuf_size
				#       where NSS+OCM buffers = 11720 and pbuf_size = 160
				sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 10000000
				sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 72512
				#initially after init 4k buf for 5G and 4k for 2G will be allocated, then range will be configured
				sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 36864
			else
				#total pbuf size is 160 bytes,allocate memory for 55672 pbufs
				sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 9000000
				sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 67392
				#initially after init 4k buf for 5G and 4k for 2G will be allocated, then range will be configured
				sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 40960
			fi
		fi
	;;
	*)
		#total pbuf size is 160 bytes,allocate memory for 48456 pbufs
		sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 7800000
		sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 60176
		sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 35840
	;;
	esac
	fi
	fi

	config_get lteu_support qcawifi lteu_support
	[ -n "$lteu_support" ] && update_ini_file lteu_support "$lteu_support"

	config_get tgt_sched_params qcawifi tgt_sched_params
	[ -n "$tgt_sched_params" ] && update_ini_file tgt_sched_params "$tgt_sched_params"

	config_get enable_mesh_support qcawifi enable_mesh_support
	[ -n "$enable_mesh_support" ] && update_ini_file mesh_support "$enable_mesh_support"

	config_get enable_eapol_minrate qcawifi enable_eapol_minrate
	[ -n "$enable_eapol_minrate" ] && update_ini_file eapol_minrate_set "$enable_eapol_minrate"

	config_get set_eapol_minrate_ac qcawifi set_eapol_minrate_ac
	[ -n "$set_eapol_minrate_ac" ] && update_ini_file eapol_minrate_ac_set "$set_eapol_minrate_ac"

	if [ -n "$enable_mesh_support" ]
	then
		config_get enable_mesh_peer_cap_update qcawifi enable_mesh_peer_cap_update
		[ -n "$enable_mesh_peer_cap_update" ] && append umac_args "enable_mesh_peer_cap_update=$enable_mesh_peer_cap_update"
	fi

	config_get enable_pktlog_support qcawifi enable_pktlog_support $def_pktlog_support
	[ -n "$enable_pktlog_support" ] && append umac_args "enable_pktlog_support=$enable_pktlog_support"

	config_get g_unicast_deauth_on_stop qcawifi g_unicast_deauth_on_stop $g_unicast_deauth_on_stop
	[ -n "$g_unicast_deauth_on_stop" ] && append umac_args "g_unicast_deauth_on_stop=$g_unicast_deauth_on_stop"

	config_get qld_max_list qcawifi qld_max_list $qld_max_list
	[ -n "$qld_max_list" ] && append umac_args "qld_max_list=$qld_max_list"

	config_get beacon_offload_disable qcawifi beacon_offload_disable
	[ -n "$beacon_offload_disable" ] && update_ini_file beacon_offload_disable "$beacon_offload_disable"

	config_get spectral_disable qcawifi spectral_disable
	[ -n "$spectral_disable" ] && update_ini_file spectral_disable "$spectral_disable"

	config_get mgmt_rx_reo_enable qcawifi mgmt_rx_reo_enable
	[ -n "$mgmt_rx_reo_enable" ] && update_ini_file mgmt_rx_reo_enable "$mgmt_rx_reo_enable"

	config_get mgmt_rx_reo_scheduler_enable qcawifi mgmt_rx_reo_scheduler_enable
	[ -n "$mgmt_rx_reo_scheduler_enable" ] && update_ini_file mgmt_rx_reo_scheduler_enable "$mgmt_rx_reo_scheduler_enable"

	config_get mgmt_rx_reo_pkt_ctr_delta_thresh qcawifi mgmt_rx_reo_pkt_ctr_delta_thresh
	[ -n "$mgmt_rx_reo_pkt_ctr_delta_thresh" ] && update_ini_file mgmt_rx_reo_pkt_ctr_delta_thresh "$mgmt_rx_reo_pkt_ctr_delta_thresh"

	config_get mgmt_rx_reo_ingress_frame_debug_list_size qcawifi mgmt_rx_reo_ingress_frame_debug_list_size
	[ -n "$mgmt_rx_reo_ingress_frame_debug_list_size" ] && update_ini_file mgmt_rx_reo_ingress_frame_debug_list_size "$mgmt_rx_reo_ingress_frame_debug_list_size"

	config_get mgmt_rx_reo_egress_frame_debug_list_size qcawifi mgmt_rx_reo_egress_frame_debug_list_size
	[ -n "$mgmt_rx_reo_egress_frame_debug_list_size" ] && update_ini_file mgmt_rx_reo_egress_frame_debug_list_size "$mgmt_rx_reo_egress_frame_debug_list_size"

	config_get mgmt_rx_reo_scheduler_debug_list_size qcawifi mgmt_rx_reo_scheduler_debug_list_size
	[ -n "$mgmt_rx_reo_scheduler_debug_list_size" ] && update_ini_file mgmt_rx_reo_scheduler_debug_list_size "$mgmt_rx_reo_scheduler_debug_list_size"

	config_get twt_enable qcawifi twt_enable
	[ -n "$twt_enable" ] && update_ini_file twt_enable "$twt_enable"

	config_get b_twt_enable qcawifi b_twt_enable
	[ -n "$b_twt_enable" ] && update_ini_file b_twt_enable "$b_twt_enable"

	config_get r_twt_enable qcawifi r_twt_enable
	[ -n "$r_twt_enable" ] && update_ini_file r_twt_enable "$r_twt_enable"

	config_get t2lm_enable qcawifi t2lm_enable
	[ -n "$t2lm_enable" ] && update_ini_file t2lm_enable "$t2lm_enable"

	config_get default_t2lm_resp qcawifi default_t2lm_resp
	[ -n "$default_t2lm_resp" ] && update_ini_file default_t2lm_resp "$default_t2lm_resp"

	config_get allow_non_t2lm_sta_assoc qcawifi allow_non_t2lm_sta_assoc
	[ -n "$allow_non_t2lm_sta_assoc" ] && update_ini_file allow_non_t2lm_sta_assoc "$allow_non_t2lm_sta_assoc"

	config_get enable_mloadvert_degrade_on_cac qcawifi enable_mloadvert_degrade_on_cac
	[ -n "$enable_mloadvert_degrade_on_cac" ] && update_ini_file enable_mloadvert_degrade_on_cac "$enable_mloadvert_degrade_on_cac"

	config_get non_mlo_11be_ap_operation_enable qcawifi non_mlo_11be_ap_operation_enable
	[ -n "$non_mlo_11be_ap_operation_enable" ] && update_ini_file non_mlo_11be_ap_operation_enable "$non_mlo_11be_ap_operation_enable"

	config_get honor_supplicant_scan_ie qcawifi honor_supplicant_scan_ie
	[ -n "$honor_supplicant_scan_ie" ] && update_ini_file honor_supplicant_scan_ie "$honor_supplicant_scan_ie"

	config_get poison_spectral_bufs qcawifi poison_spectral_bufs
	[ -n "$poison_spectral_bufs" ] && update_ini_file poison_spectral_bufs "$poison_spectral_bufs"

	config_get mbss_ie_enable qcawifi mbss_ie_enable
	[ -n "$mbss_ie_enable" ] && update_ini_file mbss_ie_enable "$mbss_ie_enable"

	config_get disable_6ghz_mbssid qcawifi disable_6ghz_mbssid
	[ -n "$disable_6ghz_mbssid" ] && update_ini_file disable_6ghz_mbssid "$disable_6ghz_mbssid"

	config_get ema_ap_vendor_ie_size_low qcawifi ema_ap_vendor_ie_size_low
	[ -n "$ema_ap_vendor_ie_size_low" ] && update_ini_file ema_ap_vendor_ie_size_low "$ema_ap_vendor_ie_size_low"

	config_get ema_ap_vendor_ie_size_high qcawifi ema_ap_vendor_ie_size_high
	[ -n "$ema_ap_vendor_ie_size_high" ] && update_ini_file ema_ap_vendor_ie_size_high "$ema_ap_vendor_ie_size_high"

	config_get ema_ap_num_max_vaps qcawifi ema_ap_num_max_vaps
	[ -n "$ema_ap_num_max_vaps" ] && update_ini_file ema_ap_num_max_vaps "$ema_ap_num_max_vaps"

	config_get ema_ap_beacon_common_part_size qcawifi ema_ap_beacon_common_part_size
	[ -n "$ema_ap_beacon_common_part_size" ] && update_ini_file ema_ap_beacon_common_part_size "$ema_ap_beacon_common_part_size"

	config_get ema_ap_support_wps_in_6ghz qcawifi ema_ap_support_wps_in_6ghz
	[ -n "$ema_ap_support_wps_in_6ghz" ] && update_ini_file ema_ap_support_wps_in_6ghz "$ema_ap_support_wps_in_6ghz"

	config_get ema_ap_optional_ie_size qcawifi ema_ap_optional_ie_size
	[ -n "$ema_ap_optional_ie_size" ] && update_ini_file ema_ap_optional_ie_size "$ema_ap_optional_ie_size"

	config_get enable_ema_ap_ext qcawifi enable_ema_ap_ext
	[ -n "$enable_ema_ap_ext" ] && update_ini_file enable_ema_ap_ext "$enable_ema_ap_ext"

	config_get ema_ap_max_mgmt_frm_size qcawifi ema_ap_max_mgmt_frm_size
	[ -n "$ema_ap_max_mgmt_frm_size" ] && update_ini_file ema_ap_max_mgmt_frm_size "$ema_ap_max_mgmt_frm_size"

	config_get ema_ap_max_pp qcawifi ema_ap_max_pp
	[ -n "$ema_ap_max_pp" ] && update_ini_file ema_ap_max_pp "$ema_ap_max_pp"

	config_get ema_ap_rnr_field_size_limit qcawifi ema_ap_rnr_field_size_limit
	[ -n "$ema_ap_rnr_field_size_limit" ] && update_ini_file ema_ap_rnr_field_size_limit "$ema_ap_rnr_field_size_limit"

	config_get ap_bss_color_collision_detection qcawifi ap_bss_color_collision_detection
	[ -n "$ap_bss_color_collision_detection" ] && update_ini_file ap_bss_color_collision_detection "$ap_bss_color_collision_detection"

	config_get enable_6ghz_sp_pwrmode_supp qcawifi enable_6ghz_sp_pwrmode_supp
	[ -n "$enable_6ghz_sp_pwrmode_supp" ] && update_ini_file enable_6ghz_sp_pwrmode_supp "$enable_6ghz_sp_pwrmode_supp"

	config_get afc_disable_timer_check qcawifi afc_disable_timer_check
	[ -n "$afc_disable_timer_check" ] && update_ini_file afc_disable_timer_check "$afc_disable_timer_check"

	config_get afc_disable_request_id_check qcawifi afc_disable_request_id_check
	[ -n "$afc_disable_request_id_check" ] && update_ini_file afc_disable_request_id_check "$afc_disable_request_id_check"

	config_get afc_reg_no_action qcawifi afc_reg_no_action
	[ -n "$afc_reg_no_action" ] && update_ini_file afc_reg_no_action "$afc_reg_no_action"

	config_get spatial_reuse_enable qcawifi spatial_reuse_enable
	[ -n "$spatial_reuse_enable" ] && update_ini_file spatial_reuse_enable "$spatial_reuse_enable"

	config_get srp_non_srg_self_obss_pd_enable qcawifi srp_non_srg_self_obss_pd_enable
	[ -n "$srp_non_srg_self_obss_pd_enable" ] && update_ini_file srp_non_srg_self_obss_pd_enable "$srp_non_srg_self_obss_pd_enable"

	config_get allow_mon_vaps_in_sr qcawifi allow_mon_vaps_in_sr
	[ -n "$allow_mon_vaps_in_sr" ] && update_ini_file allow_mon_vaps_in_sr  "$allow_mon_vaps_in_sr"

	config_get rnr_6ghz_driver_override qcawifi rnr_6ghz_driver_override
	[ -n "$rnr_6ghz_driver_override" ] && update_ini_file rnr_6ghz_driver_override "$rnr_6ghz_driver_override"

	config_get rnr_selective_nontx_add qcawifi rnr_selective_nontx_add
	[ -n "$rnr_selective_nontx_add" ] && update_ini_file rnr_selective_nontx_add "$rnr_selective_nontx_add"

	config_get max_rnr_ie_allowed qcawifi max_rnr_ie_allowed
	[ -n "$max_rnr_ie_allowed" ] && update_ini_file max_rnr_ie_allowed "$max_rnr_ie_allowed"

	config_get re_ul_resp qcawifi re_ul_resp
	[ -n "$re_ul_resp" ] && update_ini_file re_ul_resp "$re_ul_resp"

	config_get_bool icm_enable icm enable 0
	if [ $icm_enable -ne 0 ]
	then
		update_ini_file externalacs_enable 1
	else
		update_ini_file externalacs_enable 0
	fi

	config_get iot_sim qcawifi iot_sim $def_iot_sim

	if [ -f "/lib/modules/qca-whunt-modules" ]; then
		load_qcawhunt
	fi

	config_get load_rawsimulation_mod qcawifi load_rawsimulation_mod 0

	config_get carrier_vow_optimization qcawifi carrier_vow_optimization
	[ -n "$carrier_vow_optimization" ] && update_ini_file carrier_vow_optimization "$carrier_vow_optimization"

	config_get scan_radio_tx_on_dfs_channels qcawifi scan_radio_tx_on_dfs_channels
	[ -n "$scan_radio_tx_on_dfs_channels" ] && update_ini_file scan_radio_tx_on_dfs_channels "$scan_radio_tx_on_dfs_channels"

	config_get direct_dma_handler_ctx qcawifi direct_dma_handler_ctx
	[ -n "$direct_dma_handler_ctx" ] && update_internal_ini global_i.ini direct_dma_handler_ctx "$direct_dma_handler_ctx"

	config_get spl_vap_get_pdev_stats qcawifi spl_vap_get_pdev_stats
	[ -n "$spl_vap_get_pdev_stats" ] && update_ini_file spl_vap_get_pdev_stats "$spl_vap_get_pdev_stats"

	config_get spl_vap_always_up qcawifi spl_vap_always_up
	[ -n "$spl_vap_always_up" ] && update_ini_file spl_vap_always_up "$spl_vap_always_up"

	config_get enable_eml_capability qcawifi enable_eml_capability
	[ -n "$enable_eml_capability" ] && update_ini_file enable_eml_capability "$enable_eml_capability"

	config_get msd_info_override_enable qcawifi msd_info_override_enable
	[ -n "$msd_info_override_enable" ] && update_ini_file msd_info_override_enable "$msd_info_override_enable"

	config_get msd_info_present_override qcawifi msd_info_present_override
	[ -n "$msd_info_present_override" ] && update_ini_file msd_info_present_override "$msd_info_present_override"

	config_get msd_info_value_override qcawifi msd_info_value_override
	[ -n "$msd_info_value_override" ] && update_ini_file msd_info_value_override "$msd_info_value_override"

	case "$board_name" in
	ap-sdxlemur*)
		config_get force_hostapd_attach qcawifi force_hostapd_attach 0
		if [ ! -d /sys/module/umac -a "$force_hostapd_attach" -eq 1 ]; then
			if [ -f /etc/init.d/qca-hostapd.init -a -f /etc/init.d/qca-wpa-supplicant.init ]; then
				. /etc/init.d/qca-hostapd.init
				boot > /dev/kmsg

				. /etc/init.d/qca-wpa-supplicant.init
				boot > /dev/kmsg
			else
				echo "Not starting hostapd/supplicant. Init files missing" > /dev/kmsg
			fi
		fi
	;;
	esac

	config_get carrier_profile_config qcawifi carrier_profile_config
	[ -n "$carrier_profile_config" ] && update_ini_file carrier_profile_config "$carrier_profile_config"

	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ] && [ -f /lib/wifi/.first_time_boot ] && [ -s /etc/config/wireless ]; then
		if [ "$recover" != "1" ]; then
			lock -u /var/run/wifilock
		fi
	fi

	for mod in $(cat /lib/wifi/qca-wifi-modules); do
		case ${mod} in
			umac) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} "${umac_args}" || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawificfg80211 $recover
					return 1
				}
			};;

			qdf) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} "${qdf_args}" || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawificfg80211 $recover
					return 1
				}
			};;

			qca_ol) [ -d /sys/module/${mod} ] || { \
				load_ol_mod=1
				do_cold_boot_calibration_qcawificfg80211
				insmod_cmd ${mod} ${ol_args} || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawificfg80211 $recover
					return 1
				}
			};;

			qca_da|ath_dev|hst_tx99|ath_rate_atheros|ath_hal) [ -f /tmp/no_qca_da ] || { \
				[ -d /sys/module/${mod} ] || { \
					insmod_cmd ${mod} || { \
						if [ "$recover" != "1" ]; then
							lock -u /var/run/wifilock
						fi
						unload_qcawificfg80211 $recover
						return 1
					}
				}
			};;

			ath_pktlog)
				if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
					lock /var/run/load_qcawificfg80211_lock
					[ $enable_pktlog_support -eq 0 ] && lock -u /var/run/load_qcawificfg80211_lock || { \
						[ -d /sys/module/${mod} ] || { \
							insmod_cmd ${mod} || { \
								if [ "$recover" != "1" ]; then
									lock -u /var/run/wifilock
								fi
								unload_qcawificfg80211 $recover
								lock -u /var/run/load_qcawificfg80211_lock
								return 1
							}
						}
						lock -u /var/run/load_qcawificfg80211_lock
					}
				else
					[ $enable_pktlog_support -eq 0 ] || { \
						[ -d /sys/module/${mod} ] || { \
							insmod_cmd ${mod} || { \
								if [ "$recover" != "1" ]; then
									lock -u /var/run/wifilock
								fi
								unload_qcawificfg80211 $recover
								return 1
							}
						}
					}
				fi
			;;

			wifi_3_0_sim0) [ -d /sys/module/${mod} ] || { \
				insmod ${mod} netlink_son_ald=18 "${qdf_args}" "${umac_args}" "${ol_args}" || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawificfg80211 $recover
					return 1
				}
			};;

			wifi_3_0_sim1) [ -d /sys/module/${mod} ] || { \
				insmod ${mod} netlink_ath_ssid_event=20 netlink_band_steering_event=22 netlink_acfg=23 netlink_son_ald=25 "${qdf_args}" "${umac_args}" "${ol_args}" || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawificfg80211 $recover
					return 1
				}
			};;


			wifi_3_0_sim2) [ -d /sys/module/${mod} ] || { \
				insmod ${mod} netlink_ath_ssid_event=27 netlink_band_steering_event=28 netlink_acfg=30 netlink_son_ald=31 "${qdf_args}" "${umac_args}" "${ol_args}" || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawificfg80211 $recover
					return 1
				}
			};;

			qca_iot_sim) [ $iot_sim -eq 1 ] && { \
				[ -d /sys/module/${mod} ] || { \
					insmod_cmd ${mod} || { \
						lock -u /var/run/wifilock
						unload_qcawificfg80211
						return 1
					}
				}
			};;

			rawmode_sim) [ $load_rawsimulation_mod -ne 0 ] && { \
				[ -d /sys/module/${mod} ] || { \
					insmod_cmd ${mod} || { \
						if [ "$recover" != "1" ]; then
							lock -u /var/run/wifilock
						fi
						unload_qcawificfg80211 $recover
						return 1
					}
				}
			};;

			*)
				if [ ${mod} = "wifi_3_0" ] && [ ! -d /sys/module/${mod} ]; then
					cd /lib/firmware/; bin=`find . -maxdepth 2 \( -name 'amss*' -o -name 'regdb*' \)`
					echo $bin > /dev/kmsg
				fi
				if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
					lock /var/run/load_qcawificfg80211_lock
					if [ ${mod} = "telemetry_agent" ] && [ $sawf_telemetry -eq 0 ]; then
						lock -u /var/run/load_qcawificfg80211_lock
						continue
					fi
					[ -d /sys/module/${mod} ] && lock -u /var/run/load_qcawificfg80211_lock || { \
						[ ${mod} = "wifi_3_0" ] && lock /var/run/load_module_lock
						insmod_cmd ${mod} || { \
							if [ "$recover" != "1" ]; then
								lock -u /var/run/wifilock
							fi
							lock -u /var/run/load_qcawificfg80211_lock
							[ ${mod} = "wifi_3_0" ] && lock -u /var/run/load_module_lock
							unload_qcawificfg80211 $recover
							return 1
						}
						[ ${mod} = "wifi_3_0" ] && lock -u /var/run/load_module_lock
						lock -u /var/run/load_qcawificfg80211_lock
					}
				else
					if [ ${mod} = "telemetry_agent" ] && [ $sawf_telemetry -eq 0 ]; then
						continue
					fi
					[ -d /sys/module/${mod} ] || { \
						insmod_cmd ${mod} || { \
							if [ "$recover" != "1" ]; then
								lock -u /var/run/wifilock
							fi
							unload_qcawificfg80211 $recover
							return 1
						}
					}
				fi
			;;

		esac
	done

	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ] && [ -f /lib/wifi/.first_time_boot ] && [ -s /etc/config/wireless ]; then
		if [ "$recover" != "1" ]; then
			lock -u /var/run/wifilock
		fi
		# waiting for all process to complete
		while ! test -f "/tmp/wifi_load_done"; do
			sleep 1
		done
		touch /tmp/first_boot_done

		return
	fi

	if [ $load_ol_mod -eq 1 ]; then
		for wmi_dir in /sys/kernel/debug/WMI_SOC*;do
			case "$board_name" in
				ap-hk*|ap-ac*|ap-cp*|ap-oak*|ap-mp*)
				if [ -f $wmi_dir/filtered_wmi_cmds ]; then
					echo 0x5002 > $wmi_dir/filtered_wmi_cmds
					echo 0x5003 > $wmi_dir/filtered_wmi_cmds
					echo 0x5004 > $wmi_dir/filtered_wmi_cmds
					echo 0x5006 > $wmi_dir/filtered_wmi_cmds
					echo 0x5007 > $wmi_dir/filtered_wmi_cmds
					echo 0x5024 > $wmi_dir/filtered_wmi_cmds
					echo 0x4028 > $wmi_dir/filtered_wmi_cmds
				fi
				if [ -f $wmi_dir/filtered_wmi_evts ]; then
					echo 0x5001 > $wmi_dir/filtered_wmi_evts
					echo 0x5002 > $wmi_dir/filtered_wmi_evts
					echo 0x5006 > $wmi_dir/filtered_wmi_evts
					echo 0x5012 > $wmi_dir/filtered_wmi_evts
					echo 0x4023 > $wmi_dir/filtered_wmi_evts
				fi
				;;
				*)
				if [ -f $wmi_dir/filtered_wmi_cmds ]; then
					echo 0x9014 > $wmi_dir/filtered_wmi_cmds
					echo 0x9015 > $wmi_dir/filtered_wmi_cmds
					echo 0x9016 > $wmi_dir/filtered_wmi_cmds
					echo 0x9018 > $wmi_dir/filtered_wmi_cmds
					echo 0x9019 > $wmi_dir/filtered_wmi_cmds
					echo 0x9084 > $wmi_dir/filtered_wmi_cmds
					echo 0x9085 > $wmi_dir/filtered_wmi_cmds
				fi
				if [ -f $wmi_dir/filtered_wmi_evts ]; then
					echo 0x9004 > $wmi_dir/filtered_wmi_evts
					echo 0x9007 > $wmi_dir/filtered_wmi_evts
					echo 0x9047 > $wmi_dir/filtered_wmi_evts
					echo 0x9048 > $wmi_dir/filtered_wmi_evts
				fi
				;;
			esac

		done
	fi

	# Unload telemetry modules for unsupported platforms
	if [ $sawf_telemetry -eq 0 ]; then
		echo "sawf telemetry not enabled." >/dev/console
		rmmod telemetry_agent > /dev/null 2> /dev/null
	fi

	# Remove DA modules, if no DA chipset found
	for device in $(ls -d /sys/class/net/wifi* 2>&-); do
		[[ -f $device/is_offload ]] || {
			qca_da_needed=1
			break
		}
	done

	if [ $qca_da_needed -eq 0 ]; then
		if [ ! -f /tmp/no_qca_da ]; then
			echo "No Direct-Attach chipsets found." >/dev/console
			rmmod qca_da > /dev/null 2> /dev/null
			rmmod ath_dev > /dev/null 2> /dev/null
			rmmod hst_tx99 > /dev/null 2> /dev/null
			rmmod ath_rate_atheros > /dev/null 2> /dev/null
			rmmod ath_hal > /dev/null 2> /dev/null
			echo 1 > /tmp/no_qca_da
		fi
	fi

	if [ -f "/lib/update_smp_affinity.sh" ]; then
		. /lib/update_smp_affinity.sh
		config_foreach enable_smp_affinity_wifi wifi-device
	fi

	if [ "$recover" != "1" ]; then
		lock -u /var/run/wifilock
	fi

	update_ini_target_dp_default_reo_reset

	set_umac_reset_affinity
}

load_qcawhunt() {

	mkdir -p /tmp/sysinfo/
	echo "Qualcomm Technologies, Inc. IPQ807x/AP-HK09" > /tmp/sysinfo/model
	echo "ap-hk09" > /tmp/sysinfo/board_name
	avail_entropy=$(cat /proc/sys/kernel/random/entropy_avail)

	while [ $avail_entropy -eq 0 ]; do
		avail_entropy=$(cat /proc/sys/kernel/random/entropy_avail)
		echo " Generating entropy using rngd daemon !!!" >/dev/console
		rngd -b -r /dev/urandom
		sleep 1
		echo " Stopping rngd daemon !!!" >/dev/console
		killall rngd
	done

	# Disable HW vdev stats for Waikiki WHUNT execution
	[ -f /ini/internal/QCN9224_i.ini ] && {
		update_internal_ini QCN9224_i.ini vdev_stats_hw_offload_config 0
	}

	# Load whunt modules if the modules list is present
	if [ -f "/lib/modules/qca-whunt-modules" ]; then
		if [ -S /vendor/whunt/whunt_wcd_socket ]; then
			echo " wcd already enabled !!!" >/dev/console
		else
			echo " starting wcd !!!" >/dev/console
			/usr/sbin/wcd  -s /vendor/whunt/whunt_wcd_socket &
		fi
		for mod in $(cat /lib/modules/qca-whunt-modules); do
			case ${mod} in
				whunt_utils) [ -d /sys/module/${mod} ] || { \
					insmod ${mod}  || { \
						unload_qcawhunt
						return 1
					}
				};;
				whunt_core) [ -d /sys/module/${mod} ] || { \
					 modprobe ${mod}  || { \
						unload_qcawhunt
						return 1
					}
				};;

			esac
		done
	sleep 3
	fi
}
unload_qcawhunt() {
	for mod in $(cat /lib/modules/qca-whunt-modules | sed '1!G;h;$!d'); do
		case ${mod} in
			mem_manager) continue;
		esac
	[ -d /sys/module/${mod} ] && rmmod_cmd ${mod}
	done
	killall wcd
	rm /vendor/whunt/whunt_wcd_socket
}

clear_locks() {
	lock -u /var/run/post_load_qcawificfg80211_lock
	lock -u /var/run/post_detect_qcawificfg80211_lock
	lock -u /var/run/pre_qcawificfg80211_lock
	lock -u /var/run/post_qcawificfg80211_lock
	lock -u /var/run/load_qcawificfg80211_lock
	lock -u /var/run/qdss_support_lock
	lock -u /var/run/device_wifi0
	lock -u /var/run/device_wifi1
	lock -u /var/run/device_wifi2
	lock -u /var/run/device_wifi3
	lock -u /var/run/wifilock
}

unload_qcawificfg80211() {
	local recover=$1
	local vap_mode=""

	get_vap_mode
	config_load wireless
	config_foreach disable_qcawifi wifi-device

	eval "type qwrap_teardown" >/dev/null 2>&1 && qwrap_teardown

	if [ `eval pgrep qldtool` ]; then
		killall qldtool >/dev/null 2>&1
	fi

	if [ `eval pgrep lowi-server` ]; then
		eval "type lowi_teardown" >/dev/null 2>&1 && lowi_teardown
		sleep 3
	fi
	killall cfr_test_app
	if [ "$recover" != "1" ]; then
		lock /var/run/wifilock
	fi

	[ -d /sys/module/qca_nss_mscs/ ] && rmmod_cmd qca-nss-mscs
	[ -d /sys/module/ecm_wifi_plugin/ ] && rmmod_cmd ecm-wifi-plugin

	[ ! -f /etc/init.d/miwifi-roam ] || /etc/init.d/miwifi-roam stop

	lock /var/run/load_module_lock
	for mod in $(cat /lib/wifi/qca-wifi-modules | sed '1!G;h;$!d'); do
		case ${mod} in
			mem_manager) continue;
		esac
		[ -d /sys/module/${mod} ] && rmmod_cmd ${mod}
	done
	lock -u /var/run/load_module_lock

	if [ -f "/lib/modules/qca-whunt-modules" ]; then
		unload_qcawhunt
	fi
	if [ "$recover" != "1" ]; then
		lock -u /var/run/wifilock
	fi

	# check the ini file
	if [ "$vap_mode" = "1" ]; then
		rm -rf /tmp/event_*
		rm -rf /tmp/wifi_load_done
		rm -rf /tmp/vap_up_start
		rm -rf /tmp/this_is_event
		echo killall launch instance > /dev/console
		for ppid in $(ps | grep "[l]aunch_vap" | awk '{print $1}'); do
			kill -9 $ppid
		done
		for ppid in $(ps | grep "[e]vent_reload_legacy" | awk '{print $1}'); do
			kill -9 $ppid
		done
		clear_locks
	fi
}

bridge_fdb_entry_add() {
	local device=$1
	local vif_name=$2
	local board_name net_cfg

	config_get mld "$vif" mld
	config_get ieee80211r "$vif" ieee80211r
	if [ -n "$mld" ] && [ -n "$ieee80211r" ]
	then
		[ -f /tmp/sysinfo/board_name  ] && {
			board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
		}

		net_cfg="$(find_net_config "$vif")"
		case "$board_name" in
			ap-sdxpinn*)
				local bridge_json="$(bridge_interface "$net_cfg")"
				json_load "$bridge_json"
				json_get_var bridge bridge
		;;
		*)
			bridge="$(bridge_interface "$net_cfg")"
		;;
		esac

		config_get macaddr "$device" macaddr
		bridge fdb add $macaddr dev $bridge local
	fi
}

bridge_fdb_entry_del() {
	local device=$1
	local vif_name=$2
	local board_name net_cfg

	config_get mld "$vif" mld
	config_get ieee80211r "$vif" ieee80211r
	if [ -n "$mld" ] && [ -n "$ieee80211r" ]
	then
		[ -f /tmp/sysinfo/board_name  ] && {
			board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
		}

		net_cfg="$(find_net_config "$vif")"
		case "$board_name" in
			ap-sdxpinn*)
				local bridge_json="$(bridge_interface "$net_cfg")"
				json_load "$bridge_json"
				json_get_var bridge bridge
		;;
		*)
			bridge="$(bridge_interface "$net_cfg")"
		;;
		esac

		config_get macaddr "$device" macaddr
		bridge fdb del $macaddr dev $bridge
	fi
}

set_vifs_down() {
	local device=$1
	local vif_name=$2
	local vif vifs
	config_get vifs "$device" vifs
	for vif in $vifs; do
		config_get ifname "$vif" ifname
		if [ "$ifname" = "$vif_name" ]; then
			bridge_fdb_entry_del $device $vif
			uci_revert_state wireless "$vif"
			break;
		else
			continue;
		fi
	done
}

disable_recover_qcawificfg80211() {
	local board_name
	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}
	disable_qcawificfg80211 1 "$@"
	[ -e /sys/firmware/devicetree/base/AUTO_MOUNT ] && {
		case "$board_name" in
			ap-mp*)
				touch /tmp/.crashed_$@
			;;
			*)
			;;
		esac
	}
}

enable_recover_qcawificfg80211() {
	local numcrashed
	local board_name
	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}
	enable_qcawificfg80211 1 "$@"
	mbss_tx_vdev_config $@ 1 1

	[ -e /sys/firmware/devicetree/base/AUTO_MOUNT ] && {
		numcrashed=`ls /tmp/.crashed* | wc -l`
		case "$board_name" in
			ap-mp*)
			[ $numcrashed == 1 ] && {
				. /etc/init.d/wifi_fw_mount
				stop_wifi_fw "IPQ5018"
			}
			;;
			*)
			;;
		esac
		rm -f /tmp/.crashed_$@
	}
}

_disable_qcawificfg80211() {
	local device="$1"
	local vifs_name="$2"
	local parent=
	local retval=0
	local recover=0
	local board_name ini_path
	local force_hostapd_attach

	if [ "$1" = "1" ]; then
		device="$2"
		vifs_name="$3"
		recover="$1"
	fi

	#Invoked from wifi_hw_mode script
	if [ "$3" = "1" ]; then
		vifs_name=
	fi

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	case "$board_name" in
	ap-sdxlemur*) config_get force_hostapd_attach qcawifi force_hostapd_attach 0 ;;
	*) force_hostapd_attach=1 ;;
	esac

	ini_path=$(get_config_file_path "ini")

	# Ap in dynamic mode means 3 radios will always be present
	# If in DBS mode then wifi2 should not be using cfg80211tool functions
	dynamic_hw_mode=`grep "dynamic_hw_mode" $ini_path/internal/global_i.ini | grep -m1 -v "^[#]" | awk -F'=' '{print $2}'`
	if [ "$dynamic_hw_mode" = "1" ]; then
		if [ $device = "wifi2" ]; then
			hw_mode_id=`retrieve_current_hw_mode`
			if [ $hw_mode_id -eq 1 ]; then
				return 0
			fi
		fi
	fi

	echo "$DRIVERS disable radio $device" >/dev/console

	find_qcawifi_phy "$device" >/dev/null || return 1

	# If qrfs is disabled in enable_qcawifi(),need to enable it
	if [ -f /var/qrfs_disabled_by_wifi ] && [ $(cat /var/qrfs_disabled_by_wifi) == 1 ]; then
		echo_cmd "1" /proc/qrfs/enable
		echo_cmd "0" /var/qrfs_disabled_by_wifi
	fi

	# disable_qcawifi also gets called for disabled radio during wifi up. Don't
	# remove the files if it gets from disabled radio.
	config_get disabled "$device" disabled
	if [ -f /tmp/wifi_nss_up_one_radio ] && [ "$disabled" = "0" ]; then
		rm /tmp/wifi_nss_up_one_radio
	fi
	config_get phy "$device" phy

	config_get vifs "$device" vifs
	if [ -z "$vifs_name" ]; then
		set_wifi_down "$device"
		for viface in $vifs; do
			bridge_fdb_entry_del $device $viface
		done
	else
		for vif in $vifs_name; do
			set_vifs_down $device $vif
		done
	fi

	case "$board_name" in
		ap-hk*|ap-ac*|ap-cp*|ap-oak*|ap-mp*|*emu*|ap-al*|ap-sdx*|ap-mi*)
		echo "Disable ol_stats for Lithium platforms"
		"$device_if" "$phy" enable_ol_stats 0
	;;
		*) echo "ol_stats is disabled for non-Lithium platforms"
	;;
	esac

	# in MBSS case, send notification to allow deletion of transmitting VAP
	config_get device_if "$device" device_if "cfg80211tool"
	config_get mbss_ie_enable qcawifi mbss_ie_enable
	if [ -n "$mbss_ie_enable" ]; then
		if [ "$mbss_ie_enable" != "0" ] && [ "$mbss_ie_enable" != "0x0" ]; then
		$device_if $device wifi_down_ind 1
		fi
	fi

	include /lib/network
	cd /sys/class/net
	for dev in *; do
		if [ ! -z "$vifs_name" ]; then
			found=0
			for vif in $vifs_name; do
				if [ "$dev" == "$vif" ]; then
					found=1;
					break;
				fi
			done

			if [ "$found" != "1" ]; then
				continue
			fi
		fi

		[ -f /sys/class/net/${dev}/parent ] && { \
			local parent=$(cat /sys/class/net/${dev}/parent)
			[ -n "$parent" -a "$parent" = "$device" ] && { \
				# Detach athX ifaces from hostapd/wpa_supplicant if "force_hostapd_attach" is set to 1.
				# IPQ/SDX75 boards will have it set to 1 always;
				# SDX65 boards can configure this option in the wireless file
				if [ "$force_hostapd_attach" -eq 1 ]; then
					[ -f "/var/run/hostapd-${dev}.lock" ] && { \
						kill "$(cat "/var/run/hostapd_cli-${dev}.pid")"
						wpa_cli -g /var/run/hostapd/global raw REMOVE ${dev}
						rm /var/run/hostapd-${dev}.lock
					}
					[ -f "/var/run/wpa_supplicant-${dev}.lock" ] && { \
						wpa_cli -g /var/run/wpa_supplicantglobal  interface_remove  ${dev}
						rm /var/run/wpa_supplicant-${dev}.lock
					}
				fi

				[ -f "/var/run/wapid-${dev}.conf" ] && { \
					wapid_supp_cli -g /var/run/wapid/global raw REMOVE ${dev}
					rm /var/run/wapid-${dev}.lock
				}

				ifconfig "$dev" down
				unbridge "$dev"
				if [ -z "$recover" ] || [ "$recover" -eq "0" ]; then
				    iw "$dev" del
				fi
			}
			[ -f /var/run/hostapd_cred_${device}.bin ] && { \
				rm /var/run/hostapd_cred_${device}.bin
			}
		}
	done

	return 0
}

destroy_vap() {
	local ifname="$1"
	ifconfig $ifname down
	wlanconfig $ifname destroy
}

disable_qcawificfg80211() {
	local vap_mode=""

	get_vap_mode
	[ "$2" = "wifi_reload" ] && set "$1"
	[ "$2" = "wifi_load" ] && set "$1"

	# wifi reload_legacy
	[ "$vap_mode" = "1" ] && [ -f /tmp/event_vap_nop ] && return

	if [ "$1" = "1" ]; then   #wifi_hw_mode only
        	_disable_qcawificfg80211 $@
	else
		if [ "$vap_mode" = "1" ]; then
			lock /var/run/load_module_lock
		else
			lock /var/run/wifilock
		fi

		_disable_qcawificfg80211 "$@"

		if [ "$vap_mode" = "1" ]; then
			lock -u /var/run/load_module_lock
		else
			lock -u /var/run/wifilock
		fi
	fi
}

#This function handles below cmds
#wifi multi_up/multi_down wifiX athX
#wifi multi_up/multi_down wifiX athX athXY
#wifi multi_up/multi_down wifiX athX athXY..wifiY athY athYY..
#wifi multi_up/multi_down mldX wifiX athX athXY..wifiY athY athYY.. mldY

multi_radio_wifi_updown() {
    lock_wifi
    local multi_ifname radio_ifname multi_vif_name multi_vifs_list
    local i=2 #first interface name starts from $2
    local j
    local all_vifs=
    local vifs_count
    local multi_vifs_count
    local mbss_tx_vap=0
    local mbss_tx_check=0
    local mbss_tx_grp=
    local clear_tx_grp=0
    local master_ath_list=""

    if [ -z "$gdevice" ]; then
            gdevice=$DEVICES
    fi

    echo -ne "pre_qcawificfg80211 "disable"\n"
    pre_qcawificfg80211 "disable" "multi_up"
    while [ ${i} -le ${#} ]; do
        eval "multi_ifname=\${${i}}";
        radio_ifname=$(echo $multi_ifname | grep -c "wifi")
        mld_ifname=$(echo $multi_ifname | grep -c "mld")

        if [ $radio_ifname = 1 ]; then
            j=$((i+1))
            multi_vifs_list=
            # There can be multiple athX interfaces passed
            # Concate them and send in multi_vifs_list
            while [ ${j} -le ${#} ]; do
                eval "multi_vif_name=\${${j}}";
                check_if_dev=$(echo $multi_vif_name|grep -c wifi)
                check_if_mld=$(echo $multi_vif_name|grep -c mld)

               [ $check_if_dev = 1 ] && break;
               [ $check_if_mld = 1 ] && break;

               master_ath_list="$master_ath_list $multi_vif_name"

               config_get vifmld $multi_vif_name mld
               if [ -z $vifmld ]; then
                   multi_vifs_list="$multi_vifs_list $multi_vif_name";
               fi
               j=$((j+1));
            done;

            scan_qcawificfg80211 "$multi_ifname"

            # If all available VAPs are passed as arg for multi_* cmd,
            # restart whole radio so that cleared radio params in driver
            # will get re-configured.
            all_vifs=
            config_get all_vifs "$multi_ifname" vifs
            vifs_count=$(echo "$all_vifs" | wc -w)
            multi_vifs_count=$(echo "$multi_vifs_list" | wc -w)
            [ ${vifs_count} = ${multi_vifs_count} ] && {
                echo -ne "Apply restart on Radio\n"
                multi_vifs_list=
                mbss_tx_vap=1
            }

            config_get disabled "$multi_ifname" disabled
            [ "$disabled" = "1" ] && {
                echo "'$multi_ifname' is disabled"
                set disable
            }

            echo -ne "disable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"\n"
            ubus_wifi_cmd "down" "$multi_ifname"
            disable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"

            if [ $1 = "multi_up" ]; then
                ubus_wifi_cmd "up" "$multi_ifname"
                pre_qcawificfg80211 "enable";
                echo -ne "enable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"\n"
                enable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"
                start_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"
            fi
            i=$((j))
        fi

        if [ $mld_ifname = 1 ]; then
             j=$((i+1))
             mld_dup=$multi_ifname

             # Remove MLD from bridge for multi up
             remove_mld_bridge $mld_dup

             for device in $gdevice; do
                 multi_ifname=$device
                 multi_vifs_list=
                 config_get disabled "$device" disabled
                 [ "$disabled" = "1" ] && {
                         echo "'$device' is disabled"
                         continue
                 }
                 scan_qcawificfg80211 $device
                 vifs=
                 config_get vifs "$device" vifs

                 for vif in $vifs; do
                         config_get ifmld "$vif" mld
                         config_get ifname "$vif" ifname
                         if [ $ifmld = $mld_dup ]; then
                                 master_ath_list="$master_ath_list $ifname"
                                 multi_vifs_list="$multi_vifs_list $ifname"
                         fi
                 done

                if [ -z $multi_vifs_list ]; then
                    continue
                fi

                 echo -ne "disable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"\n"
                 ubus_wifi_cmd "down" "$multi_ifname"
                 disable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"

                 if [ $1 = "multi_up" ]; then
                     ubus_wifi_cmd "up" "$multi_ifname"
                     pre_qcawificfg80211 "enable";
                     echo -ne "enable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"\n"
                     enable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"
                     # Add MLD bridge for multi up
                     add_mld_bridge $mld_dup
                 fi
             done

             [ "$1" == "multi_up" ] && for device in $gdevice; do
                 multi_ifname=$device
                 multi_vifs_list=
                 config_get disabled "$device" disabled
                 [ "$disabled" = "1" ] && {
                         echo "'$device' is disabled"
                         continue
                 }
                 scan_qcawificfg80211 $device
                 config_get vifs "$device" vifs

                 for vif in $vifs; do
                         config_get ifmld "$vif" mld
                         config_get ifname "$vif" ifname
                         if [ $ifmld = $mld_dup ]; then
                                 multi_vifs_list="$multi_vifs_list $ifname"
                         fi
                 done

                 if [ -z $multi_vifs_list ]; then
                      continue
                 fi

                 start_qcawificfg80211 "$multi_ifname" "$multi_vifs_list" "$mld_dup"
             done
             i=$((j))
        fi
    done

    if [ $1 = "multi_up" ]; then
         for device in $gdevice; do
             config_get disabled "$device" disabled
             [ "$disabled" = "1" ] && {
                     echo "'$device' is disabled"
                     continue
             }
             scan_qcawificfg80211 $device
             config_get vifs "$device" vifs

             for vif in $vifs; do
                 config_get ifname "$vif" ifname
                 check_vif=$(echo $master_ath_list|grep -c -w $ifname)

                 if [ "$check_vif" = 1 ]; then
                      config_get user_tx_config $vif mbss_tx_vdev
                      var=$(cfg80211tool $ifname g_mbss_tx_vdev)
                      mbss_tx_check=${var##*:}
                      if [ $user_tx_config = 1 ] && [ $user_tx_config != $mbss_tx_check ]; then
                            mbss_tx_vap=1
                            grp=$(cfg80211tool $ifname g_mbss_grp)
                            grp=${grp##*:}
                            tx_grp=""

                            if [ -n "$grp" ]; then
                                tx_grp="$device.$grp"
                            else
                                clear_tx_grp=1
                            fi

                            if [ -n "$tx_grp" ]; then
                                check_radio_name=$(echo $mbss_tx_grp|grep -c $tx_grp)
                                if [ $check_radio_name != 1 ]; then
                                     mbss_tx_grp="$mbss_tx_grp $tx_grp"
                                fi
                            fi
                      fi
                 fi

             done

         done

         if [ $clear_tx_grp = 1 ]; then
              mbss_tx_grp=""
         fi

         post_qcawificfg80211 "enable" "multi_up" "$mbss_tx_vap" "$mbss_tx_grp"
    fi
    unlock_wifi
}

mlo_usage() {
    echo "Usage: mlo [ap_add|ap_remove]"
}

mlo() {
    case "$2" in
        ap_add) mlo_ap_add $@;;
        ap_remove) mlo_ap_remove $@;;
        *) mlo_usage;;
    esac
}

#mlo_ap_add mldX athX athY .. mldY athXX athYY..
mlo_ap_add() {
    local i=3 #first interface name starts from $3
    local j
    local mld
    local pre_enable=0
    local vif_found
    local vifs_list
    local mbss_tx_vdev_found=0

    if [ -z "$gdevice" ]; then
            gdevice=$DEVICES
    fi

    echo -ne "pre_qcawificfg80211 "disable"\n"
    pre_qcawificfg80211 "disable" "multi_up"

    while [ ${i} -le ${#} ]; do
        eval "mld=\${${i}}";

        check_if_mld=$(echo $mld | grep -c "mld")
        [ $check_if_mld != 1 ] && break;

        j=$((i+1))
        vifs_list=

        # Read virtual interfaces
        while [ ${j} -le ${#} ]; do
            eval "arg_ifname=\${${j}}";
            check_if_mld=$(echo $arg_ifname | grep -c mld)

            [ $check_if_mld = 1 ] && break;
            j=$((j+1));

            # Find the corresponding vif
            vif_found=
            for device in $gdevice; do
                config_get disabled "$device" disabled
                [ "$disabled" = "1" ] && {
                    echo "'$device' is disabled"
                    continue
                }
                scan_qcawificfg80211 $device
                vifs=
                config_get vifs "$device" vifs

                for vap in $vifs; do
                   config_get virt_if_name "$vap" ifname
                   if [ "$virt_if_name" = "$arg_ifname" ]; then
                       vif_found=$vap
                       break;
                   fi
                done;
                [ ! -z "$vif_found" ] && break;
            done;

            [ -z "$vif_found" ] && {
                echo "Ignoring $arg_ifname as its corresponding vif is not found"
                continue
            }

            config_get wlanmode $vif_found mode
            [ "$wlanmode" != "ap" ] && {
                echo "Skipping the non-AP VAP $arg_ifname in MLO link add"
                continue
            }

            config_get vifmld $vif_found mld
            if [ "$vifmld" = "$mld" ]; then
                vifs_list="$vifs_list $vif_found"
            fi
        done;
        i=$((j))

        check_valid_mld=$(echo ${MLD_DEVICES} | grep -c $mld)
        [ "$check_valid_mld" = "0" ] && {
            echo "Ignoring invalid MLD $mld and all the VAPs passed under it"
            continue
        }

        [ -z $vifs_list ] && continue;

        echo "Adding vifs$vifs_list to MLD $mld"

        # Bring down and delete the VAPs
        for vif in $vifs_list; do
            # device will be in enabled state as the vifs_list building logic took care of that
            config_get device $vif device
            config_get ifname $vif ifname

            config_get radio_vifs "$device" vifs
            radio_vifs_count=$(echo "$radio_vifs" | wc -w)
            [ ${radio_vifs_count} = 1 ] && ifname=

            ubus_wifi_cmd "down" "$device"
            echo -ne "disable_qcawificfg80211 "$device" "$ifname"\n"
            disable_qcawificfg80211 "$device" "$ifname"
        done

        # pre_enable, only if not done earlier
        [ $pre_enable = 0 ] && {
            echo -ne "pre_qcawificfg80211 "enable"\n"
            pre_qcawificfg80211 "enable"
            pre_enable=1
        }

        # Create the VAPs and apply the VAP level configs
        for vif in $vifs_list; do
            config_get device $vif device
            config_get ifname $vif ifname

            # mld_reconfig will be read by hostapd script
            config_set "$vif" mld_reconfig 1
            config_get mbss_tx_vdev "$vif" mbss_tx_vdev
            [ -n "$mbss_tx_vdev" ] && mbss_tx_vdev_found=1

            # If this is the only VAP on the radio, pass an empty interface list
            # to enable_qcawificfg80211() so that it takes care of handling the
            # radio level configs as well along with the VAP level configs.
            config_get radio_vifs "$device" vifs
            radio_vifs_count=$(echo "$radio_vifs" | wc -w)
            [ ${radio_vifs_count} = 1 ] && ifname=

            ubus_wifi_cmd "up" "$device"
            echo -ne "enable_qcawificfg80211 "$device" "$ifname"\n"
            enable_qcawificfg80211 "$device" "$ifname"
        done

        # Setup hostapd config and start the VAPs
        for vif in $vifs_list; do
            config_get device $vif device
            config_get ifname $vif ifname

            # If this is the only VAP on the radio, pass an empty interface list
            # to start_qcawificfg80211() so that it takes care of handling the
            # radio level configs as well along with the VAP level configs.
            config_get radio_vifs "$device" vifs
            radio_vifs_count=$(echo "$radio_vifs" | wc -w)
            [ ${radio_vifs_count} = 1 ] && ifname=

            echo -ne "start_qcawificfg80211 "$device" "$ifname"\n"
            start_qcawificfg80211 "$device" "$ifname"
        done
    done

    post_qcawificfg80211 "enable" "multi_up" $mbss_tx_vdev_found
}

#mlo_ap_remove mldX athX <tbtt> athY <tbtt>.. mldY athXX <tbtt> athYY <tbtt>..
mlo_ap_remove() {
    local i=3 #first interface name starts from $3
    local j
    local k
    local mld
    local vif_found
    local tbtt_count
    local vifs_list
    local tbtt_list

    if [ -z "$gdevice" ]; then
            gdevice=$DEVICES
    fi

    while [ ${i} -le ${#} ]; do
        eval "mld=\${${i}}";

        check_if_mld=$(echo $mld | grep -c "mld")
        [ $check_if_mld != 1 ] && break;

        j=$((i+1))
        vifs_list=
        tbtt_list=

        # Read all the VAPs on this MLD
        while [ ${j} -le ${#} ]; do
            eval "arg_ifname=\${${j}}";
            check_if_mld=$(echo $arg_ifname | grep -c mld)

            [ "$check_if_mld" = "1" ] && break;

            j=$((j+1));
            eval "tbtt_count=\${${j}}";
            j=$((j+1));

            # Find the corresponding vif
            vif_found=
            for device in $gdevice; do
                config_get disabled "$device" disabled
                [ "$disabled" = "1" ] && {
                    echo "'$device' is disabled"
                    continue
                }
                scan_qcawificfg80211 $device
                vifs=
                config_get vifs "$device" vifs

                for vap in $vifs; do
                   config_get virt_if_name "$vap" ifname
                   if [ "$virt_if_name" = "$arg_ifname" ]; then
                       vif_found=$vap
                       break;
                   fi
                done;
                [ ! -z "$vif_found" ] && break;
            done;

            [ -z "$vif_found" ] && {
                echo "Ignoring $arg_ifname as its corresponding vif is not found"
                continue
            }

            config_get wlanmode $vif_found mode
            [ "$wlanmode" != "ap" ] && {
                echo "Skipping the non-AP VAP $arg_ifname in MLO link remove"
                continue
            }

            config_get vifmld $vif_found mld
            if [ "$vifmld" = "$mld" ]; then
                vifs_list="$vifs_list $vif_found"
                tbtt_list="$tbtt_list $tbtt_count"
            fi
        done;
        i=$((j))

        # Before proceeding further, validate the MLD
        check_valid_mld=$(echo ${MLD_DEVICES} | grep -c $mld)
        [ "$check_valid_mld" = "0" ] && {
            echo "Ignoring invalid MLD $mld and all the VAPs passed under it"
            continue
        }

        [ -z $vifs_list ] && continue;

        echo "Removing vifs$vifs_list with respective Delete Timer TBTT values$tbtt_list from their MLD $mld"

        k=1
        for vif in $vifs_list; do
            config_get device $vif device
            config_get vifname $vif ifname
            tbtt_count=$(echo $tbtt_list | cut -d " " -f ${k})
            echo "hostapd_cli -i $vifname -p /var/run/hostapd-${device} reconfig-remove $tbtt_count"
            hostapd_cli -i $vifname -p /var/run/hostapd-${device} reconfig-remove $tbtt_count
            k=$((k+1));
        done
    done
}

get_vap_mode() {
	vap_mode="0"
	vap_mode_ret=0
	local pid=""

	[ ! -f /lib/wifi/.first_time_boot ] && vap_mode_ret=1 && touch /tmp/first_boot_done && return
	[ ! -s /etc/config/wireless ] && vap_mode_ret=2 && touch /tmp/first_boot_done && return
	[ -f /lib/modules/qca-whunt-modules ] && vap_mode_ret=3 && return
	[ ! -f /ini/internal/global_i.ini ] && vap_mode_ret=4 && return
	[ -f /tmp/first_boot_done ] && vap_mode_ret=5 && return

	skip_cnss=$(cat /proc/cmdline | sed -rn "s/.* ?"skip_cnss"="\([0-1]+\)" ?(.*)+?/\1/p")
	if [ $skip_cnss == 1 ]; then
		echo "***** Fast boot is disabled due to skip_cnss in bootargs *****" > /dev/kmsg
		touch /tmp/first_boot_done
		return
	fi

	pid=$(ps | grep "[a]cfg_tool" | awk '{print $1}')
	if [ -z "$pid" ]; then
		echo "***** ACFG app not found: Fast boot is disabled *****" > /dev/kmsg
		return
	fi

	vap_mode=`grep "fast_boot_vap_mode" /ini/internal/global_i.ini | grep -m1 -v "^[#]" | awk -F'=' '{print $2}'`
}


event_common_pre_singlewiphy_qcawificfg80211() {
	local action=${1}
	local board_name
	local devices_t=$DEVICES
	local mld_mac_option=

	if [ -z "$gdevice" ]; then
		gdevice=$DEVICES
	fi

	devices_t=$gdevice

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	config_load wireless

	case "${action}" in
		enable)
			mld_netdev=1
			for mld in ${MLD_DEVICES}; do
				local wlanmode="__ap"
				local parent_wifi_iface
				local mld_iface
				if [ $mld_netdev == 0 ]; then
					break;
				fi
				config_get mld_mac $mld mld_macaddr
				config_get role $mld role

				[ -z "$mld_mac" ] || mld_mac_option="mld_addr"

				for device1 in $devices_t; do
					config_get disabled "$device1" disabled
					["$disabled" = "1" ] && {
						echo "'$device1' is disabled"
						continue
					}
					config_get vifs "$device1" vifs

					for vif in $vifs; do
						config_get ifmld "$vif" mld
						if [ "$ifmld" = $mld ]; then
							config_get link_mode "$vif" mode
							if [ "$link_mode" = "sta" ]; then
								wlanmode="managed"
								break
							fi
						fi
					done
					for vif in $vifs; do
						config_get ifmld "$vif" mld
						if [ "$ifmld" = $mld ]; then
							config_get wifi_iface "$vif" device
							phy_name=`cat /sys/class/net/$wifi_iface/mldphy_name`
							if [ "$phy_name" = "mld-phy0" ] || [ "$phy_name" = "mld-phy1" ] ; then
								parent_wifi_iface="$wifi_iface"
								mld_iface="$ifmld"
								break;
							fi
						fi
					done
				done

				local mld_phy_name
				mld_phy_name=`cat /sys/class/net/$parent_wifi_iface/mldphy_name`
				echo "Rmld_phy_name: $mld_phy_name parent_wifi_iface: $parent_wifi_iface" > /dev/console

				if [ "$role" = "Non-AP" ]; then
					iw phy $mld_phy_name interface add $mld_iface type managed $mld_mac_option $mld_mac
					echo "Rmld: $mld_iface:$mld_phy_name role: $role wlanmode: managed" > /dev/console
					ifconfig $mld up
					continue;
				fi
				if [ "$role" = "AP" ]; then
					iw phy $mld_phy_name interface add $mld_iface type $wlanmode $mld_mac_option $mld_mac
					echo "Rmld: $mld_iface:$mld_phy_name role: $role wlanmode: $wlanmode" > /dev/console
					ifconfig $mld up
					continue;
				fi

				iw phy $mld_phy_name interface add $mld_iface type $wlanmode $mld_mac_option $mld_mac
				echo "Rmld: $mld_iface:$mld_phy_name wlanmode: $wlanmode" > /dev/console
				ifconfig $mld up
			done
	esac
}

event_wifi_updown() {
	local vap_mode=""

	get_vap_mode
	[ "$vap_mode" = "0" ] && return

	for driver in ${DRIVERS}; do (
		if eval "type pre_${driver}" 2>/dev/null >/dev/null; then
			eval "event_common_pre_singlewiphy_${driver}" ${1} ${2}
			eval "pre_${driver}" ${1} ${2}
		fi
	); done

	#_wifi_enable_disable $1 $2 $3
	for device in ${2:-$DEVICES}; do (
		config_get disabled "$device" disabled
		[ "$disabled" = "1" ] && {
			echo "'$device' is disabled"
			set disable "$2" "$3"
		}
		config_get iftype "$device" type
		if eval "type ${1}_$iftype" 2>/dev/null >/dev/null; then
			eval "scan_$iftype '$device' '$3'"
			eval "${1}_$iftype '$device' '$3'" || echo "$device($iftype): ${1} failed"
		elif [ ! -f /lib/netifd/wireless/$iftype.sh ]; then
			echo "$device($iftype): Interface type not supported"
		fi
	); done

	config_get disabled "$2" disabled
	[ "$disabled" = "1" ] && {
		echo "'$2' is disabled"
		set disable $2 $3
	}
	for driver in ${DRIVERS}; do (
		if eval "type post_${driver}" 2>/dev/null >/dev/null; then
			if [ "$disabled" = "1" ]; then
				continue
			fi
			eval "post_${driver} ${1} '$2' '$3'"
		fi
	); done

	# wifi reload_legacy
	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_vap_nop ]; then
		rm -rf /tmp/event_vap_nop
		return
	fi

	# wifi up/reload
	[ "$vap_mode" = "1" ] && [ -f /tmp/this_is_event ] && [ ! -f /tmp/event_fast_boot_in_progress ] && return

	for driver in ${DRIVERS}; do (
		if eval "type event_monitor_vaps_${driver}" 2>/dev/null >/dev/null; then
			eval "event_monitor_vaps_${driver} ${2}"
		fi
		if eval "type event_common_post_${driver}" 2>/dev/null >/dev/null; then
			eval "event_common_post_${driver} ${2}"
		fi
	); done
}

event_start_mlo_vaps() {
	local vap_mode=""

	get_vap_mode
	start_mlo_vaps "$1" "" "$2"
}

post_common_qcawificfg80211() {
	local mbss_tx_vdev_config_required=$1
	local board_name skip_ezmesh_daemon_restart
	local icm_enable qwrap_enable lowi_enable

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}


	config_get_bool wpc_enable wpc enable 0
	[ ${wpc_enable} -gt 0 ] && \
			eval "type wpc_setup" >/dev/null 2>&1 && {
		wpc_setup
	}

	config_get_bool lowi_enable lowi enable 0
	[ ${lowi_enable} -gt 0 ] && \
		eval "type lowi_setup" >/dev/null 2>&1 && {
		lowi_setup
	}

	# In reboot case call add_mld_bridge once all radios are up
	add_mld_bridge
	eval "type qwrap_setup" >/dev/null 2>&1 && qwrap_setup && _disable_qcawificfg80211

	# These init scripts are assumed to check whether the feature is
	# actually enabled and do nothing if it is not.
	[ ! -f /etc/init.d/ssid_steering ] || /etc/init.d/ssid_steering start

	config_get_bool skip_ezmesh_daemon_restart qcawifi skip_ezmesh_daemon_restart '0'
	[ ! -f /etc/init.d/miwifi-roam ] || /etc/init.d/miwifi-roam restart
	[ ! -f /usr/sbin/topomon_action.sh ] || /usr/sbin/topomon_action.sh update_mesh_param

	config_get_bool wps_pbc_extender_enhance qcawifi wps_pbc_extender_enhance 0
	[ ${wps_pbc_extender_enhance} -ne 0 ] && {
		rm -f /var/run/wifi-wps-enhc-extn.conf
		setup_wps_enhc
	}
	if [ -f  "/var/run/son.conf" ]; then
		rm /var/run/son.conf
	fi

	config_get wfcfg wireless conffile wireless
	config_load $wfcfg

	if [ -f  "/lib/wifi/iface_mgr.sh" ]; then
		config_foreach son_get_config_qcawificfg80211 wifi-device
	fi
	config_foreach mbss_tx_vdev_config wifi-device 0 "$mbss_tx_vdev_config_required" "$2"

	rm -f /etc/ath/iface_mgr.conf
	rm -f /var/run/iface_mgr.pid
	#iface_mgr_setup
	[ -e /sys/firmware/devicetree/base/AUTO_MOUNT ] && {
		case "$board_name" in
			ap-mp*)
				. /etc/init.d/wifi_fw_mount
				stop_wifi_fw "IPQ5018"
			;;
			*)
			;;
		esac
	}

	config_get qld_max_list qcawifi qld_max_list $qld_max_list
	if [ ! -z $qld_max_list ]; then
		if [ $qld_max_list -ne 0 ]; then
		qld_enablecfg80211 wifi0
		fi
	fi

	unicastflood_configcfg80211

	configure_service_class 1
	configure_sawf_telemetry
	configure_sawf_sla
	configure_sla_detect

	if [ -f "/etc/init.d/qca-nss-ppe-ds" ]; then
		echo "Configure affinity for DS"
		/etc/init.d/qca-nss-ppe-ds start
	fi
	if [ $skip_ezmesh_daemon_restart -eq 0 ]; then
		if [ -e /tmp/bootup_completed ]; then
			[ ! -f /etc/init.d/lbd ] || /etc/init.d/lbd start
			[ ! -f /etc/init.d/hyfi-bridging ] || /etc/init.d/hyfi-bridging start
			[ ! -f /etc/init.d/wsplcd ] || /etc/init.d/wsplcd restart
		fi
	fi

}

event_common_post_qcawificfg80211() {
	local flag=0
	local device_if=""
	local wifi_3_0_installed="0"
	local monitor_installed="0"

	scan_wifi
	gdevice=$DEVICES
	ldevice=$DEVICES

	for device in ${2:-$DEVICES}; do
		config_get disabled "$device" disabled
		[ "$disabled" = "1" ] && {
			continue
		}
		flag=1
	done

	if [ $flag = 0 ]; then
		lock /var/run/qdss_support_lock
		if [ ! -f /tmp/event_qdss_support ]; then
			update_global_daemon_coldboot_qdss_support_variables
			enable_qdss_tracing
			atf_configcfg80211
			touch /tmp/event_qdss_support
		fi
		lock -u /var/run/qdss_support_lock

		rm -rf /tmp/event_*
		rm -rf /tmp/wifi_load_done
		rm -rf /tmp/vap_up_start
		rm -rf /tmp/this_is_event
		touch /tmp/wifi_load_done

		echo "***** Fast boot VAP is completed.. *****" > /dev/kmsg
		return
	fi

	lock /var/run/post_qcawificfg80211_lock
	if [ -f /sys/module/qca_ol/parameters/is_wifi_3_0_installed ]; then
		wifi_3_0_installed="$(cat /sys/module/qca_ol/parameters/is_wifi_3_0_installed)"
	fi
	if [ "$wifi_3_0_installed" = "0" ]; then
		[ -f /tmp/event_radio_done_for_$1 ] && rm -rf /tmp/event_radio_done_for_$1
		lock -u /var/run/post_qcawificfg80211_lock
		return
	fi

	[ -f /tmp/event_radio_done_for_$1 ] && rm -rf /tmp/event_radio_done_for_$1
	radio_count=$(ls /tmp/event_radio_done_for_* | wc -l)

	if [ $radio_count = 0 ]; then
		for device in ${2:-$DEVICES}; do
			config_get disabled "$device" disabled
			[ "$disabled" = "1" ] && {
				continue
			}
			config_get device_if "$device" device_if "cfg80211tool"
			if [ -f /sys/module/qca_ol/parameters/is_monitor_installed ]; then
				monitor_installed="$(cat /sys/module/qca_ol/parameters/is_monitor_installed)"
			fi
			if [ "$monitor_installed" = "1" ]; then
				"$device_if" "$device" enable_ol_stats 1
			fi
			event_mlo_vaps_qcawificfg80211 "$device"
		done
		event_start_mlo_vaps "$ldevice" "$gdevice"
		post_common_qcawificfg80211 1
		update_global_daemon_coldboot_qdss_support_variables
		enable_qdss_tracing
		atf_configcfg80211

		rm -rf /tmp/event_*
		rm -rf /tmp/wifi_load_done
		rm -rf /tmp/vap_up_start
		rm -rf /tmp/this_is_event
		touch /tmp/wifi_load_done
		echo "***** Fast boot VAP is completed... *****" > /dev/kmsg
	fi
	lock -u /var/run/post_qcawificfg80211_lock
}

event_mlo_vaps_qcawificfg80211() {
	local mlo_device=$1
	local mlo_vifs
	local mlo_vif
	local vap_mode=""
	local wifi_3_0_installed="0"

	if [ -f /sys/module/qca_ol/parameters/is_wifi_3_0_installed ]; then
		wifi_3_0_installed="$(cat /sys/module/qca_ol/parameters/is_wifi_3_0_installed)"
	fi

	get_vap_mode

	config_get disabled "$mlo_device" disabled 0
	[ $disabled = 0 ] || return

	config_get mlo_vifs "$mlo_device" vifs

	for mlo_vif in $mlo_vifs; do
		config_get mld "$mlo_vif" mld
		[ -n "$mld" ] && [ -f /tmp/mlo_$mlo_vif ] || continue

		while test "$wifi_3_0_installed" = "0"; do
			sleep 1
			if [ -f /sys/module/qca_ol/parameters/is_wifi_3_0_installed ]; then
				wifi_3_0_installed="$(cat /sys/module/qca_ol/parameters/is_wifi_3_0_installed)"
			fi
			# echo "Still waiting for install wifi_3_0" > /dev/console
		done
		scan_qcawificfg80211 $mlo_device
		enable_qcawificfg80211 $mlo_device "" "" "" "1"
		break
	done
}

event_monitor_vaps_qcawificfg80211() {
	local monitor_device=$1
	local monitor_vifs
	local monitor_vif
	local flag=0
	local vap_mode=""
	local monitor_installed="0"

	if [ -f /sys/module/qca_ol/parameters/is_monitor_installed ]; then
		monitor_installed="$(cat /sys/module/qca_ol/parameters/is_monitor_installed)"
	fi

	get_vap_mode

	scan_wifi

	config_get disabled "$monitor_device" disabled 0
	[ $disabled = 0 ] || return

	config_get monitor_vifs "$monitor_device" vifs

	for monitor_vif in $monitor_vifs; do
		config_get mode "$monitor_vif" mode
		[[ $mode = *"monitor"* ]] && [ -f /tmp/monitor_$monitor_vif ] || continue

		while test "$monitor_installed" = "0"; do
			sleep 1
			if [ -f /sys/module/qca_ol/parameters/is_monitor_installed ]; then
				monitor_installed="$(cat /sys/module/qca_ol/parameters/is_monitor_installed)"
			fi
			# echo "Still waiting for install monitor" > /dev/console
		done
		flag=1
		monitor_scan_qcawificfg80211 $monitor_device
		enable_qcawificfg80211 $monitor_device "" "" "1"
		break
	done

	[ $flag = 0 ] && return

	config_get monitor_vifs "$monitor_device" vifs
	for monitor_vif in $monitor_vifs; do
		config_get mode "$monitor_vif" mode
		[[ $mode = *"monitor"* ]] && [ -f /tmp/monitor_$monitor_vif ] || continue

		lock /var/run/device_$monitor_device
		start_vifs_qcawificfg80211 $monitor_device $monitor_vif
		rm -rf /tmp/monitor_$monitor_vif
		lock -u /var/run/device_$monitor_device
	done
}

start_mlo_vaps() {
	local ldevice="$1"
	local vifs_name="$2"
	local gdevice="$3"
	local mld_arg="$4"
	local fail_vap=0
	local vap_mode=""
	local wifi_3_0_installed="0"
	local monitor_installed="0"
	local tmp_mld=""

	if [ -f /sys/module/qca_ol/parameters/is_wifi_3_0_installed ]; then
		wifi_3_0_installed="$(cat /sys/module/qca_ol/parameters/is_wifi_3_0_installed)"
	fi

	if [ -f /sys/module/qca_ol/parameters/is_monitor_installed ]; then
		monitor_installed="$(cat /sys/module/qca_ol/parameters/is_monitor_installed)"
	fi

	get_vap_mode

	for mld in ${MLD_DEVICES}; do
		local check_mld_unique
		local ssid_check=""
		local enc_check=""
		local key_check=""
		local sae_pass_check=""
		local check_11w=""
		local sae_pwe_check=""
		local owe_group_check=""
		local mld_macaddr=""
		fail_vap=0
		if [ -z $tmp_mld ]; then
			check_mld_unique=1
		fi

		if [ ! -z $mld_arg ]; then
			if [ $mld != $mld_arg ]; then
				continue;
			fi
		fi

		# Append config section adds mld devices as part of any
		# scan calls, to prevent starting vaps of same mld again,
		# check if its unique before using it.
		for mld2 in $tmp_mld; do
			if [ "$mld2" = "$mld" ]; then
				check_mld_unique=0
				break
			else
				check_mld_unique=1
			fi
		done

		[ "$check_mld_unique" = "0" ] && continue
		[ "$check_mld_unique" = "1" ] && tmp_mld="$tmp_mld $mld"

		for device in $gdevice; do
			config_get disabled "$device" disabled
			[ "$disabled" = "1" ] && {
				echo "'$device' is disabled"
				continue
			}
			scan_qcawificfg80211 $device
			config_get vifs "$device" vifs

			if [ "$fail_vap" = 1 ]; then
				break;
			fi

			for vif in $vifs; do
				config_get ifmld "$vif" mld
				if [ "$ifmld" = $mld ]; then
					config_get ifname "$vif" ifname

					if [ -z $ifname ]; then
						continue
					fi
					config_get mld_macaddr "$mld" mld_macaddr
					config_get link_mac "$mld" link_mac
					config_get link_id "$mld" link_id
					config_get link_mode "$vif" mode

					if [ "$link_mode" = "sta" ]; then
						config_get link_ssid "$vif" ssid
						config_get link_enc "$vif" encryption "none"
						link_enc=$(echo $link_enc | awk '{ print tolower($0) }')
						config_get link_key "$vif" key ""
						config_get link_sae_pass "$vif" sae_password ""
						config_get link_11w "$vif" ieee80211w 0
						config_get link_sae_pwe	"$vif" sae_pwe	2
						config_get link_owe_group "$vif" owe_group ""

						if [ -n "$ssid_check" ]; then
							if [ "$ssid_check" != "$link_ssid" ]; then
								echo "MLD Config Mismatch"
								fail_vap=1
								break;
							fi
						else
							ssid_check="$link_ssid"
						fi

						if [ -n "$enc_check" ]; then
							if [ "$enc_check" != "$link_enc" ]; then
								echo "MLD ENC Mismatch"
								fail_vap=1
								break;
							fi
						else
							enc_check="$link_enc"
						fi

						if [ -n "$key_check" ]; then
							if [ "$key_check" != "$link_key" ]; then
								echo "MLD Key Mismatch"
								fail_vap=1
								break;
							fi
						else
							key_check="$link_key"
						fi

						if [ -n "$sae_pass_check" ]; then
							if [ "$sae_pass_check" != "$link_sae_pass" ]; then
								echo "MLD SAE Password Mismatch"
								fail_vap=1
								break;
							fi
						else
							sae_pass_check="$link_sae_pass"
						fi

						if [ -n "$check_11w" ]; then
							if [ "$check_11w" != "$link_11w" ]; then
								echo "MLD PMF Mismatch"
								fail_vap=1
								break;
							fi
						else
							check_11w="$link_11w"
						fi

						if [ -n "$sae_pwe_check" ]; then
							if [ "$sae_pwe_check" != "$link_sae_pwe" ]; then
								echo "MLD SAE-PWE Mismatch"
								fail_vap=1
								break;
							fi
						else
							sae_pwe_check="$link_sae_pwe"
						fi

						if [ -n "$owe_group_check" ]; then
							if [ "$owe_group_check" != "$link_owe_group" ]; then
								echo "OWE Group Mismatch"
								fail_vap=1
								break;
							fi
						else
							owe_group_check="$link_owe_group"
						fi

					fi

					if [ -n "$link_mac" ]; then
						new_mac=$(cat /sys/class/net/$ifname/address)
						mac_found=$(echo $link_mac | grep -c "$new_mac")
						if [ $mac_found = 0 ];then
							# Add 6 GHz link at the end of list
							vif_band=$(cfg80211tool $device g_oper_reg_info | grep -i band | awk -F ',' '{print $3}' | awk -F '=' '{print $2}')
							if [ "$vif_band" == "6GHz" ]; then
								link_mac="$link_mac $new_mac"
							else
								link_mac="$new_mac $link_mac"
							fi
						fi
					else
						link_mac="$(cat /sys/class/net/$ifname/address)"
					fi
					if [ -n "$link_id" ]; then
						new_link=${device:4:1}
						link_found=$(echo $link_id | grep -c "$new_link")
						if [ $link_found = 0 ];then
							# Add 6 GHz link at the end of list
							vif_band=$(cfg80211tool $device g_oper_reg_info | grep -i band | awk -F ',' '{print $3}' | awk -F '=' '{print $2}')
							if [ "$vif_band" == "6GHz" ]; then
								link_id="$link_id $new_link"
							else
								link_id="$new_link $link_id"
							fi
						fi
					else
						link_id="${device:4:1}"
					fi
					if [ -z "$mld_macaddr" ]; then
						mld_macaddress="$(cat /sys/class/net/$mld/address)"
						tmp_mld=$(echo $mld_macaddress | sed 's/://g' | sed 's/0//g' )
						if [ -n "$tmp_mld" ]; then
							config_set "$mld" mld_macaddr "$mld_macaddress"
						fi
					fi
					config_set "$mld" link_mac "$link_mac"
					config_set "$mld" link_id "$link_id"
				fi
			done
		done
		if [ "$fail_vap" = 1 ]; then
			echo "STA Config Mismatch SKIP $mld Bring-up"
			continue;
		fi
		for device in $ldevice; do
			config_get disabled "$device" disabled
			[ "$disabled" = "1" ] && {
				echo "'$device' is disabled"
				continue
			}

			scan_qcawificfg80211 $device
			config_get vifs "$device" vifs

			for vif in $vifs; do

				config_get ifname "$vif" ifname
				if [ -z $ifname ]; then
					continue
				fi

				# needs to remove monitor check in mld case
				if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
					config_get mode "$vif" mode
					[[ $mode = *"monitor"* ]] && continue
				fi
				config_get ifmld "$vif" mld
				if [ "$ifmld" = $mld ]; then
						if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
							while test "$monitor_installed" = "0"; do
								sleep 1
								if [ -f /sys/module/qca_ol/parameters/is_monitor_installed ]; then
									monitor_installed="$(cat /sys/module/qca_ol/parameters/is_monitor_installed)"
								fi
								# echo "MLO: Still waiting for install monitor" > /dev/console
							done
							if [ "$monitor_installed" = "1" ] && [ "$wifi_3_0_installed" = "1" ]; then
								start_vifs_qcawificfg80211 "$device" "$vif" "$vifs_name"
							fi
						else
							start_vifs_qcawificfg80211 "$device" "$vif" "$vifs_name"
						fi
				fi
			done
		done
	done
}

start_qcawificfg80211() {
	local ldevice="$1"
	local vifs_name="$2"
	local mld="$3"
	local vap_mode=""

	get_vap_mode
	if [ -z "$gdevice" ]; then
		gdevice=$DEVICES
	fi

	if [ -z "$ldevice" ]; then
		ldevice=$DEVICES
	fi

	for device in $ldevice; do (
		config_get disabled "$device" disabled
		[ "$disabled" = "1" ] && {
			echo "'$device' is disabled"
			continue
		}
		scan_qcawificfg80211 $device
		config_get vifs "$device" vifs

		for vif in $vifs; do
			if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
				config_get mode "$vif" mode
				[[ $mode = *"monitor"* ]] && [ -f /tmp/monitor_$vif ] && continue
			fi
			config_get ifmld "$vif" mld
			if [ -z $ifmld ]; then
					start_vifs_qcawificfg80211 "$device" "$vif" "$vifs_name"
			fi
		done
	); done

	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		return
	fi

	if [ -z $mld ]; then
		start_mlo_vaps "$ldevice" "$vifs_name" "$gdevice"
	else
		start_mlo_vaps "$ldevice" "$vifs_name" "$gdevice" "$mld"
	fi
}

enable_qcawificfg80211() {
	[ "$2" = "wifi_reload" ] && set "$1"
	[ "$2" = "wifi_load" ] && set "$1"

	local device="$1"
	local count=0
	local vifs_name="$2"
	local recover=0
	local wifi_hwm_script
	local board_name ini_path
	local monitor_installed="0"
	local vap_mode=""

	get_vap_mode

	# wifi reload_legacy
	[ "$vap_mode" = "1" ] && [ -f /tmp/event_vap_nop ] && return

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	if [ "$1" = "1" ]; then
		device="$2"
		vifs_name="$3"
		recover="$1"
	fi

        #Invoked from wifi_hw_mode script
	if [ "$3" = "1" ]; then
		vifs_name=
		wifi_hwm_script="$3"
	fi

	[ "$vap_mode" = "1" ] && [ -f /tmp/this_is_event ] && [ ! -f /tmp/event_fast_boot_in_progress ] && return

	ini_path=$(get_config_file_path "ini")

	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		if [ -d /sys/module/umac ] && [ -f /tmp/.wifi-config-done ]; then
			[ -d /sys/module/ecm_wifi_plugin ] || insmod_cmd ecm-wifi-plugin
		fi
	fi

	if [ ! -z "$vifs_name" ]; then

		# check the ini file
		if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
			lock /var/run/device_$1
		else
			if [ "$recover" != "1" ]; then
				lock /var/run/wifilock
			fi
		fi

		for vif in $vifs_name
		do
			enable_vifs_qcawificfg80211 $recover $device $vif
		done

		# check the ini file
		if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
			lock -u /var/run/device_$1
		else
			if [ "$recover" != "1" ]; then
				lock -u /var/run/wifilock
			fi
		fi
		return 0
	fi

	# Ap in dynamic mode means 3 radios will always be present
	# If in DBS mode then wifi2 should not be using cfg80211tool functions
	dynamic_hw_mode=`grep "dynamic_hw_mode" $ini_path/internal/global_i.ini | grep -m1 -v "^[#]" | awk -F'=' '{print $2}'`
	if [ "$dynamic_hw_mode" = "1" ]; then
		if [ $device = "wifi2" ]; then
			hw_mode_id=`retrieve_current_hw_mode`
			if [ $hw_mode_id -eq 1 ]; then
				return 0
			fi
		fi
	fi

	echo "$DRIVERS: enable radio $1" >/dev/console
	local num_radio_instamode=0
	local hk_ol_num=0
	local edge_ch_dep_applicable
	local hwcaps

	# check the ini file
	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		if [ ! -d /sys/module/wifi_3_0 ]; then
			load_qcawificfg80211 $recover
			rm -rf /tmp/event_post_load_qcawificfg80211
			post_load_qcawificfg80211 $1
		fi
		if [ -d /sys/module/umac ] && [ -f /tmp/.wifi-config-done ]; then
			[ -d /sys/module/ecm_wifi_plugin ] || insmod_cmd ecm-wifi-plugin
		fi
	else
		load_qcawificfg80211 $recover
	fi

	find_qcawifi_phy "$device" || return 1

	if [ ! -f /lib/wifi/wifi_nss_override ]; then
		if [ -f /lib/wifi/wifi_nss_olcfg ] && [ $(cat /lib/wifi/wifi_nss_olcfg) != 0 ]; then
			touch /lib/wifi/wifi_nss_override
			echo_cmd 0 /lib/wifi/wifi_nss_override
		fi
	fi

	if [ -f /lib/wifi/wifi_nss_override ]; then
		cd /sys/class/net
		# check the ini file
		if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
			config_get_bool disabled "$1" disabled 0
			if [ $disabled = 0 ]; then
				config_get vifs "$1" vifs

				for vif in $vifs; do
					config_get mode "$vif" mode
					if [ $mode = "sta" ]; then
						num_radio_instamode=$(($num_radio_instamode + 1))
						break
					fi
				done
			fi
		else
			for all_device in $(ls -d wifi* 2>&-); do
				config_get_bool disabled "$all_device" disabled 0
				[ $disabled = 0 ] || continue
				config_get vifs "$all_device" vifs

				for vif in $vifs; do
					config_get mode "$vif" mode
					if [ $mode = "sta" ]; then
						num_radio_instamode=$(($num_radio_instamode + 1))
						break
					fi
				done
				if [ $num_radio_instamode = "0" ]; then
					break
				fi
			done
		fi

		# HK variants supports 3 radio sta configuration with fast lane enabled.
		# NSS WiFi Offload needs to be enabled for HK when 3 sta configured.
		nss_override="$(cat /lib/wifi/wifi_nss_override)"
		if [ [ $num_radio_instamode != "3" ] && [ $nss_override != "0" ] ]; then
			echo_cmd 0 /lib/wifi/wifi_nss_override
			unload_qcawificfg80211 $recover
			device=$1
			# check the ini file
			if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
				if [ ! -d /sys/module/wifi_3_0 ]; then
					load_qcawificfg80211 $recover
					rm -rf /tmp/event_post_load_qcawificfg80211
					post_load_qcawificfg80211 $1
				fi
			else
				load_qcawificfg80211 $recover
			fi
		fi
	fi

	# check the ini file
	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		lock /var/run/device_$1
	else
		if [ "$recover" != "1" ]; then
			lock /var/run/wifilock
		fi
	fi

	config_get phy "$device" phy
	config_get device_if "$device" device_if "cfg80211tool"

	config_get enable_ema "$device" enable_ema
	[ -n "$enable_ema" ] && "$device_if" "$phy" enable_ema "$enable_ema"

	config_get interCACChan "$device" interCACChan
	[ -n "$interCACChan" ] && "$device_if" "$phy" interCACChan "$interCACChan"

	config_get country "$device" country
	if [ -z "$country" ]; then
		if ! set_default_country $device; then
			# check the ini file
			if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
				lock -u /var/run/device_$1
			else
				if [ "$recover" != "1" ]; then
					lock -u /var/run/wifilock
				fi
			fi
			return 1
		fi
	else
		# If the country parameter is a number (either hex or decimal), we
		# assume it's a regulatory domain - i.e. we use "$device_if" setCountryID.
		# Else we assume it's a country code - i.e. we use "$device_if" setCountry.
		case "$country" in
			[0-9]*)
				"$device_if" "$phy" setCountryID "$country"
			;;
			*)
				[ -n "$country" ] && "$device_if" "$phy" setCountry "$country"
			;;
		esac
	fi

	config_get chan_coex_disable "$device" chan_coex_disable
	[ -n "$chan_coex_disable" ] && "$device_if" "$phy" chan_coex_disable "$chan_coex_disable"

	config_get bsta_fixed_idmask "$device" bsta_fixed_idmask 255
	[ -n "$bsta_fixed_idmask" ] && "$device_if" "$phy" bsta_fixed_idmask "$bsta_fixed_idmask"


	config_get channel "$device" channel 0
	config_get vifs "$device" vifs
	config_get txpower "$device" txpower
	config_get htmode "$device" htmode auto
	config_get band "$device" band 0
	config_get edge_channel_deprioritize "$device" edge_channel_deprioritize 1
	[ auto = "$channel" ] && channel=0
	[ AUTO = "$channel" ] && channel=0

	# MIWIFI
	dev="/sys/class/net/${phy}"
	hwcaps=$(cat ${dev}/hwcaps)
	case "${hwcaps}" in
		*11an) bdmode=5G;;
		*11an/ac) bdmode=5G;;
		*11an/ac/ax) bdmode=5G;;
		*11an/ac/ax/be) bdmode=5G;;
		*11abgn/ac) bdmode=5G;;
		*11abgn/ac/ax) bdmode=5G;;
		*11abgn) bdmode=24G;;
		*11bgn) bdmode=24G;;
		*11bgn/ax) bdmode=24G;;
		*11bgn/ax/be) bdmode=24G;;
	esac
	config_get bw "$device" bw
	[ -z "$bw" ] && bw="0"
	force11NGHT40=0
	if [ "$bdmode" = "24G" ]; then
		case "$bw" in
			20) htmode=HT20;;
			40|80)
				if [ "$channel" = 0 ]; then
					htmode=HT40
				elif [ "$channel" -lt 7 ]; then
					htmode=HT40+
				else
					htmode=HT40-
				fi
				force11NGHT40=1
			;;
			*)
				if [ "$channel" = 0 ]; then
					htmode=HT40
				elif [ "$channel" -lt 7 ]; then
					htmode=HT40+
				else
					htmode=HT40-
			fi
			;;
		esac
	else
		case "$bw" in
			20) htmode=HT20;;
			40)
				if [ "$channel" = 0 ]; then
					htmode=HT40
				fi
				if [ "$channel" = 36 \
				-o "$channel" = 44 \
				-o "$channel" = 52 \
				-o "$channel" = 60 \
				-o "$channel" = 100 \
				-o "$channel" = 108 \
				-o "$channel" = 116 \
				-o "$channel" = 124 \
				-o "$channel" = 132 \
				-o "$channel" = 149 \
				-o "$channel" = 157 ]; then
					htmode=HT40+
				fi
				if [ "$channel" = 40 \
				-o "$channel" = 48 \
				-o "$channel" = 56 \
				-o "$channel" = 64 \
				-o "$channel" = 104 \
				-o "$channel" = 112 \
				-o "$channel" = 120 \
				-o "$channel" = 128 \
				-o "$channel" = 136 \
				-o "$channel" = 153 \
				-o "$channel" = 161 ]; then
					htmode=HT40-
				fi
			;;
			80) htmode=HT80;;
			160) 
				htmode=HT160
			;;
			*) 
				if [ "$channel" = 149 \
				-o "$channel" = 153 \
				-o "$channel" = 157 \
				-o "$channel" = 161 ]; then
					htmode=HT80
				else
					htmode=HT160
		fi
			;;
		esac
		fi

	if [ "$channel" = 165 ]; then
		htmode=HT20
	fi

	# # WAR to not use chan 36 as primary channel, when using higher BW.
	# if { [ $band -eq 0 ] || [ $band -eq 2 ]; } && [ $channel -eq 36 ]; then
	# 	if [ -f /sys/class/net/${device}/edge_ch_dep_applicable ]; then
	# 		edge_ch_dep_applicable=$(cat /sys/class/net/${device}/edge_ch_dep_applicable)
	# 		if [ $edge_ch_dep_applicable == "1" -a $edge_channel_deprioritize -eq 1 ]; then
	# 			[ HT20 != "$htmode" ] && channel=40 && echo " Primary channel is changed to 40"
	# 			[ HT40+ = "$htmode" ] && htmode=HT40- && echo " Mode changed to HT40MINUS with channel 40"
	# 		fi
	# 	fi
	# fi

	config_get_bool antdiv "$device" diversity
	config_get antrx "$device" rxantenna
	config_get anttx "$device" txantenna
	config_get_bool softled "$device" softled
	config_get antenna "$device" antenna
	config_get distance "$device" distance

	[ -n "$antdiv" ] && echo "antdiv option not supported on this driver"
	[ -n "$antrx" ] && echo "antrx option not supported on this driver"
	[ -n "$anttx" ] && echo "anttx option not supported on this driver"
	[ -n "$softled" ] && echo "softled option not supported on this driver"
	[ -n "$antenna" ] && echo "antenna option not supported on this driver"
	[ -n "$distance" ] && echo "distance option not supported on this driver"

	# Advanced QCA wifi per-radio parameters configuration
	config_get txchainmask "$device" txchainmask
	[ -n "$txchainmask" ] && "$device_if" "$phy" txchainmask "$txchainmask"

	config_get rxchainmask "$device" rxchainmask
	[ -n "$rxchainmask" ] && "$device_if" "$phy" rxchainmask "$rxchainmask"

	config_get radio_qdf_cv_lvl "$device" radio_qdf_cv_lvl
	[ -n "$radio_qdf_cv_lvl" ] && "$device_if" "$phy" radio_qdf_cv_lvl "$radio_qdf_cv_lvl"

        config_get regdomain "$device" regdomain
        [ -n "$regdomain" ] && "$device_if" "$phy" setRegdomain "$regdomain"

	config_get postNOLfreq "$device" postNOLfreq
	[ -n "$postNOLfreq" ] && "$device_if" "$phy" setpostNOLfreq "$postNOLfreq"

	config_get postNOLmode "$device" postNOLmode
	[ -n "$postNOLmode" ] && "$device_if" "$phy" setpostNOLmode "$postNOLmode"

	config_get postNOLcfreq2 "$device" postNOLcfreq2
	[ -n "$postNOLcfreq2" ] && "$device_if" "$phy" setpostNOLcfreq2 "$postNOLcfreq2"

	config_get preCACEn "$device" preCACEn
	[ -n "$preCACEn" ] && "$device_if" "$phy" preCACEn "$preCACEn"

	config_get upload_pktlog "$device" upload_pktlog
	[ -n "$upload_pktlog" ] && "$device_if" "$phy" upload_pktlog "$upload_pktlog"

	config_get rpt_max_phy "$device" rpt_max_phy 1
	[ -n "$rpt_max_phy" ] && "$device_if" "$phy" rpt_max_phy "$rpt_max_phy"

	config_get pCACTimeout "$device" pCACTimeout
	[ -n "$pCACTimeout" ] && "$device_if" "$phy" pCACTimeout "$pCACTimeout"

	config_get rCACEn "$device" rCACEn
	[ -n "$rCACEn" ] && "$device_if" "$phy" rCACEn "$rCACEn"

	config_get rCAC_freq "$device" rCAC_freq
	[ -n "$rCAC_freq" ] && "$device_if" "$phy" rCAC_freq "$rCAC_freq"

	config_get mark_subchan  "$device" mark_subchan
	[ -n "$mark_subchan" ] && "$device_if" "$phy" mark_subchan "$mark_subchan"

	config_get bw_expand  "$device" bw_expand
	[ -n "$bw_expand" ] && "$device_if" "$phy" bw_expand "$bw_expand"

	config_get dfs_punctureEn  "$device" dfs_punctureEn
	[ -n "$dfs_punctureEn" ] && "$device_if" "$phy" dfs_punctureEn "$dfs_punctureEn"

	config_get he_bsscolor "$device" he_bsscolor
	[ -n "$he_bsscolor" ] && "$device_if" "$phy" he_bsscolor ${he_bsscolor}

	config_get arp_protocol_tag "$device" rx_protocol_arp_type_tag
        [ -n "$arp_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 0 $arp_protocol_tag

        config_get dhcpv4_protocol_tag "$device" rx_protocol_dhcpv4_type_tag
        [ -n "$dhcpv4_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 4 $dhcpv4_protocol_tag

        config_get dhcpv6_protocol_tag "$device" rx_protocol_dhcpv6_type_tag
        [ -n "$dhcpv6_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 5 $dhcpv6_protocol_tag

        config_get dns_tcpv4_protocol_tag "$device" rx_protocol_dns_tcpv4_type_tag
        [ -n "$dns_tcpv4_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 6 $dns_tcpv4_protocol_tag

        config_get dns_tcpv6_protocol_tag "$device" rx_protocol_dns_tcpv6_type_tag
        [ -n "$dns_tcpv6_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 7 $dns_tcpv6_protocol_tag

        config_get dns_udpv4_protocol_tag "$device" rx_protocol_dns_udpv4_type_tag
        [ -n "$dns_udpv4_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 8 $dns_udpv4_protocol_tag

        config_get dns_udpv6_protocol_tag "$device" rx_protocol_dns_udpv6_type_tag
        [ -n "$dns_tcpv6_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 9 $dns_udpv6_protocol_tag

        config_get icmpv4_protocol_tag "$device" rx_protocol_icmpv4_type_tag
        [ -n "$icmpv4_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 10 $icmpv4_protocol_tag

        config_get icmpv6_protocol_tag "$device" rx_protocol_icmpv6_type_tag
        [ -n "$icmpv6_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 11 $icmpv6_protocol_tag

        config_get tcpv4_protocol_tag "$device" rx_protocol_tcpv4_type_tag
        [ -n "$tcpv4_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 12 $tcpv4_protocol_tag

        config_get tcpv6_protocol_tag "$device" rx_protocol_tcpv6_type_tag
        [ -n "$tcpv6_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 13 $tcpv6_protocol_tag

        config_get udpv4_protocol_tag "$device" rx_protocol_udpv4_type_tag
        [ -n "$udpv4_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 14 $udpv4_protocol_tag

        config_get udpv6_protocol_tag "$device" rx_protocol_udpv6_type_tag
        [ -n "$udpv6_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 15 $udpv6_protocol_tag

        config_get ipv4_protocol_tag "$device" rx_protocol_ipv4_type_tag
        [ -n "$ipv4_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 16 $ipv4_protocol_tag

        config_get ipv6_protocol_tag "$device" rx_protocol_ipv6_type_tag
        [ -n "$ipv6_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 17 $ipv6_protocol_tag

        config_get eap_protocol_tag "$device" rx_protocol_eap_type_tag
        [ -n "$eap_protocol_tag" ] && "$device_if" "$phy" set_rxProtocolTag 0 18 $eap_protocol_tag

	config_get mbss_auto "$device" mbss_auto
	[ -n "$mbss_auto" ] && "$device_if" "$phy" mbss_auto "$mbss_auto"

	config_get AMPDU "$device" AMPDU
	[ -n "$AMPDU" ] && "$device_if" "$phy" AMPDU "$AMPDU"

	config_get ampdudensity "$device" ampdudensity
	[ -n "$ampdudensity" ] && "$device_if" "$phy" ampdudensity "$ampdudensity"

	config_get_bool AMSDU "$device" AMSDU
	[ -n "$AMSDU" ] && "$device_if" "$phy" AMSDU "$AMSDU"

	config_get AMPDULim "$device" AMPDULim
	[ -n "$AMPDULim" ] && "$device_if" "$phy" AMPDULim "$AMPDULim"

	config_get AMPDUFrames "$device" AMPDUFrames
	[ -n "$AMPDUFrames" ] && "$device_if" "$phy" AMPDUFrames "$AMPDUFrames"

	config_get AMPDURxBsize "$device" AMPDURxBsize
	[ -n "$AMPDURxBsize" ] && "$device_if" "$phy" AMPDURxBsize "$AMPDURxBsize"

	config_get_bool bcnburst "$device" bcnburst 1
	[ -n "$bcnburst" ] && "$device_if" "$phy" set_bcnburst "$bcnburst"

	config_get set_smart_antenna "$device" set_smart_antenna
	[ -n "$set_smart_antenna" ] && "$device_if" "$phy" setSmartAntenna "$set_smart_antenna"

	config_get current_ant "$device" current_ant
	[ -n  "$current_ant" ] && "$device_if" "$phy" current_ant "$current_ant"

	config_get default_ant "$device" default_ant
	[ -n "$default_ant" ] && "$device_if" "$phy" default_ant "$default_ant"

	config_get ant_retrain "$device" ant_retrain
	[ -n "$ant_retrain" ] && "$device_if" "$phy" ant_retrain "$ant_retrain"

	config_get retrain_interval "$device" retrain_interval
	[ -n "$retrain_interval" ] && "$device_if" "$phy" retrain_interval "$retrain_interval"

	config_get retrain_drop "$device" retrain_drop
	[ -n "$retrain_drop" ] && "$device_if" "$phy" retrain_drop "$retrain_drop"

	config_get ant_train "$device" ant_train
	[ -n "$ant_train" ] && "$device_if" "$phy" ant_train "$ant_train"

	config_get ant_trainmode "$device" ant_trainmode
	[ -n "$ant_trainmode" ] && "$device_if" "$phy" ant_trainmode "$ant_trainmode"

	config_get ant_traintype "$device" ant_traintype
	[ -n "$ant_traintype" ] && "$device_if" "$phy" ant_traintype "$ant_traintype"

	config_get ant_pktlen "$device" ant_pktlen
	[ -n "$ant_pktlen" ] && "$device_if" "$phy" ant_pktlen "$ant_pktlen"

	config_get ant_numpkts "$device" ant_numpkts
	[ -n "$ant_numpkts" ] && "$device_if" "$phy" ant_numpkts "$ant_numpkts"

	config_get ant_numitr "$device" ant_numitr
	[ -n "$ant_numitr" ] && "$device_if" "$phy" ant_numitr "$ant_numitr"

	config_get ant_train_thres "$device" ant_train_thres
	[ -n "$ant_train_thres" ] && "$device_if" "$phy" train_threshold "$ant_train_thres"

	config_get ant_train_min_thres "$device" ant_train_min_thres
	[ -n "$ant_train_min_thres" ] && "$device_if" "$phy" train_threshold "$ant_train_min_thres"

	config_get ant_traffic_timer "$device" ant_traffic_timer
	[ -n "$ant_traffic_timer" ] && "$device_if" "$phy" traffic_timer "$ant_traffic_timer"

	config_get dcs_enable "$device" dcs_enable
	[ -n "$dcs_enable" ] && "$device_if" "$phy" dcs_enable "$dcs_enable"

	config_get dcs_coch_int "$device" dcs_coch_int
	[ -n "$dcs_coch_int" ] && "$device_if" "$phy" set_dcs_coch_int "$dcs_coch_int"

	config_get dcs_errth "$device" dcs_errth
	[ -n "$dcs_errth" ] && "$device_if" "$phy" set_dcs_errth "$dcs_errth"

	config_get dcs_phyerrth "$device" dcs_phyerrth
	[ -n "$dcs_phyerrth" ] && "$device_if" "$phy" set_dcs_phyerrth "$dcs_phyerrth"

	config_get dcs_usermaxc "$device" dcs_usermaxc
	[ -n "$dcs_usermaxc" ] && "$device_if" "$phy" set_dcs_usermaxc "$dcs_usermaxc"

	config_get dcs_debug "$device" dcs_debug
	[ -n "$dcs_debug" ] && "$device_if" "$phy" set_dcs_debug "$dcs_debug"

	config_get dcs_afc_random_chan_en "$device" dcs_afc_random_chan_en
	[ -n "$dcs_afc_random_chan_en" ] && "$device_if" "$phy" dcs_afc_random_chan_en "$dcs_afc_random_chan_en"

	config_get dcs_afc_chan_sel_config "$device" dcs_afc_chan_sel_config
	[ -n "$dcs_afc_chan_sel_config" ] && "$device_if" "$phy" dcs_afc_chan_sel_config "$dcs_afc_chan_sel_config"

	config_get dcs_bw_reduction_ctrl "$device" dcs_bw_reduction_ctrl
	[ -n "$dcs_bw_reduction_ctrl" ] && "$device_if" "$phy" set_dcs_bw_reduction_ctrl "$dcs_bw_reduction_ctrl"

	config_get_bool ce_debug_stats "$device" ce_debug_stats
	if [ -n "$ce_debug_stats" ]; then
		"$device_if" "$phy" ce_debug_stats "$ce_debug_stats"
	else
	case "$board_name" in
		ap-hk*|ap-ac*|ap-cp*|ap-oak*|ap-mp*|ap-al*|ap-mi*)
		"$device_if" "$phy" ce_debug_stats 1
		;;
		esac
	fi

	config_get set_ch_144 "$device" set_ch_144
	[ -n "$set_ch_144" ] && "$device_if" "$phy" setCH144 "$set_ch_144"

	config_get eppovrd_ch_144 "$device" eppovrd_ch_144
	[ -n "$eppovrd_ch_144" ] && "$device_if" "$phy" setCH144EppOvrd "$eppovrd_ch_144"

	config_get_bool ani_enable "$device" ani_enable
	[ -n "$ani_enable" ] && "$device_if" "$phy" ani_enable "$ani_enable"

	config_get_bool acs_bkscanen "$device" acs_bkscanen
	[ -n "$acs_bkscanen" ] && "$device_if" "$phy" acs_bkscanen "$acs_bkscanen"

	config_get acs_scanintvl "$device" acs_scanintvl
	[ -n "$acs_scanintvl" ] && "$device_if" "$phy" acs_scanintvl "$acs_scanintvl"

	config_get acs_rssivar "$device" acs_rssivar
	[ -n "$acs_rssivar" ] && "$device_if" "$phy" acs_rssivar "$acs_rssivar"

	config_get acs_chloadvar "$device" acs_chloadvar
	[ -n "$acs_chloadvar" ] && "$device_if" "$phy" acs_chloadvar "$acs_chloadvar"

	config_get acs_lmtobss "$device" acs_lmtobss
	[ -n "$acs_lmtobss" ] && "$device_if" "$phy" acs_lmtobss "$acs_lmtobss"

	config_get acs_ctrlflags "$device" acs_ctrlflags
	[ -n "$acs_ctrlflags" ] && "$device_if" "$phy" acs_ctrlflags "$acs_ctrlflags"

	config_get acs_dbgtrace "$device" acs_dbgtrace
	[ -n "$acs_dbgtrace" ] && "$device_if" "$phy" acs_dbgtrace "$acs_dbgtrace"

	config_get puncture_strict "$device" puncture_strict
	[ -n "$puncture_strict" ] && "$device_if" "$phy" puncture_strict "$puncture_strict"

	config_get acs_6g_only_psc "$device" acs_6g_only_psc
	[ -n "$acs_6g_only_psc" ] && "$device_if" "$phy" acs_6g_only_psc "$acs_6g_only_psc"

	config_get_bool acs_pcaconly "$device" acs_pcaconly
	[ -n "$acs_pcaconly" ] && "$device_if" "$phy" acs_pcaconly "$acs_pcaconly"

	config_get_bool acs_chan_grade_algo "$device" acs_chan_grade_algo
	[ -n "$acs_chan_grade_algo" ] && "$device_if" "$phy" acs_chan_grade_algo "$acs_chan_grade_algo"

	config_get set_acs_chan_eff_var "$device" set_acs_chan_eff_var
	[ -n "$set_acs_chan_eff_var" ] && "$device_if" "$phy" set_acs_chan_eff_var "$set_acs_chan_eff_var"

	config_get set_acs_near_range_weightage "$device" set_acs_near_range_weightage
	[ -n "$set_acs_near_range_weightage" ] && "$device_if" "$phy" set_acs_near_range_weightage "$set_acs_near_range_weightage"

	config_get set_acs_mid_range_weightage "$device" set_acs_mid_range_weightage
	[ -n "$set_acs_mid_range_weightage" ] && "$device_if" "$phy" set_acs_mid_range_weightage "$set_acs_mid_range_weightage"

	config_get set_acs_far_range_weightage "$device" set_acs_far_range_weightage
	[ -n "$set_acs_far_range_weightage" ] && "$device_if" "$phy" set_acs_far_range_weightage "$set_acs_far_range_weightage"

	config_get acs_6g_non_prio_penalty "$device" acs_6g_non_prio_penalty
	[ -n "$acs_6g_non_prio_penalty" ] && "$device_if" "$phy" acs_6g_non_prio_chan_penalty "$acs_6g_non_prio_penalty"

	config_get_bool dscp_ovride "$device" dscp_ovride
	[ -n "$dscp_ovride" ] && "$device_if" "$phy" set_dscp_ovride "$dscp_ovride"

	config_get reset_dscp_map "$device" reset_dscp_map
	[ -n "$reset_dscp_map" ] && "$device_if" "$phy" reset_dscp_map "$reset_dscp_map"

	config_get dscp_tid_map "$device" dscp_tid_map
	[ -n "$dscp_tid_map" ] && "$device_if" "$phy" set_dscp_tid_map $dscp_tid_map

        #Default enable IGMP overide & TID=6
	"$device_if" "$phy" sIgmpDscpOvrid 1
	"$device_if" "$phy" sIgmpDscpTidMap 6

	config_get_bool igmp_dscp_ovride "$device" igmp_dscp_ovride
	[ -n "$igmp_dscp_ovride" ] && "$device_if" "$phy" sIgmpDscpOvrid "$igmp_dscp_ovride"

	config_get igmp_dscp_tid_map "$device" igmp_dscp_tid_map
	[ -n "$igmp_dscp_tid_map" ] && "$device_if" "$phy" sIgmpDscpTidMap "$igmp_dscp_tid_map"

	config_get_bool hmmc_dscp_ovride "$device" hmmc_dscp_ovride
	[ -n "$hmmc_dscp_ovride" ] && "$device_if" "$phy" sHmmcDscpOvrid "$hmmc_dscp_ovride"

	config_get hmmc_dscp_tid_map "$device" hmmc_dscp_tid_map
	[ -n "$hmmc_dscp_tid_map" ] && "$device_if" "$phy" sHmmcDscpTidMap "$hmmc_dscp_tid_map"

	config_get_bool blk_report_fld "$device" blk_report_fld
	[ -n "$blk_report_fld" ] && "$device_if" "$phy" setBlkReportFld "$blk_report_fld"

	config_get_bool drop_sta_query "$device" drop_sta_query
	[ -n "$drop_sta_query" ] && "$device_if" "$phy" setDropSTAQuery "$drop_sta_query"

	config_get_bool burst "$device" burst
	[ -n "$burst" ] && "$device_if" "$phy" burst "$burst"

	config_get burst_dur "$device" burst_dur
	[ -n "$burst_dur" ] && "$device_if" "$phy" burst_dur "$burst_dur"

	config_get TXPowLim2G "$device" TXPowLim2G
	[ -n "$TXPowLim2G" ] && "$device_if" "$phy" TXPowLim2G "$TXPowLim2G"

	config_get TXPowLim5G "$device" TXPowLim5G
	[ -n "$TXPowLim5G" ] && "$device_if" "$phy" TXPowLim5G "$TXPowLim5G"

	config_get cck_tx_enable "$device" cck_tx_enable
	[ -n "$cck_tx_enable" ] && "$device_if" "$phy" cck_tx_enable "$cck_tx_enable"

	case "$board_name" in
		ap-hk*|ap-ac*|ap-cp*|ap-oak*|ap-mp*|*emu*|ap-al*|ap-sdx*|ap-mi*)
		if [ -f /sys/module/qca_ol/parameters/is_monitor_installed ]; then
			monitor_installed="$(cat /sys/module/qca_ol/parameters/is_monitor_installed)"
		fi
		if [ "$monitor_installed" = "1" ]; then
			echo "Enable ol_stats by default for Lithium platforms"
			"$device_if" "$phy" enable_ol_stats 1
		fi
	;;
		*) echo "ol_stats is disabled for non-Lithium platforms"
	;;
	esac

	config_get_bool enable_ol_stats "$device" enable_ol_stats
	[ -n "$enable_ol_stats" ] && "$device_if" "$phy" enable_ol_stats "$enable_ol_stats"

	config_get emiwar80p80 "$device" emiwar80p80
	[ -n "$emiwar80p80" ] && "$device_if" "$phy" emiwar80p80 "$emiwar80p80"

	config_get_bool rst_tso_stats "$device" rst_tso_stats
	[ -n "$rst_tso_stats" ] && "$device_if" "$phy" rst_tso_stats "$rst_tso_stats"

	config_get_bool rst_lro_stats "$device" rst_lro_stats
	[ -n "$rst_lro_stats" ] && "$device_if" "$phy" rst_lro_stats "$rst_lro_stats"

	config_get_bool rst_sg_stats "$device" rst_sg_stats
	[ -n "$rst_sg_stats" ] && "$device_if" "$phy" rst_sg_stats "$rst_sg_stats"

	config_get_bool set_fw_recovery "$device" set_fw_recovery
	[ -n "$set_fw_recovery" ] && "$device_if" "$phy" set_fw_recovery "$set_fw_recovery"

	config_get_bool allowpromisc "$device" allowpromisc
	[ -n "$allowpromisc" ] && "$device_if" "$phy" allowpromisc "$allowpromisc"

	config_get set_sa_param "$device" set_sa_param
	[ -n "$set_sa_param" ] && "$device_if" "$phy" set_sa_param $set_sa_param

	config_get_bool aldstats "$device" aldstats
	[ -n "$aldstats" ] && "$device_if" "$phy" aldstats "$aldstats"

	config_get macaddr "$device" macaddr
	[ -n "$macaddr" ] && "$device_if" "$phy" setHwaddr "$macaddr"

	config_get promisc "$device" promisc
	[ -n "$promisc" ] && "$device_if" "$phy" promisc $promisc

	config_get mode0 "$device" mode0
	[ -n "$mode0" ] && "$device_if" "$phy" fc_buf_min 2501

	config_get mode1 "$device" mode1
	[ -n "$mode1" ] && "$device_if" "$phy" fc_buf_min 0

	handle_aggr_burst() {
		local value="$1"
		[ -n "$value" ] && "$device_if" "$phy" aggr_burst $value
	}

	config_list_foreach "$device" aggr_burst handle_aggr_burst

	config_get_bool block_interbss "$device" block_interbss
	[ -n "$block_interbss" ] && "$device_if" "$phy" block_interbss "$block_interbss"

	config_get set_pmf "$device" set_pmf
	[ -n "$set_pmf" ] && "$device_if" "$phy" set_pmf "${set_pmf}"

	config_get txbf_snd_int "$device" txbf_snd_int 100
	[ -n "$txbf_snd_int" ] && "$device_if" "$phy" txbf_snd_int "$txbf_snd_int"

	config_get mcast_echo "$device" mcast_echo
	[ -n "$mcast_echo" ] && "$device_if" "$phy" mcast_echo "${mcast_echo}"

	config_get obss_rssi_th "$device" obss_rssi_th 35
	[ -n "$obss_rssi_th" ] && "$device_if" "$phy" obss_rssi_th "${obss_rssi_th}"

	config_get obss_rxrssi_th "$device" obss_rxrssi_th 35
	[ -n "$obss_rxrssi_th" ] && "$device_if" "$phy" obss_rxrssi_th "${obss_rxrssi_th}"

        config_get acs_txpwr_opt "$device" acs_txpwr_opt
        [ -n "$acs_txpwr_opt" ] && "$device_if" "$phy" acs_tcpwr_opt "${acs_txpwr_opt}"

        config_get set_mu_ppdu_dur "$device" set_mu_ppdu_dur
        [ -n "$set_mu_ppdu_dur" ] && "$device_if" "$phy" set_mu_ppdu_dur "$set_mu_ppdu_dur"

	config_get obss_long_slot "$device" obss_long_slot
	[ -n "$obss_long_slot" ] && "$device_if" "$phy" obss_long_slot "${obss_long_slot}"

	config_get staDFSEn "$device" staDFSEn
	[ -n "$staDFSEn" ] && "$device_if" "$phy" staDFSEn "${staDFSEn}"

	config_get scan_over_cac_en "$device" scan_over_cac_en
	[ -n "$scan_over_cac_en" ] && "$device_if" "$phy" scan_over_cac_en "${scan_over_cac_en}"

        config_get dbdc_enable "$device" dbdc_enable
        [ -n "$dbdc_enable" ] && "$device_if" "$phy" dbdc_enable "${dbdc_enable}"

        config_get client_mcast "$device" client_mcast
        [ -n "$client_mcast" ] && "$device_if" "$phy" client_mcast "${client_mcast}"

        config_get pas_scanen "$device" pas_scanen
        [ -n "$pas_scanen" ] && "$device_if" "$phy" pas_scanen "${pas_scanen}"

        config_get delay_stavapup "$device" delay_stavapup
        [ -n "$delay_stavapup" ] && "$device_if" "$phy" delay_stavapup "${delay_stavapup}"

        config_get tid_override_queue_map "$device" tid_override_queue_map
        [ -n "$tid_override_queue_map" ] && "$device_if" "$phy" queue_map "${tid_override_queue_map}"

        config_get channel_block_mode "$device" channel_block_mode
        [ -n "$channel_block_mode" ] && "$device_if" "$phy" acs_bmode "${channel_block_mode}"

        config_get no_vlan "$device" no_vlan
        [ -n "$no_vlan" ] && "$device_if" "$phy" no_vlan "${no_vlan}"

        config_get setNxtRadarFreq "$device" setNxtRadarFreq
        [ -n "$setNxtRadarFreq" ] && "$device_if" "$phy" setNxtRadarFreq "${setNxtRadarFreq}"

        config_get discon_time qcawifi discon_time 10
        [ -n "$discon_time" ] && "$device_if" "$phy" discon_time "${discon_time}"

        config_get reconfig_time qcawifi reconfig_time 60
        [ -n "$reconfig_time" ] && "$device_if" "$phy" reconfig_time "${reconfig_time}"

        config_get alwaysprimary qcawifi alwaysprimary
        [ -n "$alwaysprimary" ] && "$device_if" "$phy" alwaysprimary "${alwaysprimary}"

        config_get samessid_disable qcawifi samessid_disable
        [ -n "$samessid_disable" ] && "$device_if" "$phy" samessid_disable "${samessid_disable}"

	config_get nss_wifi_olcfg qcawifi nss_wifi_olcfg
	if [ -z "$nss_wifi_olcfg" ]; then
		if [ -f /lib/wifi/wifi_nss_olcfg ]; then
			nss_wifi_olcfg="$(cat /lib/wifi/wifi_nss_olcfg)"
		fi
	fi

	if [ -n "$nss_wifi_olcfg" ] && [ "$nss_wifi_olcfg" != "0" ]; then
		local mp_256="$(ls /proc/device-tree/ | grep -rw "MP_256")"
		local mp_512="$(ls /proc/device-tree/ | grep -rw "MP_512")"
		local kasan="$(zcat /proc/config.gz | grep -rw "CONFIG_KASAN=y")"

		config_get hwmode "$device" hwmode auto
		hk_ol_num="$(cat /lib/wifi/wifi_nss_hk_olnum)"
		#For 256 memory profile the range is preset in fw
		if [ "$mp_256" == "MP_256" ]; then
			:

		elif [ "$mp_512" == "MP_512" -a "$kasan" == "CONFIG_KASAN=y" ]; then
			:

		elif [ "$mp_512" == "MP_512" ]; then
			if [ $hk_ol_num -eq 3 ]; then
				if [ ! -f /tmp/wifi_nss_up_one_radio ]; then
					touch /tmp/wifi_nss_up_one_radio
					sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 31648
					sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 0
				fi
				case "$hwmode" in
				*bea |*axa | *ac)
					"$device_if" "$phy" fc_buf0_max 4096
					"$device_if" "$phy" fc_buf1_max 4096
					"$device_if" "$phy" fc_buf2_max 4096
					"$device_if" "$phy" fc_buf3_max 4096
					;;
				*)
					"$device_if" "$phy" fc_buf0_max 4096
					"$device_if" "$phy" fc_buf1_max 4096
					"$device_if" "$phy" fc_buf2_max 4096
					"$device_if" "$phy" fc_buf3_max 4096
					;;
				esac
			else
				if [ ! -f /tmp/wifi_nss_up_one_radio ]; then
					touch /tmp/wifi_nss_up_one_radio
					sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 30624
					sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 8192
				fi
				case "$hwmode" in
				*bea |*axa | *ac)
					"$device_if" "$phy" fc_buf0_max 8192
					"$device_if" "$phy" fc_buf1_max 8192
					"$device_if" "$phy" fc_buf2_max 8192
					"$device_if" "$phy" fc_buf3_max 8192
					;;
				*)
					"$device_if" "$phy" fc_buf0_max 8192
					"$device_if" "$phy" fc_buf1_max 8192
					"$device_if" "$phy" fc_buf2_max 8192
					"$device_if" "$phy" fc_buf3_max 8192
					;;
				esac
			fi
		else
		case "$board_name" in
            ap-hk09*)
			local soc_version_major="$(cat /sys/module/ipq_cnss2/parameters/soc_version_major)"

			if [ $soc_version_major = 2 ];then
				if [ ! -f /tmp/wifi_nss_up_one_radio ]; then
					touch /tmp/wifi_nss_up_one_radio
					#reset the high water mark for NSS if range 0 value > 4096
					sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 67392
					#initially after init 4k buf for 5G and 4k for 2G will be allocated, later range will be configured
					sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 40960
				fi
				case "$hwmode" in
				*bea | *axa | *ac)
					"$device_if" "$phy" fc_buf0_max 32768
					"$device_if" "$phy" fc_buf1_max 32768
					"$device_if" "$phy" fc_buf2_max 32768
					"$device_if" "$phy" fc_buf3_max 32768
				;;
				*)
					"$device_if" "$phy" fc_buf0_max 16384
					"$device_if" "$phy" fc_buf1_max 16384
					"$device_if" "$phy" fc_buf2_max 16384
					"$device_if" "$phy" fc_buf3_max 32768
				;;
				esac
			else
				case "$hwmode" in
				*ac)
					#we distinguish the legacy chipset based on the hwcaps
					hwcaps=$(cat /sys/class/net/${phy}/hwcaps)
					if [ "$hwcaps" == "802.11an/ac" ]; then
						"$device_if" "$phy" fc_buf0_max 8192
						"$device_if" "$phy" fc_buf1_max 12288
						"$device_if" "$phy" fc_buf2_max 16384
					else
						"$device_if" "$phy" fc_buf0_max 4096
						"$device_if" "$phy" fc_buf1_max 8192
						"$device_if" "$phy" fc_buf2_max 12288
					fi
					"$device_if" "$phy" fc_buf3_max 16384
					;;
				*)
					"$device_if" "$phy" fc_buf0_max 4096
					"$device_if" "$phy" fc_buf1_max 8192
					"$device_if" "$phy" fc_buf2_max 12288
					"$device_if" "$phy" fc_buf3_max 16384
					;;
				esac
			fi
			;;
		ap-hk* | ap-oak* | ap-cp* | ap-mp* | ap-ac*)
			if [ $hk_ol_num -ge 3 ]; then
				if [ ! -f /tmp/wifi_nss_up_one_radio ]; then
					touch /tmp/wifi_nss_up_one_radio
					sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 72512
					sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 36864
					update_ini_for_hk_sbs QCA8074V2_i.ini
				fi
				case "$hwmode" in
				*bea | *axa | *ac)
					"$device_if" "$phy" fc_buf0_max 24576
					"$device_if" "$phy" fc_buf1_max 24576
					"$device_if" "$phy" fc_buf2_max 24576
					"$device_if" "$phy" fc_buf3_max 32768
					;;
				*)
					"$device_if" "$phy" fc_buf0_max 16384
					"$device_if" "$phy" fc_buf1_max 16384
					"$device_if" "$phy" fc_buf2_max 16384
					"$device_if" "$phy" fc_buf3_max 24576
					;;
				esac
			else
				local soc_version_major="$(cat /sys/module/ipq_cnss2/parameters/soc_version_major)"

				if [ ! -f /tmp/wifi_nss_up_one_radio ]; then
					touch /tmp/wifi_nss_up_one_radio
					#reset the high water mark for NSS if range 0 value > 4096
					sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 67392
					#initially after init 4k buf for 5G and 4k for 2G will be allocated, later range will be configured
					sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 40960
					update_ini_for_hk_dbs QCA8074V2_i.ini
				fi
				case "$hwmode" in
				*bea | *axa | *ac)
					if [ $soc_version_major = 2 ];then
						"$device_if" "$phy" fc_buf0_max 32768
						"$device_if" "$phy" fc_buf1_max 32768
						"$device_if" "$phy" fc_buf2_max 32768
						"$device_if" "$phy" fc_buf3_max 32768
					else
						"$device_if" "$phy" fc_buf0_max 8192
						"$device_if" "$phy" fc_buf1_max 8192
						"$device_if" "$phy" fc_buf2_max 12288
						"$device_if" "$phy" fc_buf3_max 32768
					fi
				;;
				*)
					if [ $soc_version_major = 2 ];then
						"$device_if" "$phy" fc_buf0_max 16384
						"$device_if" "$phy" fc_buf1_max 16384
						"$device_if" "$phy" fc_buf2_max 16384
						"$device_if" "$phy" fc_buf3_max 32768
					else
						"$device_if" "$phy" fc_buf0_max 4096
						"$device_if" "$phy" fc_buf1_max 8192
						"$device_if" "$phy" fc_buf2_max 12288
						"$device_if" "$phy" fc_buf3_max 16384
					fi
				;;
				esac
			fi
			;;
		*)
			case "$hwmode" in
			*ng)
				"$device_if" "$phy" fc_buf0_max 5120
				"$device_if" "$phy" fc_buf1_max 8192
				"$device_if" "$phy" fc_buf2_max 12288
				"$device_if" "$phy" fc_buf3_max 16384
				;;
			*ac)
				"$device_if" "$phy" fc_buf0_max 8192
				"$device_if" "$phy" fc_buf1_max 16384
				"$device_if" "$phy" fc_buf2_max 24576
				"$device_if" "$phy" fc_buf3_max 32768
				;;
			*)
				"$device_if" "$phy" fc_buf0_max 5120
				"$device_if" "$phy" fc_buf1_max 8192
				"$device_if" "$phy" fc_buf2_max 12288
				"$device_if" "$phy" fc_buf3_max 16384
				;;
			esac
			;;
		esac
		fi
	else
		local mp_512="$(ls /proc/device-tree/ | grep -rw "MP_512")"
		config_get hwmode "$device" hwmode auto
		if [ "$mp_512" == "MP_512" ]; then
			case "$hwmode" in
				*bea | *axa | *ac)
					# For 128 clients
					"$device_if" "$phy" fc_buf_max 8192
					;;
				esac
		fi
	fi

	if [ $nss_wifi_olcfg == 0 ]; then
		sysctl_cmd dev.nss.n2hcfg.n2h_queue_limit_core0 2048
		sysctl_cmd dev.nss.n2hcfg.n2h_queue_limit_core1 2048
	else
		sysctl_cmd dev.nss.n2hcfg.n2h_queue_limit_core0 256
		sysctl_cmd dev.nss.n2hcfg.n2h_queue_limit_core1 256
	fi

	if [ "$wifi_hwm_script" = "1" ]; then
		enable_vifs_qcawificfg80211 $recover $device $wifi_hwm_script
	else
		enable_vifs_qcawificfg80211 $recover $device "$vifs_name" $4
	fi

	config_get country "$device" country
	if [ "$country" != "CN" -a "$country" != "156" ]; then
		config_get txpwr "$device" txpwr
		if [ "$txpwr" = "mid" ]; then
			"$device_if" "$phy" tpdbscale 1
		elif [ "$txpwr" = "min" ]; then
			"$device_if" "$phy" tpdbscale 3
		else
			"$device_if" "$phy" tpdbscale 0
		fi
	fi
	
	config_get wifi_debug_sh $device wifi_debug_sh
	[ -n "$wifi_debug_sh" -a -e "$wifi_debug_sh" ] && sh "$wifi_debug_sh"

        config_get primaryradio "$device" primaryradio
        [ -n "$primaryradio" ] && "$device_if" "$phy" primaryradio "${primaryradio}"

        config_get nobckhlradio "$device" nobckhlradio
        [ -n "$nobckhlradio" ] && "$device_if" "$phy" nobckhlradio "${nobckhlradio}"

        config_get CSwOpts "$device" CSwOpts
        [ -n "$CSwOpts" ] && "$device_if" "$phy" CSwOpts "${CSwOpts}"

	if [ -f "/lib/update_smp_affinity.sh" ]; then
		. /lib/update_smp_affinity.sh
		enable_smp_affinity_wifi $phy
	fi

	# check the ini file
	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		lock -u /var/run/device_$1
	else
		if [ "$recover" != "1" ]; then
			lock -u /var/run/wifilock
		fi
	fi
}

pre_mlo_update_qcawificfg80211() {
	local origin_cfg="$1"
	local origin_ifaces=
	local tmp_mld=""

	[ -z "$gdevice" ] && gdevice="${DEVICES}"

	#if origin_cfg not exist, return
	[ ! -f ${origin_cfg} ] && return

	list_append() {
		local list="$1"
		local append_ele="$2"
		local tmp_list=$(eval "echo \$${list}")
		[ -z "$append_ele" ] && return
		[ -z "$tmp_list" ] && eval "$list=\"$append_ele\"" && return
		local tmp_list2=" ${tmp_list} "
		[ "${tmp_list2%% $append_ele *}" = "${tmp_list2}" ] && eval "$list=\"$tmp_list $append_ele\""
	}

	local mlo_changed_links=""
	for mld in ${MLD_DEVICES}; do
		local mld_cmp=" $tmp_mld "
		[ "${mld_cmp%% $mld *}" != "$mld_cmp" ] && continue
		tmp_mld="$tmp_mld $mld"

		local mld_links=""
		for device in ${gdevice}; do
			config_get disabled "$device" disabled
			[ "$disabled" = "1" ] && {
				echo "'$device' is disabled" >/dev/console
				continue
			}

			origin_ifaces=$(uci show ${origin_cfg} | grep "\'${device}\'" | awk -F"." '{print $2}')
			config_get vifs "$device" vifs
			for vif in $vifs; do
				local origin_mld=
				local origin_mld_enable=
				local origin_iface_disab=
				local new_iface_disab=
				local new_mld_enable=
				local new_mld=
				local found=0

				config_get ifname "$vif" ifname
				for iface in $origin_ifaces; do
					origin_ifname=$(uci -q get ${origin_cfg}.${iface}.ifname)
					[ "$origin_ifname" = "$ifname" ] && found=1 && break
				done

				# found, compare mlo config
				config_get new_mld "$vif" mld
				if [ "$found" = "1" ]; then
					origin_mld=$(uci -q get ${origin_cfg}.${iface}.mld)
					[ "$origin_mld" != "$mld" -a "$new_mld" != "$mld" ] && continue

					# mld changed
					if [ "$origin_mld" != "$new_mld" ]; then
						[ -n "$new_mld" ] && config_set "$new_mld" mld_changed 1
						[ -n "$origin_mld" ] && config_set "$origin_mld" mld_changed 1
						config_set "$ifname" mld_changed 1
						list_append mlo_changed_links "$ifname"
						continue
					fi

					config_get new_iface_disab "$vif" disabled
					config_get new_mld_enable "$new_mld" mlo_enable
					config_get new_uplink_changed "$vif" uplink_changed 0

					origin_mld_enable=$(uci -q get ${origin_cfg}.${origin_mld}.mlo_enable)
					origin_iface_disab=$(uci -q get ${origin_cfg}.${iface}.disabled)

					# mlo enable or auth config changed
					if [ "$origin_mld_enable" != "$new_mld_enable" ] \
					 		|| [ "$new_uplink_changed" == "1" ] \
							|| [ "$origin_iface_disab" != "$new_iface_disab" ]; then
						config_set "$origin_mld" mld_changed 1
						config_set "$ifname" mld_changed 1
						list_append mlo_changed_links "$ifname"
						continue
					fi

					# add ifname to new_mld
					if [ "$new_mld" = "$mld" ]; then
						list_append mld_links "$ifname"
						continue
					fi
				else
					# not found
					if [ "$new_mld" = "$mld" ]; then
						config_set "$new_mld" mld_changed 1
						config_set "$ifname" mld_changed 1
						list_append mlo_changed_links "$ifname"
					fi
				fi
			done
		done

		config_get mld_changed "$mld" mld_changed 0
		if [ "$mld_changed" = "1" ]; then
			for vap in $mld_links; do
				config_set "$vap" mld_changed 1
				list_append mlo_changed_links "$vap"
			done
		fi
	done

	# There's no mld devices exist in new config, delete all affiliated links in old config
	if [ -z "${MLD_DEVICES}" ]; then
		origin_ifaces=$(uci show ${origin_cfg} | grep "=wifi-iface" | awk -F"." '{print $2}')
		for iface in $origin_ifaces; do
			origin_mld=$(uci -q get ${origin_cfg}.${iface}.mld)
			origin_ifname=$(uci -q get ${origin_cfg}.${iface}.ifname)
			origin_disabled=$(uci -q get ${origin_cfg}.${iface}.disabled)
			[ -z "$origin_mld" -o "$origin_disabled" = "1" ] && continue
			list_append mlo_changed_links "$origin_ifname"
		done
	fi

	. /lib/network/config.sh
	# down all mlo_changed_links
	for vap in $mlo_changed_links; do
		[ -f /sys/class/net/$vap/parent ] && { \
			[ -f "/var/run/hostapd-${vap}.lock" ] && { \
				wpa_cli -g /var/run/hostapd/global raw REMOVE ${vap}
				rm /var/run/hostapd-${vap}.lock
			}
			[ -f "/var/run/wpa_supplicant-${vap}.lock" ] && { \
				wpa_cli -g /var/run/wpa_supplicantglobal interface_remove ${vap}
				rm /var/run/wpa_supplicant-${vap}.lock
			}
			[ -f "/var/run/wapid-${vap}.conf" ] && { \
				kill "$(cat "/var/run/wifi-${vap}.pid")"
			}
			ifconfig "$vap" down
			unbridge "$vap" >>/dev/null
			iw "$vap" del
		}
	done
}

__bring_partner_mlo_link_up() {
	local partner_mlo_links=""
	local tmp_mld=""
	local parent_dev="$1"
	local ifname="$2"
	local parent_vifs=""
	local vifs_ifname=""
	local self_disabled=0
	local self_ifmld=""
	local self_mode=""
	local partner_ifname=""
	local partner_mld=""
	local partner_disabled=0
	local partner_mode=""
	local partner_vifs=""

	[ -z "$gdevice" ] && gdevice="${DEVICES}"

	config_get parent_vifs "$parent_dev" vifs
	for each_vif in $parent_vifs; do
		config_get vifs_ifname "$each_vif" ifname
		if [ "$ifname" = "$vifs_ifname" ]; then
			config_get self_disabled "$each_vif" disabled
			config_get self_ifmld "$each_vif" mld
			config_get self_mode "$each_vif" mode
			if [ -n "$self_ifmld" -a "$self_disabled" = "0" -a "$self_mode" = "ap" ]; then
				for each_device in ${gdevice}; do
					config_get partner_vifs "$each_device" vifs
					for partner_vif in $partner_vifs; do
						config_get partner_ifname "$partner_vif" ifname
						config_get partner_mld "$partner_vif" mld
						config_get partner_disabled "$partner_vif" disabled
						[ -z "$partner_mld" -o "$partner_disabled" = "1" -o "$vifs_ifname" = "$partner_ifname" ] && continue
						if [ "$self_ifmld" = "$partner_mld" ]; then
							config_get partner_mode "$partner_vif" mode
							[ "$partner_mode" = "ap" ] && append partner_mlo_links "$partner_ifname"
						fi
					done
				done
				break
			fi
		fi
	done

	for link in $partner_mlo_links; do
		if [ -f "/var/run/hostapd-${link}.lock" ]; then
			echo "__bring_partner_mlo_link_up : bring $ifname partner mlo link $link up" > /dev/console
			wpa_cli -g /var/run/hostapd/global raw REMOVE ${link}
			wpa_cli -g /var/run/hostapd/global raw ADD bss_config=${link}:/var/run/hostapd-${link}.conf
		fi
	done
}

__radio_cfg_change_check() {
	local device="$1"
	local origin_cfg="$2"

	origin_channel=
	origin_bw=
	origin_txpwr=
	origin_ax=
	origin_txbf=
	origin_cswopt=
	channel=
	bw=
	txpwr=
	ax=
	txbf=
	cswopt=
	key_changed=0
	channel_changed=0
	bw_changed=0
	txpower_changed=0
	ax_changed=0
	txbf_changed=0
	cswopt_changed=0

	#detect changed config
	origin_channel=$(uci -q get ${origin_cfg}.${device}.channel)
	[ -z $origin_channel ] && origin_channel=0
	origin_txpwr=$(uci -q get ${origin_cfg}.${device}.txpwr)
	origin_ax=$(uci -q get ${origin_cfg}.${device}.ax)
	origin_bw=$(uci -q get ${origin_cfg}.${device}.bw)
	origin_txbf=$(uci -q get ${origin_cfg}.${device}.txbf)
	origin_cswopt=$(uci -q get ${origin_cfg}.${device}.CSwOpts)

	config_get channel "$device" channel 0
	config_get txpwr "$device" txpwr
	config_get ax "$device" ax
	config_get bw "$device" bw 0
	config_get txbf "$device" txbf
	config_get cswopt "$device" CSwOpts 0

	[ -z "$origin_bw" ] && origin_bw="0"
	[ -z "$origin_cswopt" ] && origin_cswopt="0"

	[ "$channel" = "0" ] && channel=auto
	[ "$origin_channel" = "0" ] && origin_channel=auto

	[ "$origin_channel" != "$channel" ] && channel_changed=1
	[ "$origin_ax" != "$ax" ] && ax_changed=1
	[ "$origin_txpwr" != "$txpwr" ] && txpower_changed=1
	[ "$origin_bw" != "$bw" ] && bw_changed=1
	[ "$origin_txbf" != "$txbf" ] && txbf_changed=1
	[ "$origin_cswopt" != "$cswopt" ] && cswopt_changed=1

	#need to decide restart all vap or just single vap
	if [ "$channel_changed" = "1" ] \
		|| [ "$ax_changed" = "1" ] \
		|| [ "$bw_changed" = "1" ]; then
		restart_all=1
	fi
}

update_qcawificfg80211() {
	local device="$1"
	local origin_cfg="$2"
	local downup="$3"
	local delete_vaps=""
	local restart_all=0
	local up_vaps=""
	local create_vaps=""

	. /lib/network/config.sh
	[ -z "$downup" ] || {\
		include /lib/network
		cd /sys/class/net
		for dev in *; do
			[ -f /sys/class/net/${dev}/parent ] && { \
				local parent=$(cat /sys/class/net/${dev}/parent)
				[ -n "$parent" -a "$parent" = "$device" ] && {
					local state=$(hostapd_cli -i ${dev} -p /var/run/hostapd-${parent} status | grep state | cut -f2- -d=)
					[ -f "/var/run/hostapd-${dev}.lock" -a "$state" == "ENABLED" ] && { \
						wpa_cli -g /var/run/hostapd/global raw REMOVE ${dev}
						__bring_partner_mlo_link_up "$parent" "$dev"
						wpa_cli -g /var/run/hostapd/global raw ADD bss_config=${dev}:/var/run/hostapd-${dev}.conf
					}
				}
			}
		done
	}

	#if origin_cfg not exist, return
	[ ! -f ${origin_cfg} ] && return

	#device disabled changed
	local origin_dev_disabled=$(uci -q get ${origin_cfg}.${device}.disabled)
	[ -z "$origin_dev_disabled" ] && origin_dev_disabled=0
	config_get new_dev_disabled $device disabled 0
	if [ "$origin_dev_disabled" != "$new_dev_disabled" ]; then
		if [ "$new_dev_disabled" = "1" ]; then
			#device disabled changed from 0 -> 1
			disable_qcawificfg80211 "$device"
		else
			#device disabled changed from 1 -> 0
			enable_qcawificfg80211 "$device"
		fi
		return
	fi

	local origin_ifaces=$(uci show ${origin_cfg} | grep "\'${device}\'" | awk -F"." '{print $2}')
	#find interfaces which should be delete
	for iface in $origin_ifaces; do
		local match=0
		origin_ifname=$(uci -q get ${origin_cfg}.${iface}.ifname)
		find_related_vap_in_new_cfg() {
			config_get ifname "$1" ifname
			config_get disabled "$1" disabled
			if [ "$ifname" = "$origin_ifname" ]; then
				match=1
				break
			fi
		}

		config_foreach find_related_vap_in_new_cfg wifi-iface
		[ "$match" = "0" -o "$disabled" = "1" ] && append delete_vaps "$origin_ifname"
		config_set "$origin_ifname" vif "$iface"
	done

	#if ifname exist but not in origin cfg, delete it
	include /lib/network
	cd /sys/class/net
	for dev in *; do
		[ -f /sys/class/net/${dev}/parent ] && { \
			local parent=$(cat /sys/class/net/${dev}/parent)
			[ -n "$parent" -a "$parent" = "$device" ] && {
				local match=0
				for iface in $origin_ifaces; do
					origin_ifname=$(uci -q get ${origin_cfg}.${iface}.ifname)
					origin_disabled=$(uci -q get ${origin_cfg}.${iface}.disabled)
					[ "$dev" = "$origin_ifname" ] && match=1 && break
				done
				[ "$match" = "0" -o "$origin_disabled" = "1" ] && append delete_vaps "$dev"
			}
		}
	done

	echo "update_qcawificfg80211: delete_vaps=$delete_vaps" >> /dev/console
	for vap in $delete_vaps; do
		[ -f /sys/class/net/${vap}/parent ] && { \
			local parent=$(cat /sys/class/net/${vap}/parent)
			[ -n "$parent" -a "$parent" = "$device" ] && { \
				[ -f "/var/run/hostapd-${vap}.lock" ] && { \
					wpa_cli -g /var/run/hostapd/global raw REMOVE ${vap}
					rm /var/run/hostapd-${vap}.lock
				}
				[ -f "/var/run/wpa_supplicant-${vap}.lock" ] && { \
					wpa_cli -g /var/run/wpa_supplicantglobal interface_remove  ${vap}
					rm /var/run/wpa_supplicant-${vap}.lock
				}
				[ -f "/var/run/wapid-${vap}.conf" ] && { \
					kill "$(cat "/var/run/wifi-${vap}.pid")"
				}

				ifconfig "$vap" down
				unbridge "$vap" >>/dev/null
				iw "$vap" del
			}
		}
	done

	__radio_cfg_change_check "$device" "$origin_cfg"

	# [XP-38835] RE在修改信道时，软重启sta接口存在60s超时，故在此先down掉同radio下所有vap接口
	if [ "$restart_all" = "1" ]; then
		include /lib/network
		cd /sys/class/net
		for dev in *; do
			[ -f /sys/class/net/${dev}/parent ] && { \
				local parent=$(cat /sys/class/net/${dev}/parent)
				[ -n "$parent" -a "$parent" = "$device" ] && { \
					[ -f "/var/run/hostapd-${dev}.lock" ] && { \
						wpa_cli -g /var/run/hostapd/global raw REMOVE ${dev}
						rm /var/run/hostapd-${dev}.lock
					}
					[ -f "/var/run/wpa_supplicant-${dev}.lock" ] && { \
						wpa_cli -g /var/run/wpa_supplicantglobal interface_remove ${dev}
						rm /var/run/wpa_supplicant-${dev}.lock
					}
					[ -f "/var/run/wapid-${dev}.conf" ] && { \
						kill "$(cat "/var/run/wifi-${dev}.pid")"
					}
					ifconfig "$dev" down
					unbridge "$dev" >>/dev/null
					__bring_partner_mlo_link_up "$parent" "$dev"
				}
			}
		done
	fi

	#find interfaces which should be created
	config_get vifs "$device" vifs
	for vif in $vifs; do
		config_get ifname "$vif" ifname
		if [ -f /sys/class/net/${ifname}/parent ]; then
			append up_vaps "$ifname"
		else
			append create_vaps "$ifname"
		fi
	done

	# if no device up, but enabled_vaps exist, do enable_qcawificfg80211
	if [ -n "$create_vaps" ] && [ -z "$up_vaps" ]; then
		enable_qcawificfg80211 "$device"
	elif [ -n "$create_vaps" ]; then
		for ifname in $create_vaps; do
			find_qcawifi_phy "$device" || return 1
			enable_vifs_qcawificfg80211 0 $device $ifname

			config_get vif "$ifname" vif
			[ -n "$vif" ] && uci -c /tmp -q set ${origin_cfg}.${vif}.disabled=1
		done
		uci -c /tmp commit ${origin_cfg}
	fi
}

post_mlo_update_qcawificfg80211() {
	local ap_links=""
	local tmp_mld=""

	[ -z "$gdevice" ] && gdevice="${DEVICES}"

	for mld in ${MLD_DEVICES}; do
		local mld_cmp=" $tmp_mld "
		[ "${mld_cmp%% $mld *}" != "$mld_cmp" ] && continue
		tmp_mld="$tmp_mld $mld"

		local mlo_links=""
		for device in ${gdevice}; do
			config_get disabled "$device" disabled
			[ "$disabled" = "1" ] && {
				echo "'$device' is disabled" >/dev/console
				continue
			}
			config_get vifs "$device" vifs
			for vif in $vifs; do
				config_get ifmld "$vif" mld
				config_get disabled "$vif" disabled
				[ "$disabled" = "1" ] && continue
				if [ "$ifmld" = $mld ]; then
					local link_found=0

					config_get ifname "$vif" ifname
					config_get link_mac "$mld" link_mac
					config_get link_id "$mld" link_id
					if [ -n "$link_mac" ]; then
						local new_mac="$(cat /sys/class/net/$ifname/address)"
						link_found=$(echo $link_mac | grep -c "$new_mac")
						if [ $link_found = 0 ];then
							link_mac="$link_mac $new_mac"
						fi
					else
						link_mac="$(cat /sys/class/net/$ifname/address)"
					fi

					if [ -n "$link_id" ]; then
						local new_link="${device:4:1}"
						if [ $link_found = 0 ];then
							link_id="$link_id $new_link"
						fi
					else
						link_id="${device:4:1}"
					fi
					ulink_mac=$(for mac in $link_mac; do echo $mac; done | tr '\n' ' ' | xargs)
					ulink_id=$(for id in $link_id; do echo $id; done | tr '\n' ' ' | xargs)
					config_set "$mld" link_mac "$ulink_mac"
					config_set "$mld" link_id "$ulink_id"
					append mlo_links "$ifname"
					config_set "$mld" mlo_links "$mlo_links"

					config_get mode "$vif" mode
					[ "$mode" = "ap" ] && append ap_links "$ifname"
				fi
			done
		done
	done

	eval "$1=\"$ap_links\""
}

__txpower_change() {
	local bdmode="$1"
	local device="$2"
	local txpwr="$3"
	local ifname=""
	local disabled=""

	# get a running interface belong device
	config_get vifs "$device" vifs
	for vif in $vifs; do
		config_get disabled "$vif" disabled 0
		[ "$disabled" = "1" ] && continue
		config_get ifname "$vif" ifname
		[ -d "/sys/class/net/$ifname" ] && break
		ifname=""
	done
	[ -z "$ifname" ] && return

	if [ "$bdmode" = "24G" ]; then
		max_power=$(uci -q get misc.wireless.if_2g_maxpower)
		if [ -z "$max_power" ]; then
			max_power=30
		fi
	else
		max_power=$(uci -q get misc.wireless.if_5g_maxpower)

		if [ -z "$max_power" ]; then
			max_power=30
		fi
	fi

	# if max power is xx.5 dBm, max_power = 2 * maxpower + 256
	# plz make sure your driver support this special method.
	float_flag=$(echo $max_power | grep "\.5")
	max_power="${max_power%%.*}"
	if [ "$txpwr" = "mid" ]; then
		txpower=`expr $max_power - 1`
	elif [ "$txpwr" = "min" ]; then
		txpower=`expr $max_power - 3`
	else
		txpower="$max_power"
	fi
	if [ "$float_flag" != "" ]; then
		txpower=`expr $txpower \* 2 + 1 + 256`
	fi
	txpower="${txpower:-$vif_txpower}"
	iwconfig "$ifname" txpower "${txpower%%.*}"
}

__bhsta_check() {
	local vif="$1"
	local ifname="$2"
	local backhaul=0

	[ -z "$vif" ] && [ -z "$ifname" ] && return

	config_get backhaul "$vif" backhaul 0
	if [ "$backhaul" = "1" ]; then
		local current_bhtype=$(/usr/sbin/topomon_action.sh current_status bh_type)
		local mesh_bh_mode=$(uci -q get wireless.meshbhmode.mode)
		if [ "$current_bhtype" = "wired" -o "$mesh_bh_mode" = "wired" ]; then
			local network_id=$(wpa_cli -p /var/run/wpa_supplicant-$ifname list_network 2>>dev/null| grep CURRENT | awk '{print $1}')
			[ -z "$network_id" ] && network_id=0
			wpa_cli -p /var/run/wpa_supplicant-$ifname disable_network $network_id
			echo "[qcawifi] current bh_type is wired, disable_network $ifname" >>/dev/console
		fi
	fi
}

__post_update_qcawificfg80211() {
	local device="$1"
	local origin_cfg="$2"
	local restart_all=0
	local bdmode
	local support_160m=$(uci -q get misc.wireless.support_160m)
	# MIWIFI iot_dev
	local iot_dev_support=$(uci -q get misc.features.iot_dev)
	local wifi5_bk_2G=$(uci -q get misc.wireless.wifi5_bk_2G)
	local wifi5_bk_5G=$(uci -q get misc.wireless.wifi5_bk_5G)

	#if origin_cfg not exist, return
	[ ! -f ${origin_cfg} ] && return

	# MIWIFI, decide bdmode
	dev="/sys/class/net/$device"
	hwcaps=$(cat ${dev}/hwcaps)
	case "${hwcaps}" in
		*11an) bdmode=5G;;
		*11an/ac) bdmode=5G;;
		*11an/ac/ax) bdmode=5G;;
		*11an/ac/ax/be) bdmode=5G;;
		*11abgn/ac) bdmode=5G;;
		*11abgn/ac/ax) bdmode=5G;;
		*11abgn) bdmode=24G;;
		*11bgn) bdmode=24G;;
		*11bgn/ax) bdmode=24G;;
		*11bgn/ax/be) bdmode=24G;;
	esac

	find_qcawifi_phy "$device" || return 1

	__radio_cfg_change_check "$device" "$origin_cfg"

	if [ "$restart_all" != "1" ] && [ "$txpower_changed" = "1" ]; then
		[ -z "$txpwr" ] && txpwr=max
		__txpower_change "$bdmode" "$device" "$txpwr"
		txpower_changed=0
	fi
	
	#set CSwOpts if changed
	if [ "$cswopt_changed" == "1" ]; then
		config_get device_if "$device" device_if "cfg80211tool"
		config_get phy "$device" phy
		config_get CSwOpts "$device" CSwOpts                                                                                                 
		[ -n "$CSwOpts" ] && "$device_if" "$phy" CSwOpts "${CSwOpts}"
	fi

	local wifi5_reconfig_mode=0
	local origin_ifaces=$(uci show ${origin_cfg} | grep "\'${device}\'" | awk -F"." '{print $2}')
	config_get vifs "$device" vifs
	for vif in $vifs; do
		local found=0
		local origin_ssid
		local origin_encrytion
		local origin_pwd
		local origin_key
		local origin_hidden
		local origin_mimesh
		local origin_rrm
		local origin_wnm
		local origin_twt_responder
		local ssid
		local encrytion
		local pwd
		local key
		local rrm
		local wnm
		local hidden
		local mimesh
		local backhaul
		local hostap_mld
		local twt_responder
		local ssid_changed=0
		local ency_changed=0
		local pwd_changed=0
		local key_changed=0
		local hidden_changed=0
		local rrm_changed=0
		local wnm_changed=0
		local on_changed=0
		local mimesh_changed=0
		local mld_changed=0
		local disabled=0
		local hostap_mld_changed=0
		local twt_responder_changed=0
		local iotwifi5mode_changed=0

		config_get ifname "$vif" ifname
		config_get disabled "$vif" disabled 0
		config_get backhaul "$vif" backhaul 0

		[ "$disabled" = "1" ] && continue

		#get new config
		config_get ssid "$vif" ssid
		config_get encrytion "$vif" encryption
		config_get pwd "$vif" sae_password
		config_get key "$vif" key
		config_get rrm "$vif" rrm
		config_get wnm "$vif" wnm
		config_get hidden "$vif" hidden
		config_get mimesh "$vif" miwifi_mesh
		config_get mld_changed "$ifname" mld_changed 0
		config_get hostap_mld "$vif" mld
		config_get twt_responder "$vif" twt_responder
		config_get iotwifi5mode "$vif" iotwifi5mode

		#get origin config
		for iface in $origin_ifaces; do
			origin_ifname=$(uci -q get ${origin_cfg}.${iface}.ifname)
			[ "$origin_ifname" = "$ifname" ] && found=1 && break
		done

		if [ "$found" = "1" ]; then
			origin_disabled=$(uci -q get ${origin_cfg}.${iface}.disabled)
			[ -z $origin_disabled ] && origin_disabled=0

			origin_ssid=$(uci -q get ${origin_cfg}.${iface}.ssid)
			origin_encrytion=$(uci -q get ${origin_cfg}.${iface}.encryption)
			origin_pwd=$(uci -q get ${origin_cfg}.${iface}.sae_password)
			origin_key=$(uci -q get ${origin_cfg}.${iface}.key)
			origin_rrm=$(uci -q get ${origin_cfg}.${iface}.rrm)
			origin_wnm=$(uci -q get ${origin_cfg}.${iface}.wnm)
			origin_hidden=$(uci -q get ${origin_cfg}.${iface}.hidden)
			origin_mimesh=$(uci -q get ${origin_cfg}.${iface}.miwifi_mesh)
			origin_mld=$(uci -q get ${origin_cfg}.${iface}.mld)
			origin_hostap_mld=$(uci -q get ${origin_cfg}.${iface}.mld)
			origin_twt_responder=$(uci -q get ${origin_cfg}.${iface}.twt_responder)
			origin_iotwifi5mode=$(uci -q get ${origin_cfg}.${iface}.iotwifi5mode)

			[ "$origin_disabled" != "$disabled" ] && on_changed=1
			[ "$origin_ssid" != "$ssid" ] && ssid_changed=1
			[ "$origin_encrytion" != "$encrytion" ] && ency_changed=1
			[ "$origin_pwd" != "$pwd" ] && pwd_changed=1
			[ "$origin_key" != "$key" ] && key_changed=1
			[ "$origin_rrm" != "$rrm" ] && rrm_changed=1
			[ "$origin_wnm" != "$wnm" ] && wnm_changed=1
			[ "$origin_hidden" != "$hidden" ] && hidden_changed=1
			[ "$origin_mimesh" != "$mimesh" ] && mimesh_changed=1
			[ "$origin_twt_responder" != "$twt_responder" ] && twt_responder_changed=1
			[ "$origin_iotwifi5mode" != "$iotwifi5mode" ] && iotwifi5mode_changed=1
		else
			on_changed=1
		fi

		[ -n "$hostap_mld" -a "$on_changed" = "1" ] && mld_changed=1
		if [ "$mld_changed" = "1" ]; then
			start_vifs_qcawificfg80211 "$device" "$vif" ""
			continue
		fi

		local force_hostapd_attach
		local board_name
		[ -f /tmp/sysinfo/board_name ] && {
			board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
		}
		case "$board_name" in
			ap-sdx*) config_get force_hostapd_attach qcawifi force_hostapd_attach 0 ;;
			*) force_hostapd_attach=1 ;;
		esac
		config_set "$device" force_hostapd_attach "$force_hostapd_attach"

		if [ $restart_all == 1 ] || [ $channel_changed == 1 ] || [ $ax_changed == 1 ] ||
		[ $bw_changed == 1 ] || [ $txbf_changed == 1 ] || [ $on_changed == 1 ] || [ $ssid_changed == 1 ] ||
		[ $ency_changed == 1 ] || [ $pwd_changed == 1 ] || [ $key_changed == 1 ] || [ $hidden_changed == 1 ] ||
		[ $mimesh_changed == 1 ] || [ $rrm_changed == 1 ] || [ $wnm_changed == 1 ] ||
		[ $twt_responder_changed == 1 ] || [ $iotwifi5mode_changed == 1 ]; then

			if [ "$restart_all" != "1" ]; then
				include /lib/network
				cd /sys/class/net
				[ -f /sys/class/net/${ifname}/parent -a "$restart_all" != "1" ] && { \
					local parent=$(cat /sys/class/net/${ifname}/parent)
					[ -n "$parent" -a "$parent" = "$device" ] && { \
						[ -f "/var/run/hostapd-${ifname}.lock" ] && { \
							wpa_cli -g /var/run/hostapd/global raw REMOVE ${ifname}
							rm /var/run/hostapd-${ifname}.lock
						}
						[ -f "/var/run/wpa_supplicant-${ifname}.lock" ] && { \
							wpa_cli -g /var/run/wpa_supplicantglobal  interface_remove  ${ifname}
							rm /var/run/wpa_supplicant-${ifname}.lock
						}
						[ -f "/var/run/wapid-${ifname}.conf" ] && { \
							kill "$(cat "/var/run/wifi-${ifname}.pid")"
						}
						ifconfig "$ifname" down
						unbridge "$ifname" >>/dev/null
						__bring_partner_mlo_link_up "$parent" "$ifname"
					}
				}
			fi

			config_get band "$device" band 0
			config_get mode "$vif" mode
			config_get device_if "$device" device_if "cfg80211tool"

			config_get htmode "$device" htmode auto
			[ auto = "$channel" ] && channel=0
			[ AUTO = "$channel" ] && channel=0
			[ -z "$bw" ] && bw="0"
			force11NGHT40=0
			if [ "$bdmode" = "24G" ]; then
				case "$bw" in
					20) htmode=HT20;;
					40|80)
						if [ "$channel" = 0 ]; then
							htmode=HT40
						elif [ "$channel" -lt 7 ]; then
							htmode=HT40+
						else
							htmode=HT40-
						fi
						force11NGHT40=1
					;;
					*)
						if [ "$channel" = 0 ]; then
							htmode=HT40
						elif [ "$channel" -lt 7 ]; then
							htmode=HT40+
						else
							htmode=HT40-
						fi
					;;
				esac
			else
				case "$bw" in
					20) htmode=HT20;;
					40)
						if [ "$channel" = 0 ]; then
							htmode=HT40
						fi
						if [ "$channel" = 36 \
						-o "$channel" = 44 \
						-o "$channel" = 52 \
						-o "$channel" = 60 \
						-o "$channel" = 100 \
						-o "$channel" = 108 \
						-o "$channel" = 116 \
						-o "$channel" = 124 \
						-o "$channel" = 132 \
						-o "$channel" = 149 \
						-o "$channel" = 157 ]; then
							htmode=HT40+
						fi
						if [ "$channel" = 40 \
						-o "$channel" = 48 \
						-o "$channel" = 56 \
						-o "$channel" = 64 \
						-o "$channel" = 104 \
						-o "$channel" = 112 \
						-o "$channel" = 120 \
						-o "$channel" = 128 \
						-o "$channel" = 136 \
						-o "$channel" = 153 \
						-o "$channel" = 161 ]; then
							htmode=HT40-
						fi
					;;
					80) htmode=HT80;;
					160) 
						htmode=HT160;;
					*) 
						if [ "$channel" = 0 ]; then
							if [ -f /sys/class/net/$device/5g_maxchwidth ]; then
								maxchwidth="$(cat /sys/class/net/$device/5g_maxchwidth)"
								[ -n "$maxchwidth" ] && htmode=HT$maxchwidth
							fi
						elif [ "$support_160m" != "1" \
						-o "$channel" = 149 \
						-o "$channel" = 153 \
						-o "$channel" = 157 \
						-o "$channel" = 161 ]; then
							htmode=HT80
						else
							htmode=HT160
						fi
					;;
				esac
			fi

			if [ "$channel" = 165 ]; then
				htmode=HT20
			fi

			config_get hwmode "$device" hwmode auto
			pureg=0
			config_get ax "$device" ax
			if [ "$ax" = "0" ]; then
				if [ "$bdmode" = "24G" ]; then
					hwmode=11ng
				else
					hwmode=11ac
				fi
			fi
			# MIWIFI iot_dev
			[ "$iot_dev_support" == "1" -a "$ax" == "1" ] && {
				config_get iotwifi5mode "$vif" iotwifi5mode 0
				if [ "$ifname" == "$wifi5_bk_2G" ]; then
					if [ "$iotwifi5mode" == "1" ]; then
						hwmode=11ng
					else
						hwmode=11axg
					fi
				elif [ "$ifname" == "$wifi5_bk_5G" ]; then
					if [ "$iotwifi5mode" == "1" ]; then
						hwmode=11ac
					else
						hwmode=11axa
					fi
				fi
			}

			case "$hwmode:$htmode" in
				# The parsing stops at the first match so we need to make sure
				# these are in the right orders (most generic at the end)
				*ng:HT20) hwmode=11NGHT20;;
				*ng:HT40-) hwmode=11NGHT40MINUS;;
				*ng:HT40+) hwmode=11NGHT40PLUS;;
				*ng:HT40) hwmode=11NGHT40;;
				*ng:*) hwmode=11NGHT20;;
				*na:HT20) hwmode=11NAHT20;;
				*na:HT40-) hwmode=11NAHT40MINUS;;
				*na:HT40+) hwmode=11NAHT40PLUS;;
				*na:HT40) hwmode=11NAHT40;;
				*na:*) hwmode=11NAHT40;;
				*ac:HT20) hwmode=11ACVHT20;;
				*ac:HT40+) hwmode=11ACVHT40PLUS;;
				*ac:HT40-) hwmode=11ACVHT40MINUS;;
				*ac:HT40) hwmode=11ACVHT40;;
				*ac:HT80) hwmode=11ACVHT80;;
				*ac:HT160) hwmode=11ACVHT160;;
				*ac:HT80_80) hwmode=11ACVHT80_80;;
				*ac:*) hwmode=11ACVHT80
				if [ -f /sys/class/net/${device}/5g_maxchwidth ]; then
					maxchwidth="$(cat /sys/class/net/${device}/5g_maxchwidth)"
					if [ $maxchwidth -gt 160 ]; then
						maxchwidth=160
					fi
					[ -n "$maxchwidth" ] && hwmode=11ACVHT$maxchwidth
				fi
				if [ "$mode" == "sta" ]; then
					cat /sys/class/net/${device}/hwmodes | grep  "11AC_VHT80_80"
					if [ $? -eq 0 ]; then
						hwmode=11ACVHT80_80
					fi
				fi;;
				*axg:HT20) hwmode=11GHE20;;
				*axg:HT40-) hwmode=11GHE40MINUS;;
				*axg:HT40+) hwmode=11GHE40PLUS;;
				*axg:HT40) hwmode=11GHE40;;
				*axg:*) hwmode=11GHE20;;
				*axa:HT20) hwmode=11AHE20;;
				*axa:HT40+) hwmode=11AHE40PLUS;;
				*axa:HT40-) hwmode=11AHE40MINUS;;
				*axa:HT40) hwmode=11AHE40;;
				*axa:HT80) hwmode=11AHE80;;
				*axa:HT160) hwmode=11AHE160;;
				*axa:HT80_80) hwmode=11AHE80_80;;
				*axa:*) hwmode=11AHE80
					if [ -f /sys/class/net/${device}/5g_maxchwidth ]; then
						maxchwidth="$(cat /sys/class/net/${device}/5g_maxchwidth)"
						if [ $maxchwidth -gt 160 ]; then
							maxchwidth=160
						fi
						[ -n "$maxchwidth" ] && hwmode=11AHE$maxchwidth
					fi
					if [ "$mode" == "sta" ]; then
						cat /sys/class/net/${device}/hwmodes | grep  "11AXA_HE80_80"
						if [ $? -eq 0 ]; then
							hwmode=11AHE80_80
						fi
					fi;;
				*beg:HT20) hwmode=11GEHT20;;
				*beg:EHT20) hwmode=11GEHT20;;
				*beg:HT40-) hwmode=11GEHT40MINUS;;
				*beg:EHT40-) hwmode=11GEHT40MINUS;;
				*beg:HT40+) hwmode=11GEHT40PLUS;;
				*beg:EHT40+) hwmode=11GEHT40PLUS;;
				*beg:HT40) hwmode=11GEHT40;;
				*beg:EHT40) hwmode=11GEHT40;;
				*beg:*) hwmode=11GEHT20;;
				*bea:HT20) hwmode=11AEHT20;;
				*bea:EHT20) hwmode=11AEHT20;;
				*bea:HT40+) hwmode=11AEHT40PLUS;;
				*bea:EHT40+) hwmode=11AEHT40PLUS;;
				*bea:HT40-) hwmode=11AEHT40MINUS;;
				*bea:EHT40-) hwmode=11AEHT40MINUS;;
				*bea:HT40) hwmode=11AEHT40;;
				*bea:EHT40) hwmode=11AEHT40;;
				*bea:HT80) hwmode=11AEHT80;;
				*bea:EHT80) hwmode=11AEHT80;;
				*bea:HT160) hwmode=11AEHT160;;
				*bea:EHT160) hwmode=11AEHT160;;
				*bea:HT320) hwmode=11AEHT320;;
				*bea:EHT320) hwmode=11AEHT320;;
				*bea:*) hwmode=11AEHT320
					if [ -f /sys/class/net/$device/5g_maxchwidth ]; then
						maxchwidth="$(cat /sys/class/net/$device/5g_maxchwidth)"
						if [ $maxchwidth -gt 160 ]; then
							maxchwidth=160
						fi
						[ -n "$maxchwidth" ] && hwmode=11AEHT$maxchwidth
					fi;;
				*b:*) hwmode=11B;;
				*bg:*) hwmode=11G;;
				*g:*) hwmode=11G; pureg=1;;
				*a:*) hwmode=11A;;
				*) hwmode=auto;;
			esac

			#if channel/bw/ax changed, need to reconfig mode
			if [ $channel_changed == 1 -o $bw_changed == 1 -o $ax_changed == 1 -o "$iotwifi5mode_changed" == "1" ] || 
				[ "$wifi5_reconfig_mode" == "1" -a "$ifname" == "$wifi5_bk_5G" ] || 
				[ "$wifi5_reconfig_mode" == "1" -a "$ifname" == "$wifi5_bk_2G" ] ||
				[ "$on_changed" == "1" -a "$ifname" == "$wifi5_bk_5G" ] ||
				[ "$on_changed" == "1" -a "$ifname" == "$wifi5_bk_2G" ] ; then
				wifi5_reconfig_mode=1
				if [ "$mode" = "ap" ]; then
					if is_iotwifi_ifname $ifname; then
						process_iotwifi $ifname $hwmode
					else
						"$device_if" "$ifname" mode "$hwmode"
					fi
				else
					[ "sta" = "$mode" ] && "$device_if" "$ifname" mode "$hwmode"
					[ 0 = "$channel" ] && "$device_if" "$ifname" mode "$hwmode"
					[ "$htmode" = "HT80_80" ] && "$device_if" "$ifname" mode "$hwmode"
				fi

				# for miwifi
				if [ "$force11NGHT40" = "1" ]; then
					"$device_if" "$ifname" disablecoext 1
				else
					"$device_if" "$ifname" disablecoext 0
				fi

				[ "$channel_changed" = "1" -a "$mode" = "ap" ] && {
					# do acs check, before change channel, avoid vap up failed
					do_acs_wait
					iwconfig "$ifname" channel "$channel"
				}
			fi

			#set ssid if changed
			[ "$ssid_changed" = "1" ] && {
				config_get mode "$vif" mode
				if [ $mode = "sta" ]; then
					[ -n "$ssid" ] && {
						cfg80211tool "$ifname" ssid "$ssid"
					}
				fi
			}

			#set hidden if changed
			[ "$hidden_changed" = "1" ] && {
				"$device_if" "$ifname" hide_ssid "$hidden"
			}

			#set rrm&wnm if changed
			[ "$wnm_changed" = "1" ] && {
				[ -n "$wnm" ] && "$device_if" "$ifname" wnm "$wnm"
			}

			[ "$rrm_changed" = "1" ] && {
				[ -n "$rrm" ] && "$device_if" "$ifname" rrm "$rrm"
			}

			#set miwifi_mesh if changed
			[ "$mimesh_changed" = "1" ] && {
				[ -n "$mimesh" ] && "$device_if" "$ifname" miwifi_mesh "$mimesh"
			}

			# set network_id & mesh_ver
			[ "$backhaul" = "1" ] && {
				local mesh_ver=$(mesh_cmd max_mesh_version)
				[ -n "$mesh_ver" ] && cfg80211tool "$ifname" mesh_ver "${mesh_ver}"

				local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
				[ -n "$network_id" ] && cfg80211tool "$ifname" mesh_id "0x${network_id}"

				config_get mesh_apmac "$vif" mesh_apmac
				[ -n "$mesh_apmac" ] && cfg80211tool "$ifname" mesh_apmac "${mesh_apmac}"

				config_get mesh_aplimit "$vif" mesh_aplimit
				[ -n "$mesh_aplimit" ] && cfg80211tool "$ifname" mesh_aplimit "${mesh_aplimit}"

				local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
				local wl_if_count="$(uci -q get misc.wireless.wl_if_count)"
				if [ "$bh_mlo_support" = "1" ] && [ "$wl_if_count" -gt 2 ]; then
					"$device_if" $ifname bhoui_supp 1
				fi
			}

			#set txbf if txbf changed
			[ "$txbf_changed" = "1" ] && {
				if [ "$mode" != "sta" ]; then
					if [ "$txbf" -eq 0 ]; then
						"$device_if" "$ifname" vhtmubfer 0
						"$device_if" "$ifname" he_mubfer 0
						"$device_if" "$ifname" he_ulmumimo 0
						"$device_if" "$ifname" set_eht_mu_bfmr 0
						"$device_if" "$ifname" set_eht_ulmumimo 0
					else
						"$device_if" "$ifname" vhtmubfer 1
						"$device_if" "$ifname" he_mubfer 1
						"$device_if" "$ifname" he_ulmumimo 1
						"$device_if" "$ifname" set_eht_mu_bfmr 3
						"$device_if" "$ifname" set_eht_ulmumimo 3
					fi
				fi
			}

			[ "$twt_responder_changed" = "1" ] && {
				"$device_if" "$ifname" twt_responder "$twt_responder"
			}

			local start_hostapd=

			config_get mode "$vif" mode
			config_get enc "$vif" encryption "none"

			case "$enc" in
				wep*|mixed*|psk*|wpa*|8021x)
					start_hostapd=1
					config_get key "$vif" key
				;;
			esac

			local start_hostapd= vif_txpower= nosbeacon= wlanaddr=""
			config_get eap_type "$vif" eap_type
			config_get force_tkip "$vif" force_tkip 0
			if [ -f /sys/class/net/${device}/ciphercaps ]; then
				case "$enc" in
					*gcmp*)
						echo "enc:GCMP" >&2
						cat /sys/class/net/${device}/ciphercaps | grep -i "gcmp"
						if [ $? -ne 0 ]; then
							echo "enc:GCMP is Not Supported on Radio" >&2
							continue
						fi
						;;
					*ccmp-256*)
						echo "enc:CCMP-256" >&2
						cat /sys/class/net/${device}/ciphercaps | grep -i "ccmp-256"
						if [ $? -ne 0 ]; then
							echo "enc:CCMP-256 is Not Supported on Radio" >&2
							continue
						fi
						;;
					*tkip*)
						echo "enc:TKIP" >&2
						if [ $band -eq 3 ] && [ $force_tkip -ne 1 ]; then
							echo "enc:TKIP is Not Supported on 6GHz Radio" >&2
							continue
						fi
						;;
				esac
			fi

			if [ $ifname == "wl13" ]; then
				config_get_bool bindstatus "$vif" bindstatus 0
				config_get_bool userswitch "$vif" userswitch 1
				/usr/sbin/sysapi.firewall  miot
			fi

			config_get_bool sae "$vif" sae 0
			config_get_bool owe "$vif" owe 0
			config_get_bool dpp "$vif" dpp
			config_get pkex_code "$vif" pkex_code
			config_get suite_b "$vif" suite_b 0

			if [ $suite_b -eq 192 ]; then
				cat /sys/class/net/${device}/ciphercaps | grep -i "gcmp-256"
				if [ $? -ne 0 ]; then
					echo "enc:GCMP-256 is Not Supported on Radio" > /dev/console
					destroy_vap $ifname
					continue
				fi
			elif [ $suite_b -ne 0 ]; then
				echo "$suite_b bit security level is not supported for SUITE-B" > /dev/console
				destroy_vap $ifname
				continue
			fi

			if [ ! -z ${dpp} ]; then
				if [ "${dpp}" -eq 1 ]; then
					cfg80211tool "$ifname" set_dpp_mode 1
					config_get dpp_type "$vif" dpp_type "qrcode"
					if [ "$dpp_type" != "qrcode" -a "$dpp_type" != "pkex" ]; then
						echo "Invalid DPP type" > /dev/console
						destroy_vap $ifname
						continue
					elif [ "$dpp_type" == "pkex" ]; then
						if [ -z "$pkex_code" ]; then
							echo "pkex_code should not be NULL" > /dev/console
							destroy_vap $ifname
						fi
					fi
				fi
			fi

			case "$enc" in
				none)
					# We start hostapd in open mode also
					start_hostapd=1
				;;
				wpa*|8021x|osen*)
					start_hostapd=1
				;;
				mixed*|wep*|psk*)
					start_hostapd=1
					config_get key "$vif" key
					config_get sae_password "$vif" sae_password
					config_get wpa_psk_file  "$vif" wpa_psk_file
					if [ -z "$key" ] && [ -z $wpa_psk_file ]; then
						echo "Key is NULL" > /dev/console
						destroy_vap $ifname
						continue
					fi
					case "$enc" in
						*tkip*|wep*)
							if [ $sae -eq 1 ] || [ $owe -eq 1 ]; then
								echo "With SAE/OWE enabled, tkip/wep enc is not supported" > /dev/console
								destroy_vap $ifname
								continue
							fi
						;;
					esac

					if [ $sae -eq 1 ]; then
						if [ $sae_password -eq 0 ] && [ -z "$key" ]; then
							echo "key and sae_password are NULL" > /dev/console
							destroy_vap $ifname
							continue
						fi
					fi
				;;
				tkip*)
					if [ $sae -eq 1 ] || [ $owe -eq 1 ]; then
						echo "With SAE/OWE enabled, tkip enc is not supported" > /dev/console
						destroy_vap $ifname
						continue
					fi
				;;
				wapi*)
					start_wapid=1
					config_get key "$vif" key
				;;
				#Needed ccmp*|gcmp* check for SAE OWE auth types
				ccmp*|gcmp*)
					flag=0
					start_hostapd=1
					config_get key "$vif" key
					config_get sae_password "$vif" sae_password
					if [ $sae -eq 1 ]; then
						if [ -z "$sae_password" ] && [ -z "$key" ]; then
							echo "key/sae_password are NULL" > /dev/console
							destroy_vap $ifname
							continue
						fi
					fi
					if [ $owe -eq 1 ]; then
						if [ "$mode" = "ap" ]; then
							check_owe_groups() {
								local owe_groups=$(echo $1 | tr "," " ")
								for owe_group_value in $owe_groups
								do
									if [ $owe_group_value -ne 19 ] && [ $owe_group_value -ne 20 ] && [ $owe_group_value -ne 21 ]; then
											echo "Invalid owe_group: $owe_group_value" > /dev/console
											destroy_vap $ifname
											flag=1
											break
									fi
								done
							}
							config_list_foreach "$vif" owe_groups check_owe_groups
						elif [ "$mode" = "sta" ]; then
							config_get owe_group "$vif" owe_group
							if [ -n "$owe_group" && ${#owe_group} -ne 2 ]; then
								echo "Invalid owe_group: $owe_group" > /dev/console
								destroy_vap $ifname
								flag=1
								break;
							fi
						fi
						if [ $flag -eq 1 ]; then
							continue
						fi
					fi
				;;
				sae*|dpp|psk2)
					start_hostapd=1
				;;
			esac

			case "$mode" in
				sta|adhoc)
					config_get addr "$vif" bssid
					[ -z "$addr" ] || { 
						iwconfig "$ifname" ap "$addr" 
					}
				;;
			esac

			local net_cfg bridge
			case "$board_name" in
			ap-sdx*)
				if [ "$force_hostapd_attach" -eq 1 ]; then
					# In SDX boards, bridge is "bridge0" and netifd is not present.
					# Hence, set the bridge and add $ifname to bridge manually when
					# override option is set
					bridge=bridge0
					config_set "$vif" bridge "$bridge"
					echo "Adding $ifname to bridge $bridge" > /dev/console
					brctl addif $bridge $ifname
				fi
			;;
			*)
				net_cfg="$(find_net_config "$vif")"
				if [ -z "$net_cfg" ] || [ "$isolate" = 1 -a "$mode" = "wrap" ]; then
					echo "net_cfg = $net_cfg isolate = $isolate mode = $mode" > /dev/console
				else
					[ -f /sys/class/net/${ifname}/parent ] && {
						bridge="$(bridge_interface "$net_cfg")"
						config_set "$vif" bridge "$bridge"
					}
				fi
			;;
			esac

			case "$mode" in
				ap|wrap|ap_monitor|ap_smart_monitor|mesh|ap_lp_iot)
					config_get_bool isolate "$vif" ap_isolate 0
					"$device_if" "$ifname" ap_bridge "$((isolate^1))"

					config_get_bool l2tif "$vif" l2tif
					[ -n "$l2tif" ] && "$device_if" "$ifname" l2tif "$l2tif"

					if [ -n "$start_wapid" ]; then
						wapid_setup_vif "$vif" || {
							echo "enable_qcawifi($device): Failed to set up wapid for interface $ifname" >&2
							ifconfig "$ifname" down
							iw "$ifname" del
							continue
						}
					fi

					if [ "$mode" == "ap_lp_iot" ]; then
						default_dtim_period=41
					else
						default_dtim_period=1
					fi
					config_get dtim_period "$vif" dtim_period
					if [ -z "$dtim_period" ]; then
						config_set "$vif" dtim_period $default_dtim_period
					fi

					## XP-29788,XP-30004. cfg 165 20M ; vifs init fail
					## hostapd_setup_vif will use htmode, we should rewrite it before
					config_set "$device" htmode "$htmode"
					if [ -n "$start_hostapd" ] && eval "type hostapd_setup_vif" 2>/dev/null >/dev/null; then
						hostapd_setup_vif "$vif" nl80211 no_nconfig || {
							echo "enable_qcawifi($device): Failed to set up hostapd for interface $ifname" >&2
							# make sure this wifi interface won't accidentally stay open without encryption
							ifconfig "$ifname" down
							iw "$ifname" del
							continue
						}
						do_acs_wait
					fi
				;;
				wds|sta)
					if eval "type wpa_supplicant_setup_vif" 2>/dev/null >/dev/null; then
						wpa_supplicant_setup_vif "$vif" nl80211 || {
							echo "enable_qcawifi($device): Failed to set up wpa_supplicant for interface $ifname" >&2
							ifconfig "$ifname" down
							iw "$ifname" del
							continue
						}
					fi
					# to fix wireless and wired loop problem
					__bhsta_check "$vif" "$ifname"
				;;
				adhoc)
					if eval "type wpa_supplicant_setup_vif" 2>/dev/null >/dev/null; then
						wpa_supplicant_setup_vif "$vif" nl80211 || {
							echo "enable_qcawifi($device): Failed to set up wpa"
							ifconfig "$ifname" down
							iw "$ifname" del
							continue
						}
					fi
			esac

			[ -z "$bridge" -o "$isolate" = 1 -a "$mode" = "wrap" ] || {
				[ -f /sys/class/net/${ifname}/parent ] && {
					start_net "$ifname" "$net_cfg"
				}
			}

			ifconfig "$ifname" up
			set_wifi_up "$vif" "$ifname"

			# for miwifi
			if [ "$bdmode" = "24G" ]; then 
				max_power=$(uci -q get misc.wireless.if_2g_maxpower)
				if [ -z "$max_power" ]; then
					max_power=30
				fi

				# dynamic edcca
				case "$board_name" in
					ap-al02-c6|ap-mi01.2)
						if [ "$country" == "CN" -o "$country" == "156" ]; then
							wifitool "$ifname" setUnitTestCmd 67 3 16 0 1
						fi
					;;
				esac

				"$device_if" "$ifname" 11ngvhtintop 1
				"$device_if" "$ifname" vht_mcs_10_11_nq2q_peer_supp 1
				"$device_if" "$ifname" vhtsubfee 0
				"$device_if" "$ifname" he_subfee 0

			else
				max_power=$(uci -q get misc.wireless.if_5g_maxpower)

				if [ -z "$max_power" ]; then
					max_power=30
				fi

				# IOT issue with AC88
				"$device_if" "$ifname" vhtstscap 3

				#5G MCS drop issue workaround
				wifitool "$ifname" setUnitTestCmd 67 5 1 0 16 12 5
				wifitool "$ifname" setUnitTestCmd 67 5 1 0 16 11 2
			fi

			# if max power is xx.5 dBm, max_power = 2 * maxpower + 256
			# plz make sure your driver support this special method.
			float_flag=$(echo $max_power | grep "\.5")
			max_power="${max_power%%.*}"

			if [ "$txpwr" = "mid" ]; then
				txpower=`expr $max_power - 1`
			elif [ "$txpwr" = "min" ]; then
				txpower=`expr $max_power - 3`
			else
				txpower="$max_power"
			fi

			if [ "$float_flag" != "" ]; then
				txpower=`expr $txpower \* 2 + 1 + 256`
			fi

			txpower="${txpower:-$vif_txpower}"

			[ -z "$txpower" ] || iwconfig "$ifname" txpower "${txpower%%.*}"

			# for miwifi
			# set dyn_bw_rts of 5G band to 1,make sure the SA MAC of RTS package is write
			if [ "$bdmode" = "5G" ]; then
				iwpriv "$ifname" dyn_bw_rts 1
			fi

			if [ $ifname == "wl13" ]; then
				config_get_bool bindstatus "$vif" bindstatus 0
				config_get_bool userswitch "$vif" userswitch 1
				/usr/sbin/sysapi.firewall  miot
			fi

			#need to check router bind or not
			if [ $ifname == "wl13" ] && [ $bindstatus == 0 -o $userswitch == 0 ];then
				hostapd_cli -i wl13 -p /var/run/hostapd-$device disable
				ifconfig $ifname down
			fi

			local bh_band=$(mesh_cmd backhaul get band)
			local bh_band_upcase=$(echo "$bh_band" | tr '[a-z]' '[A-Z]')
			local netmode=$(uci -q get xiaoqiang.common.NETMODE)
			local backhaul_ap_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
			if [ -n "$netmode" ] && [ "$netmode" = "whc_re" ]; then
				if [ $ifname = $backhaul_ap_iface ]; then
					local hop_count=$(cat /var/run/topomon/hop_count 2>/dev/null)
					#bring backhaul ap down on power up or hop > 1
					#topomon will check hop status later
					if [ -z $hop_count ] || [ $hop_count != "0" -a $hop_count != "1" ]; then
						cfg80211tool "$ifname" mesh_aplimit 0
					fi
				fi
			fi

			# meshie with oui_type=MIWIFI_MESH_OUI_TYPE at main backhaul band ap
			# meshie with oui_type=MIWIFI_BHINFO_OUI_TYPE at other backhaul band ap
			if [ "$backhaul_ap_iface" != "$ifname" ]; then
				cfg80211tool "$ifname" meshie_disab 1
			else
				cfg80211tool "$ifname" meshie_disab 0
			fi

			local mesh_role=$(mesh_cmd role)
			local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)
			local ifname_5G=$(uci -q get misc.wireless.ifname_5G)
			local backhaul_5g_ap_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
			if [ -n "$mesh_role" ] && [ "CAP" = "$mesh_role" -o "RE" = "$mesh_role" ]; then
				if [ "$mesh_support_dfs" != "1" ] && [ "$ifname" = "$ifname_5G" -o "$ifname" = "$backhaul_5g_ap_iface" ]; then
					wifitool "$ifname" block_acs_channel "52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165"
				fi
			fi

			local netmode=$(uci -q get xiaoqiang.common.NETMODE)
			if [ -n "$netmode" ] && [ "$netmode" = "whc_re" ]; then
				local backhaul_5g_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
				local mesh_bh_mode=$(uci -q get wireless.meshbhmode.mode)
				if [ $ifname = $backhaul_5g_sta_iface ]; then
					if [ $(cat /var/run/topomon/bh_type) = "wired" -o "$mesh_bh_mode" = "wired" ]; then
						wpa_cli -p /var/run/wpa_supplicant-$ifname disable_network 0
					fi
				fi
			fi
		fi

	done
}

post_update_qcawificfg80211() {
	local orig_cfg="$1"
	[ -z "orig_cfg" ] && return
	local mlo_support="$(mesh_cmd mlo_support)"
	local bh_mlo_support="$(mesh_cmd bh_mlo_support)"

	local mld_ap_links=""
	[ "$mlo_support" = "1" -o "$bh_mlo_support" = "1" ] && post_mlo_update_qcawificfg80211 mld_ap_links
	for device in ${DEVICES}; do (
		__post_update_qcawificfg80211 "$device" "$orig_cfg"
	); done

	# only up ap links
	for link in $mld_ap_links; do
		ifconfig $link up
	done
}

disable_vap_qcawificfg80211() {
	local device="$1"
	local vap="$2"

	. /lib/network/config.sh

	[ -f /sys/class/net/${vap}/parent ] && { \
		local parent=$(cat /sys/class/net/${vap}/parent)
		[ -n "$parent" -a "$parent" = "$device" ] && { \
			[ -f "/var/run/hostapd-${vap}.lock" ] && { \
				wpa_cli -g /var/run/hostapd/global raw REMOVE ${vap}
				rm /var/run/hostapd-${vap}.lock
			}
			[ -f "/var/run/wpa_supplicant-${vap}.lock" ] && { \
				wpa_cli -g /var/run/wpa_supplicantglobal  interface_remove  ${vap}
				rm /var/run/wpa_supplicant-${vap}.lock
			}
			[ -f "/var/run/wapid-${vap}.conf" ] && { \
				kill "$(cat "/var/run/wifi-${vap}.pid")"
			}

			ifconfig "$vap" down
			unbridge "$vap"
			iw "$vap" del
		}
	}
}

enable_mlo_vap_qcawificfg80211() {
	local j
	local i=1 #first interface name starts from $2
	local all_vifs=
	local vifs_count
	local multi_vifs_count
	local multi_ifname radio_ifname multi_vif_name multi_vifs_list
	local enable_devlist=""

	. /lib/network/config.sh

	while [ ${i} -le ${#} ]; do
		eval "multi_ifname=\${${i}}";
		radio_ifname=$(echo $multi_ifname | grep -c "wifi")
		if [ $radio_ifname = 1 ]; then
			j=$((i+1))
			multi_vifs_list=
			# There can be multiple athX interfaces passed
			# Concate them and send in multi_vifs_list
			while [ ${j} -le ${#} ]; do
				eval "multi_vif_name=\${${j}}";
				iface_name=$(echo $multi_vif_name|grep -c wifi)

				[ $iface_name = 1 ] && break;
				multi_vifs_list="$multi_vifs_list $multi_vif_name";
				j=$((j+1));
			done;
		fi

		scan_qcawificfg80211 "$multi_ifname"
		config_get disabled "$multi_ifname" disabled 0
		if [ "$disabled" != "1" ]; then
			echo "[enable_mlo_vap_qcawificfg80211-enable]: $multi_ifname $multi_vifs_list"
			enable_qcawificfg80211 "$multi_ifname" "$multi_vifs_list"

			append enable_devlist "$multi_ifname"
			config_set $multi_ifname vifs_list "$multi_vifs_list"
		fi
		i=$((j))
	done

	local mld_ap_links=""
	ubus_wifi_cmd "up"
	post_mlo_update_qcawificfg80211 mld_ap_links
	for device in $enable_devlist; do
		config_get multi_vifs_list "$device" vifs_list ""

		scan_qcawificfg80211 $device
		config_get vifs "$device" vifs
		for target_ifname in $multi_vifs_list; do
			for vif in $vifs; do
				config_get ifname "$vif" ifname
				[ "$ifname" != "$target_ifname" ] && continue

				config_get vif_diabled "$vif" disabled 0
				[ "$vif_disabled" = "1" ] && continue

				echo "[enable_mlo_vap_qcawificfg80211-start]: $device $ifname"
				start_vifs_qcawificfg80211 "$device" "$vif" "$ifname"
			done
		done
	done

	# only up ap links
	for link in $mld_ap_links; do
		ifconfig $link up
	done
}

enable_vap_qcawificfg80211() {
	export gdevice="${DEVICES}"

	if [ "$1" != "mlo" ]; then
		local device=$1
		local ifname=$2

		find_qcawifi_phy "$device" || return 1
		enable_vifs_qcawificfg80211 0 $device $ifname
		start_qcawificfg80211 $device $ifname
		return
	else
		shift 1
		enable_mlo_vap_qcawificfg80211 "$@"
	fi
}

get_cac_time_qcawificfg80211() {
	local if_name="$2"
	local channel="$3"
	local bw="$4"
	local cac_time=$(cfg80211tool ${if_name} get_cac_time ${channel} ${bw} | awk -F ':' '{print $2}')
	echo "$cac_time"
}

pre_kick_macs_qcawificfg80211() {
	local target_ifname="$1"
	local tmp_mld=""
	local mld_links=""
	local gdevice="${DEVICES}"

	local mlo_support="$(mesh_cmd mlo_support)"
	local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
	[ "$mlo_support" != "1" -a "$bh_mlo_support" != "1" ] && return

	for vif in $vifs; do
		config_get mode "$vif" mode
		[ "$mode" != "ap" ] && continue

		config_get ifname "$vif" ifname
		config_get mld "$vif" mld
		config_get mld_links "$mld" mld_links ""
		mld_links="$mld_links $ifname"
		all_links="$all_links $ifname"

		config_set "$mld" mld_links "$mld_links"
		config_set "$ifname" vif "$vif"
	done

	if [ -n "$target_ifname" ]; then
		config_get vif "$target_ifname" vif
		[ -z "$vif" ] && return
		config_get mld "$vif" mld
		config_get mld_links "$mld" mld_links
	else
		mld_links="$all_links"
		config_set all_links all_links "$all_links"
	fi

	# down all links
	for link in $mld_links; do
		ifconfig $link down
	done
}

post_kick_macs_qcawificfg80211() {
	local target_ifname="$1"

	if [ -n "$target_ifname" ]; then
		config_get vif "$target_ifname" vif
		[ -z "$vif" ] && return
		config_get mld "$vif" mld
		[ -z "$mld" ] && return
		config_get mld_links "$mld" mld_links
	else
		config_get mld_links all_links all_links
	fi

	# down all links
	for link in $mld_links; do
		ifconfig $link up
	done
}

kick_macs_qcawificfg80211() {
	local dev="$1"
	local iface="$2"

	[ -z "$dev" ] && return

	__down() {
		local vif="$1"
		config_get ifname $vif ifname
		ifconfig "$ifname" down
	}

	__up() {
		local vif="$1"

		config_get ifname $vif ifname
		local net_cfg bridge
		net_cfg="$(find_net_config "$vif")"
		[ -z "$net_cfg" ] || {
			[ -f /sys/class/net/${ifname}/parent ] && { \
				bridge="$(bridge_interface "$net_cfg")"
				config_set "$vif" bridge "$bridge"
			}
		}

		ifconfig "$ifname" up
		set_wifi_up "$vif" "$ifname"
	}

	__scan_vap() {
		local vif="$1"
		local dev="$2"
		local iface="$3"
		local action="$4"

		config_get device "$vif" device
		config_get disabled "$vif" disabled "0"
		config_get mode "$vif" mode
		config_get ifname "$vif" ifname
		config_get mld "$vif" mld

		[ "$disabled" == "1" ] && return
		[ -n "$mld" ] && return
		[ "$mode" != "ap" ] && return
		[ "$dev" != "$device" ] && return
		[ -n "$iface" -a "$iface" != "$ifname" ] && return
		"$action" "$vif"
	}

	config_load wireless
	config_foreach __scan_vap wifi-iface "$dev" "$iface" __down
	config_foreach __scan_vap wifi-iface "$dev" "$iface" __up
}

enable_vifs_qcawificfg80211() {
	local device="$2"
	local vifs_name="$3"
	local wifi_hwm_script=
	local recover="$1"
	local edge_ch_dep_applicable
	local all_vifs map_vif
	local monitor_installed="0"
	local vap_mode=""
	local wifi_3_0_installed="0"
	local support_160m=$(uci -q get misc.wireless.support_160m)

	if [ -f /sys/module/qca_ol/parameters/is_wifi_3_0_installed ]; then
		wifi_3_0_installed="$(cat /sys/module/qca_ol/parameters/is_wifi_3_0_installed)"
	fi

	get_vap_mode

	print_rl_set=0

	#Invoked from wifi_hw_mode script
	if [ "$3" = "1" ]; then
		vifs_name=
		wifi_hwm_script="$3"
	fi

	local board_name
	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	config_get vifs "$device" vifs
	config_get phy "$device" phy
	config_get device_if "$device" device_if "cfg80211tool"
	config_get band "$device" band 0
	config_get htmode "$device" htmode auto
	config_get channel "$device" channel 0
	config_get edge_channel_deprioritize "$device" edge_channel_deprioritize 1
	[ auto = "$channel" ] && channel=0
	[ AUTO = "$channel" ] && channel=0

	# MIWIFI
	local bdmode
	dev="/sys/class/net/${phy}"
	hwcaps=$(cat ${dev}/hwcaps)
	case "${hwcaps}" in
		*11an) bdmode=5G;;
		*11an/ac) bdmode=5G;;
		*11an/ac/ax) bdmode=5G;;
		*11an/ac/ax/be) bdmode=5G;;
		*11abgn/ac) bdmode=5G;;
		*11abgn/ac/ax) bdmode=5G;;
		*11abgn) bdmode=24G;;
		*11bgn) bdmode=24G;;
		*11bgn/ax) bdmode=24G;;
		*11bgn/ax/be) bdmode=24G;;
	esac
	config_get bw "$device" bw
	[ -z "$bw" ] && bw="0"
	force11NGHT40=0
	if [ "$bdmode" = "24G" ]; then
		case "$bw" in
			20) htmode=HT20;;
			40|80)
				if [ "$channel" = 0 ]; then
					htmode=HT40
				elif [ "$channel" -lt 7 ]; then
					htmode=HT40+
				else
					htmode=HT40-
				fi
				force11NGHT40=1
			;;
			*)
				if [ "$channel" = 0 ]; then
					htmode=HT40
				elif [ "$channel" -lt 7 ]; then
					htmode=HT40+
				else
					htmode=HT40-
				fi
			;;
		esac
	else
		case "$bw" in
			20) htmode=HT20;;
			40)
				if [ "$channel" = 0 ]; then
					htmode=HT40
				fi
				if [ "$channel" = 36 \
				-o "$channel" = 44 \
				-o "$channel" = 52 \
				-o "$channel" = 60 \
				-o "$channel" = 100 \
				-o "$channel" = 108 \
				-o "$channel" = 116 \
				-o "$channel" = 124 \
				-o "$channel" = 132 \
				-o "$channel" = 149 \
				-o "$channel" = 157 ]; then
					htmode=HT40+
				fi
				if [ "$channel" = 40 \
				-o "$channel" = 48 \
				-o "$channel" = 56 \
				-o "$channel" = 64 \
				-o "$channel" = 104 \
				-o "$channel" = 112 \
				-o "$channel" = 120 \
				-o "$channel" = 128 \
				-o "$channel" = 136 \
				-o "$channel" = 153 \
				-o "$channel" = 161 ]; then
					htmode=HT40-
				fi
			;;
			80) htmode=HT80;;
			160) 
				htmode=HT160
			;;
			*) 
				if [ "$channel" = 0 ]; then
					if [ -f /sys/class/net/$device/5g_maxchwidth ]; then
						maxchwidth="$(cat /sys/class/net/$device/5g_maxchwidth)"
						[ -n "$maxchwidth" ] && htmode=HT$maxchwidth
					fi
				elif [ "$support_160m" != "1" \
				-o "$channel" = 149 \
				-o "$channel" = 153 \
				-o "$channel" = 157 \
				-o "$channel" = 161 ]; then
					htmode=HT80
				else
					htmode=HT160
			fi
			;;
		esac
		fi

	if [ "$channel" = 165 ]; then
		htmode=HT20
	fi

	# # WAR to not use chan 36 as primary channel, when using higher BW.
	# if { [ $band -eq 0 ] || [ $band -eq 2 ]; } && [ $channel -eq 36 ]; then
	# 	if [ -f /sys/class/net/${device}/edge_ch_dep_applicable ]; then
	# 		edge_ch_dep_applicable=$(cat /sys/class/net/${device}/edge_ch_dep_applicable)
	# 		if [ $edge_ch_dep_applicable == "1" -a $edge_channel_deprioritize -eq 1 ]; then
	# 			[ HT20 != "$htmode" ] && channel=40 && echo " Primary channel is changed to 40"
	# 			[ HT40+ = "$htmode" ] && htmode=HT40- && echo " Mode changed to HT40MINUS with channel 40"
	# 		fi
	# 	fi
	# fi

	case "$board_name" in
		ap-hk*|ap-ac*|ap-cp*|ap-oak*|ap-mp*|ap-sdx*)
		if [ -f /sys/module/qca_ol/parameters/is_monitor_installed ]; then
			monitor_installed="$(cat /sys/module/qca_ol/parameters/is_monitor_installed)"
		fi
		if [ "$monitor_installed" = "1" ]; then
			echo "Enable ol_stats by default for Lithium platforms"
			"$device_if" "$phy" enable_ol_stats 1
		fi
	;;
		*) echo "ol_stats is disabled for non-Lithium platforms"
	;;
	esac

	config_get_bool enable_ol_stats "$device" enable_ol_stats
	[ -n "$enable_ol_stats" ] && "$device_if" "$phy" enable_ol_stats "$enable_ol_stats"

	config_get_bool low_latency_mode "$device" low_latency_mode
	[ -n "$low_latency_mode" ] && "$device_if" "$phy" low_latency_mode "$low_latency_mode"

	config_get all_vifs "$device" vifs
	for map_vif in $all_vifs; do
		config_get MapBSSType "$map_vif" MapBSSType

		# MapBSSType 64, vap is backhaul BSS
		if [ $(($((MapBSSType&64)) >> 6)) -eq 1 ]; then
			backhaul_BSS=1 # The radio has a backhaul BSS vap configured
			config_get backhaul_ssid "$map_vif" ssid
			config_get backhaul_key "$map_vif" key
			break;
		fi
	done

	if [ -z "$vifs_name" ]; then
		ifconfig "$phy" up
	fi

	for vif in $vifs; do
		local start_hostapd=

		config_get ifname "$vif" ifname
		if [ ! -z "$vifs_name" -a "$ifname" != "$vifs_name" ]; then
			continue
		fi

		bridge_fdb_entry_add $device $vif
		config_get mode "$vif" mode
		config_get enc "$vif" encryption "none"
		enc=$(echo $enc | awk '{ print tolower($0) }')
		case "$enc" in
			wep*|mixed*|psk*|wpa*|8021x)
				start_hostapd=1
				config_get key "$vif" key
			;;
		esac

		case "$mode" in
			ap|wrap)
				if [ -n "$start_hostapd" ] && [ $count -lt 2 ] && eval "type hostapd_config_multi_cred" 2>/dev/null >/dev/null; then
					hostapd_config_multi_cred "$vif"
					count=$(($count + 1))
				fi
				;;
		esac

		if [ ! -z "$vifs_name" ]; then
			break
		fi
	done

	echo "number of vifs: $vifs" >/dev/console

	# Enable RPS and disable qrfs, if rxchainmask is 15 for some platforms
	disable_qrfs_wifi=0
	enable_rps_wifi=0
	if [ $("$device_if" "$phy" get_rxchainmask | awk -F ':' '{ print $2 }') -gt 3 ]; then
		disable_qrfs_wifi=1
		enable_rps_wifi=1
	fi

	for vif in $vifs; do
		config_get ifname "$vif" ifname
		if [ ! -z "$vifs_name" -a "$ifname" != "$vifs_name" ]; then
			continue
		fi

		local start_hostapd= vif_txpower= nosbeacon= wlanaddr=""
		local wlanmode
		local is_valid_owe_group=0
		local is_valid_sae_group=0
		config_get ifname "$vif" ifname
		config_get ppe_vp "$vif" ppe_vp "ds"
		config_get enc "$vif" encryption "none"
		enc=$(echo $enc | awk '{ print tolower($0) }')
		config_get eap_type "$vif" eap_type
		config_get mode "$vif" mode
		config_get force_tkip "$vif" force_tkip 0
		config_get force_wep "$vif" force_wep 0
		config_get mld "$vif" mld
		wlanmode=$mode
		pmode=$mode

		# for monitor skip
		if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
			if [[ $mode != *"monitor"* ]] && [ -n "$4" ]; then
				continue
			fi
			if [[ $mode = *"monitor"* ]]; then
				if [ -f /sys/module/qca_ol/parameters/is_monitor_installed ]; then
					monitor_installed="$(cat /sys/module/qca_ol/parameters/is_monitor_installed)"
				fi
				if [ "$monitor_installed" = "0" ]; then
					echo $vif > /tmp/monitor_$vif
					continue
				fi
			fi
		fi

		# for mlo skip
		if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
			if [ -z $mld ] && [ -n "$5" ]; then
				continue
			fi
			if [ -n "$mld" ]; then
				if [ -f /sys/module/qca_ol/parameters/is_wifi_3_0_installed ]; then
					wifi_3_0_installed="$(cat /sys/module/qca_ol/parameters/is_wifi_3_0_installed)"
				fi
				if [ "$wifi_3_0_installed" = "0" ]; then
					echo $vif > /tmp/mlo_$vif
					continue
				fi
			fi
		fi

		config_get_bool disabled "$vif" disabled 0
		[ $disabled = 0 ] || continue

		local smartctl=$(uci -P /var/state get wireless."$ifname".smartctl)
		[ "${smartctl:-0}" = "0" ] || continue

		if [ -f /sys/class/net/$device/ciphercaps ]
		then
			case "$enc" in
				*gcmp*)
					echo "enc:GCMP" >&2
					cat /sys/class/net/$device/ciphercaps | grep -i "gcmp"
					if [ $? -ne 0 ]
					then
						echo "enc:GCMP is Not Supported on Radio" >&2
						continue
					fi
					;;
				*ccmp-256*)
					echo "enc:CCMP-256" >&2
					cat /sys/class/net/$device/ciphercaps | grep -i "ccmp-256"
					if [ $? -ne 0 ]
					then
						echo "enc:CCMP-256 is Not Supported on Radio" >&2
						continue
					fi
					;;
				*tkip*)
					echo "enc:TKIP" >&2
					if [ $band -eq 3 ] && [ $force_tkip -ne 1 ]
					then
						echo "enc:TKIP is Not Supported on 6GHz Radio" >&2
						continue
					fi
					;;
				*wep*)
					echo "enc:WEP" >&2
					if [ $force_wep -ne 1 ]
					then
						echo "enc:WEP is Not Supported Anymore" >&2
						continue
					fi
					;;
			esac
		fi

		[ "$wlanmode" = "ap" ] && wlanmode="__ap"
		[ "$wlanmode" = "sta" ] && wlanmode="managed"
		[ "$wlanmode" = "lite_monitor" ] && wlanmode="monitor"
		[ "$wlanmode" = "ap_monitor" ] && wlanmode="__ap"
		[ "$wlanmode" = "ap_smart_monitor" ] && wlanmode="__ap"
		[ "$wlanmode" = "ap_lp_iot" ] && wlanmode="__ap"
		[ "$wlanmode" = "mesh" ] && wlanmode="__ap"
		[ "$wlanmode" = "wrap" ] && wlanmode="__ap"

		[ "$pmode" = "ap_monitor" ] && pmode="specialvap"
		[ "$pmode" = "ap_smart_monitor" ] && pmode="smart_monitor"
		[ "$pmode" = "ap_lp_iot" ] && pmode="lp_iot_mode"

		case "$mode" in
			sta)
				config_get_bool nosbeacon "$device" nosbeacon
				config_get qwrap_enable "$device" qwrap_enable 0
				[ $qwrap_enable -gt 0 ] && wlanaddr="00:00:00:00:00:00"
				;;
			adhoc)
				config_get_bool nosbeacon "$vif" sw_merge 1
				;;
		esac

		if [ $ifname == "wl13" ]; then
			config_get_bool bindstatus "$vif" bindstatus 0
			config_get_bool userswitch "$vif" userswitch 1

			if [ $bindstatus == 1 ] && [ $channel == 0 ]; then
				sleep 4
			fi
			/usr/sbin/sysapi.firewall  miot
		fi

		[ -z "$ppe_vp" ] && ppe_vp=""
		[ "$nosbeacon" = 1 ] || nosbeacon=""
		if [ -z "$recover" ] || [ "$recover" -eq "0" ]; then
			config_get macaddr "$vif" macaddr
			if [ -n "$macaddr" ]; then
				wlanconfig "$ifname" create wlandev "$phy" wlanmode "$pmode" -bssid $macaddr ${wlanaddr:+wlanaddr "$wlanaddr"} ${ppe_vp:+ppe_vp "$ppe_vp"} ${nosbeacon:+nosbeacon} -cfg80211
			else
				wlanconfig "$ifname" create wlandev "$phy" wlanmode "$pmode" ${wlanaddr:+wlanaddr "$wlanaddr"} ${ppe_vp:+ppe_vp "$ppe_vp"} ${nosbeacon:+nosbeacon} -cfg80211
			fi

			if [ -z $mld ]; then
				echo "cfg80211: ifname: $ifname mode: $wlanmode cfgphy: $(cat /sys/class/net/$phy/phy80211/name)" >&2
				iw phy "$(cat /sys/class/net/$phy/phy80211/name)" interface add $ifname type $wlanmode
			else
				config_get mld_mac "$mld" mld_macaddr
				if [ -z "$mld_mac" ]; then
					echo "cfg80211: ifname: $ifname mode: $wlanmode cfgphy: $(cat /sys/class/net/$phy/phy80211/name) mld_iface: $mld " >&2
					iw phy "$(cat /sys/class/net/$phy/phy80211/name)" interface add $ifname type $wlanmode mld_iface $mld
				else
					echo "cfg80211: ifname: $ifname mode: $wlanmode cfgphy: $(cat /sys/class/net/$phy/phy80211/name) mld_addr: $mld_mac " >&2
					iw phy "$(cat /sys/class/net/$phy/phy80211/name)" interface add $ifname type $wlanmode mld_addr $mld_mac
				fi
			fi
			[ $? -ne 0 ] && {
				echo "enable_qcawifi($device): Failed to set up $mode vif $ifname" >&2
				continue
			}
			config_set "$vif" ifname "$ifname"
		fi
		if [ $nss_wifi_olcfg != 0 ] && [ $ppe_vp == 1 ]; then
			echo "$ifname" > /proc/sys/nss/ppe_vp/create && echo "PPE VP enabled for $ifname" > /dev/console
		fi

		# Set the gloabl print ratelimiting on the first VDEV only
		if [ $print_rl_set -eq 0 ]; then
			config_get print_rl_count qcawifi print_rl_count
			config_get print_rl_time qcawifi print_rl_time

			if [ $print_rl_count -gt 0 ] && [ $print_rl_time -gt 0 ]; then
				cfg80211tool "$ifname" print_rl  $print_rl_count $print_rl_time
				echo "Setting print ratelimiting to $print_rl_count prints per $print_rl_time sec" >/dev/console
			fi

			print_rl_set=1
		fi

        #Next check is just valid when calling from wifi_hw_mode script.
        #Vaps that are appended to wireless config file for wifi2 in DBS mode
        #will not be brought up when switching to DBS_SBS mode
		if [ "$wifi_hwm_script" = "1" ]; then
			ifc_error_code=`ifconfig $ifname`
			if [ -z "$ifc_error_code" ]; then
				if [ "$recover" != "1" ]; then
					lock -u /var/run/wifilock
				fi
				return 1
			fi
		fi

		[ $qwrap_enable -gt 0 ] && iw "$ifname" set 4addr on >/dev/null 2>&1

		config_get hwmode "$device" hwmode auto
		pureg=0

		config_get ax "$device" ax
		if [ "$ax" -eq 0 ]; then
			if [ "$bdmode" = "24G" ]; then
				hwmode=11ng
			else
				hwmode=11ac
			fi
		fi

		case "$hwmode:$htmode" in
		# The parsing stops at the first match so we need to make sure
		# these are in the right orders (most generic at the end)
			*ng:HT20) hwmode=11NGHT20;;
			*ng:HT40-) hwmode=11NGHT40MINUS;;
			*ng:HT40+) hwmode=11NGHT40PLUS;;
			*ng:HT40) hwmode=11NGHT40;;
			*ng:*) hwmode=11NGHT20;;
			*na:HT20) hwmode=11NAHT20;;
			*na:HT40-) hwmode=11NAHT40MINUS;;
			*na:HT40+) hwmode=11NAHT40PLUS;;
			*na:HT40) hwmode=11NAHT40;;
			*na:*) hwmode=11NAHT40;;
			*ac:HT20) hwmode=11ACVHT20;;
			*ac:HT40+) hwmode=11ACVHT40PLUS;;
			*ac:HT40-) hwmode=11ACVHT40MINUS;;
			*ac:HT40) hwmode=11ACVHT40;;
			*ac:HT80) hwmode=11ACVHT80;;
			*ac:HT160) hwmode=11ACVHT160;;
			*ac:HT80_80) hwmode=11ACVHT80_80;;
                        *ac:*) hwmode=11ACVHT80
			       if [ -f /sys/class/net/$device/5g_maxchwidth ]; then
			           maxchwidth="$(cat /sys/class/net/$device/5g_maxchwidth)"
				   if [ $maxchwidth -gt 160 ]; then
					   maxchwidth=160
				   fi
				   [ -n "$maxchwidth" ] && hwmode=11ACVHT$maxchwidth
			       fi
                               if [ "$mode" == "sta" ]; then
                                   cat /sys/class/net/$device/hwmodes | grep  "11AC_VHT80_80"
				   if [ $? -eq 0 ]; then
			               hwmode=11ACVHT80_80
				   fi
			       fi;;
			*axg:HT20) hwmode=11GHE20;;
			*axg:HT40-) hwmode=11GHE40MINUS;;
			*axg:HT40+) hwmode=11GHE40PLUS;;
			*axg:HT40) hwmode=11GHE40;;
			*axg:*) hwmode=11GHE20;;
			*axa:HT20) hwmode=11AHE20;;
			*axa:HT40+) hwmode=11AHE40PLUS;;
			*axa:HT40-) hwmode=11AHE40MINUS;;
			*axa:HT40) hwmode=11AHE40;;
			*axa:HT80) hwmode=11AHE80;;
			*axa:HT160) hwmode=11AHE160;;
			*axa:HT80_80) hwmode=11AHE80_80;;
			*axa:*) hwmode=11AHE80
				if [ -f /sys/class/net/$device/5g_maxchwidth ]; then
					maxchwidth="$(cat /sys/class/net/$device/5g_maxchwidth)"
				   if [ $maxchwidth -gt 160 ]; then
					maxchwidth=160
				   fi
					[ -n "$maxchwidth" ] && hwmode=11AHE$maxchwidth
				fi
				if [ "$mode" == "sta" ]; then
					cat /sys/class/net/$device/hwmodes | grep  "11AXA_HE80_80"
					if [ $? -eq 0 ]; then
						hwmode=11AHE80_80
					fi
				fi;;
			*beg:HT20) hwmode=11GEHT20;;
			*beg:EHT20) hwmode=11GEHT20;;
			*beg:HT40-) hwmode=11GEHT40MINUS;;
			*beg:EHT40-) hwmode=11GEHT40MINUS;;
			*beg:HT40+) hwmode=11GEHT40PLUS;;
			*beg:EHT40+) hwmode=11GEHT40PLUS;;
			*beg:HT40) hwmode=11GEHT40;;
			*beg:EHT40) hwmode=11GEHT40;;
			*beg:*) hwmode=11GEHT20;;
			*bea:HT20) hwmode=11AEHT20;;
			*bea:EHT20) hwmode=11AEHT20;;
			*bea:HT40+) hwmode=11AEHT40PLUS;;
			*bea:EHT40+) hwmode=11AEHT40PLUS;;
			*bea:HT40-) hwmode=11AEHT40MINUS;;
			*bea:EHT40-) hwmode=11AEHT40MINUS;;
			*bea:HT40) hwmode=11AEHT40;;
			*bea:EHT40) hwmode=11AEHT40;;
			*bea:HT80) hwmode=11AEHT80;;
			*bea:EHT80) hwmode=11AEHT80;;
			*bea:HT160) hwmode=11AEHT160;;
			*bea:EHT160) hwmode=11AEHT160;;
			*bea:HT320) hwmode=11AEHT320;;
			*bea:EHT320) hwmode=11AEHT320;;
			*bea:*) hwmode=11AEHT320
				if [ -f /sys/class/net/$device/6g_maxchwidth ]; then
					maxchwidth="$(cat /sys/class/net/$device/6g_maxchwidth)"
				fi
				if ( [ -z $maxchwidth ] && [ -f /sys/class/net/$device/5g_maxchwidth ] ); then
					maxchwidth="$(cat /sys/class/net/$device/5g_maxchwidth)"
				   if ( [ $maxchwidth -gt 160 ] && [ $band -ne 3 ] ); then
					maxchwidth=160
				   fi
				fi
				[ -n "$maxchwidth" ] && hwmode=11AEHT$maxchwidth
				;;
			*b:*) hwmode=11B;;
			*bg:*) hwmode=11G;;
			*g:*) hwmode=11G; pureg=1;;
			*a:*) hwmode=11A;;
			*) hwmode=auto;;
		esac

		if [ "$pmode" = "specialvap" ] || [ "$pmode" = "smart_monitor" ] || [ "$pmode" = "monitor" ]|| [ "$pmode" = "lite_monitor" ] || [ "$pmode" = "lp_iot_mode" ]; then
			echo "HWMODE: $hwmode" > /dev/console
			"$device_if" "$ifname" mode "$hwmode"
			config_get ccfs "$device" ccfs 0
			config_get puncture_bitmap "$device" puncture_bitmap 0
			"$device_if" "$ifname" channel "$channel" "$band" "$ccfs" "$puncture_bitmap"> /dev/null 2>&1

			[ $pureg -gt 0 ] && "$device_if" "$ifname" pureg "$pureg"

			config_get ssid "$vif" ssid
			[ -n "$ssid" ] && {
				cfg80211tool "$ifname" ssid "$ssid"
			}
		fi #end of propritery modes

		# [ "sta" = "$mode" ] && "$device_if" "$ifname" mode "$hwmode"
		# [ 0 = "$channel" ] && "$device_if" "$ifname" mode "$hwmode"
		# [ "$htmode" = "HT80_80" ] && "$device_if" "$ifname" mode "$hwmode"

		if [ "$mode" = "ap" ]; then
			if is_iotwifi_ifname $ifname; then
				process_iotwifi $ifname $hwmode
			else
				"$device_if" "$ifname" mode "$hwmode"
			fi
		else
			[ "sta" = "$mode" ] && "$device_if" "$ifname" mode "$hwmode"
			[ 0 = "$channel" ] && "$device_if" "$ifname" mode "$hwmode"
			[ "$htmode" = "HT80_80" ] && "$device_if" "$ifname" mode "$hwmode"
		fi

		config_get map "$vif" map 0
		[ $map -gt 0 ] && cfg80211tool_mesh "$ifname" map "$map"

		config_get MapBSSType "$vif" MapBSSType
		if [ ! -z $MapBSSType ]; then
			[ $MapBSSType -gt 0 ] && cfg80211tool_mesh "$ifname" MapBSSType "$MapBSSType"
		fi

                config_get rept_spl "$vif" rept_spl
		[ -n "$rept_spl" ] && cfg80211tool_mesh "$ifname" rept_spl "$rept_spl"

		config_get cfreq2 "$vif" cfreq2
		[ -n "$cfreq2" -a "$htmode" = "HT80_80" ] && "$device_if" "$ifname" cfreq2 "$cfreq2" "$band"

		#set channel; store in cfg80211 vap structures, use them while setting channels
		config_get ccfs "$device" ccfs 0
		config_get puncture_bitmap "$device" puncture_bitmap 0
		"$device_if" "$ifname" channel "$channel" "$band" "$ccfs" "$puncture_bitmap"> /dev/null 2>&1

		[ $pureg -gt 0 ] && cfg80211tool "$ifname" pureg "$pureg" #set pureg

		config_get puren "$vif" puren
		[ -n "$puren" ] && "$device_if" "$ifname" puren "$puren"

		config_get pure11ax "$vif" pure11ax
		[ -n "$pure11ax" ] && "$device_if" "$ifname" pure11ax "$pure11ax"

		config_get mbss_tx_vdev "$vif" mbss_tx_vdev
		[ -n "$mbss_tx_vdev" ] && "$device_if" "$ifname" mbss_tx_vdev "$mbss_tx_vdev"

		config_get_bool hidden "$vif" hidden 0
		"$device_if" "$ifname" hide_ssid "$hidden"

                config_get_bool dynamicbeacon "$vif" dynamicbeacon 0
                [ $hidden = 1 ] && "$device_if" "$ifname" dynamicbeacon "$dynamicbeacon"

                config_get db_rssi_thr "$vif" db_rssi_thr
                [ -n "$db_rssi_thr" ] && "$device_if" "$ifname" db_rssi_thr "$db_rssi_thr"

                config_get db_timeout "$vif" db_timeout
                [ -n "$db_timeout" ] && "$device_if" "$ifname" db_timeout "$db_timeout"

                config_get nrshareflag "$vif" nrshareflag
                [ -n "$nrshareflag" ] && "$device_if" "$ifname" nrshareflag "$nrshareflag"

		config_get shortgi "$vif" shortgi
		[ -n "$shortgi" ] && "$device_if" "$ifname" shortgi "${shortgi}"

		config_get_bool disablecoext "$vif" disablecoext
		[ -n "$disablecoext" ] && "$device_if" "$ifname" disablecoext "${disablecoext}"

		# for miwifi
		[ $force11NGHT40 -eq 1 ] && "$device_if" "$ifname" disablecoext 1

		config_get chwidth "$vif" chwidth
		[ -n "$chwidth" ] && "$device_if" "$ifname" chwidth "${chwidth}"

		#for miwifi
		config_get miwifi_mesh "$vif" miwifi_mesh
		[ -n "$miwifi_mesh" ] && "$device_if" "$ifname" miwifi_mesh "${miwifi_mesh}"

		local mesh_model=$(bdata get model)
		[ -n "$mesh_model" ] && "$device_if" "$ifname" mesh_model "${mesh_model}"

		local mesh_ver=$(mesh_cmd max_mesh_version)
		if [ -n "$mesh_ver" ]; then
			cfg80211tool "$ifname" mesh_ver "${mesh_ver}"
			local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
			if [ -n "$network_id" ]; then
				cfg80211tool "$ifname" mesh_id "0x${network_id}"
			fi
		fi

		# mesh_ver4.0: 避免cap恢复出厂后自动通过已入网的套装re入网，但不会成功而影响使用
		# 驱动新增机制，只在当前节点mesh_hop不为255时，才处理接收到的probe_request报文
		# 已初始化的非whc_re模式，此处需要设置mesh_hop为0，保证probe_request消息上报到应用层
		local mesh_role=$(mesh_cmd role)
		local init_flag=$(uci -q get xiaoqiang.common.INITTED)
		if [ "$init_flag" == "YES" -a "$mesh_role" != "RE" ]; then
			cfg80211tool "$ifname" mesh_hop 0
		fi

		config_get mesh_apmac "$vif" mesh_apmac
		[ -n "$mesh_apmac" ] && cfg80211tool "$ifname" mesh_apmac "${mesh_apmac}"

		config_get mesh_aplimit "$vif" mesh_aplimit
		[ -n "$mesh_aplimit" ] && cfg80211tool "$ifname" mesh_aplimit "${mesh_aplimit}"

		config_get multi_group_key "$vif" multi_group_key
		[ -n "$multi_group_key" ] && "$device_if" "$ifname" multi_group_key "${multi_group_key}"

		config_get max_group_keys "$vif" max_group_keys
		[ -n "$max_group_keys" ] && "$device_if" "$ifname" max_group_keys "${max_group_keys}"

		config_get wds "$vif" wds
		config_get map "$vif" map 0
		case "$wds" in
			1|on|enabled)	wds=1
				# Incase of map, wpa_supplicant enables 4-address mode after association.
				# So do not add STA interface to bridge yet.
				if [ $map -eq 0 ]; then
					iw "$ifname" set 4addr on >/dev/null 2>&1
				fi
				;;
			*)	wds=0
				;;
		esac
		"$device_if" "$ifname" wds "$wds" >/dev/null 2>&1

		config_get  backhaul "$vif" backhaul 0
		"$device_if" "$ifname" backhaul "$backhaul" >/dev/null 2>&1
		[ "$mesh_role" == "RE" -a "$backhaul" == "1" ] && "$device_if" "$ifname" mesh_hop 255 >/dev/null 2>&1

		local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
		local wl_if_count="$(uci -q get misc.wireless.wl_if_count)"
		if [ "$backhaul" = "1" ] && [ "$bh_mlo_support" = "1" ] && [ "$wl_if_count" -gt 2 ]; then
			"$device_if" $ifname bhoui_supp 1
		fi

		config_get mesh_mlolink "$vif" mesh_mlolink 0
		"$device_if" "$ifname" mesh_mlolink "$mesh_mlolink"

		config_get mesh_strongsnr "$vif" mesh_strongsnr 0
		"$device_if" "$ifname" mesh_strongsnr "$mesh_strongsnr"

		config_get mesh_weaksnr "$vif" mesh_weaksnr 0
		"$device_if" "$ifname" mesh_weaksnr "$mesh_weaksnr"

		config_get mesh_snr_margin "$vif" mesh_snr_margin 0
		"$device_if" "$ifname" mesh_snr_margin "$mesh_snr_margin"

		config_get TxBFCTL "$vif" TxBFCTL
		[ -n "$TxBFCTL" ] && "$device_if" "$ifname" TxBFCTL "$TxBFCTL"

		config_get bintval "$vif" bintval
		[ -n "$bintval" ] && "$device_if" "$ifname" bintval "$bintval"

		config_get_bool countryie "$vif" countryie 0
		[ -n "$countryie" ] && "$device_if" "$ifname" countryie "$countryie"

		config_get_bool vap_contryie "$vif" vap_contryie
		[ -n "$vap_contryie" ] && "$device_if" "$ifname" vap_contryie "$vap_contryie"

		config_get ppdu_duration "$device" ppdu_duration
		[ -n "$ppdu_duration" ] && "$device_if" "$phy" ppdu_duration "${ppdu_duration}"

		config_get he_ul_ppdu_dur "$device" he_ul_ppdu_dur
		[ -n "$he_ul_ppdu_dur" ] && "$device_if" "$phy" he_ul_ppdu_dur "${he_ul_ppdu_dur}"

		config_get own_ie_override "$vif" own_ie_override
                [ -n "$own_ie_override" ] && cfg80211tool "$ifname" rsn_override 1

		config_get_bool en_6g_sec_comp "$vif" en_6g_sec_comp 1
		"$device_if" "$ifname" en_6g_sec_comp "$en_6g_sec_comp"

		if [ $en_6g_sec_comp -eq 0 ]
		then
			config_get keymgmt_mask_6g "$vif" keymgmt_mask_6g 0x0FFFFFFF
			"$device_if" "$ifname" keymgmt_mask_6g "$keymgmt_mask_6g"
		fi

		# MLO WFA Security Compliance TestBed AP
		config_get_bool en_mlo_security "$vif" en_mlo_security 0
		if [ $en_mlo_security -eq 1 ] && [ "$mode" = "ap" ]
		then
			config_get link_ocv  "$vif" ocv 0
			config_get link_enc "$vif" encryption "none"
			enc=$(echo $enc | awk '{ print tolower($0) }')
			config_get_bool link_sae "$vif" sae 0
			config_get link_sae_pwe "$vif" sae_pwe 2
			config_get link_beacon_prot "$vif" beacon_prot 0
			config_get link_ieee80211w "$vif" ieee80211w 0
			config_get link_owe "$vif" owe 0

			if [ $link_sae -eq 1 ] || [ $link_owe -eq 1 ]
			then
				if [ $link_ieee80211w -ne 2 ]
				then
					echo "ML_AP:MFP Mandatory" > /dev/console
					destroy_vap $ifname
					continue;
				fi

				if [ $link_beacon_prot -ne 1 ]
				then
					echo "ML_AP:Beacon Protection Mandatory" > /dev/console
					destroy_vap $ifname
					continue;
				fi

				if [ $link_ocv -ne 0 ]
				then
					echo "ML_AP:OCV Disabled Mandatory" > /dev/console
					destroy_vap $ifname
					continue;
				fi

				case "$link_enc" in
					*gcmp-256*)
					;;
					*)
						echo "ML_AP:GCMP-256 Mandatory" > /dev/console
						destroy_vap $ifname
						continue;
					;;
				esac
			fi

			if [ $link_sae -eq 1 ]
			then
				if [ $link_sae_pwe -ne 1 ]
				then
					echo "ML_AP:In SAE, H2E  Mandatory" > /dev/console
					destroy_vap $ifname
					continue;
				fi
			fi
		fi

		config_get_bool sae "$vif" sae 0
		config_get_bool owe "$vif" owe
		config_get_bool dpp "$vif" dpp
		config_get pkex_code "$vif" pkex_code
		config_get suite_b "$vif" suite_b 0

		if [ $suite_b -eq 192 ]
		then
			cat /sys/class/net/$device/ciphercaps | grep -i "gcmp-256"
			if [ $? -ne 0 ]
			then
				echo "enc:GCMP-256 is Not Supported on Radio" > /dev/console
				destroy_vap $ifname
				continue
			fi
		elif [ $suite_b -ne 0 ]
		then
			echo "$suite_b bit security level is not supported for SUITE-B" > /dev/console
			destroy_vap $ifname
			continue
		fi

		if [ ! -z ${dpp} ]; then
			if [ "${dpp}" -eq 1 ]
			then
				cfg80211tool "$ifname" set_dpp_mode 1
				config_get dpp_type "$vif" dpp_type "qrcode"
				if [ "$dpp_type" != "qrcode" -a "$dpp_type" != "pkex" -a "$dpp_type" != "pbbs" ]
				then
					echo "Invalid DPP type" > /dev/console
					destroy_vap $ifname
					continue
				elif [ "$dpp_type" == "pkex" ]
				then
					if [ -z "$pkex_code" ]
					then
						echo "pkex_code should not be NULL" > /dev/console
						destroy_vap $ifname
					fi
				fi
			fi
		fi

		case "$enc" in
			none)
				# We start hostapd in open mode also
				start_hostapd=1
			;;
			wpa*|8021x|osen*)
				start_hostapd=1
			;;
			mixed*|wep*|psk*)
				start_hostapd=1
				config_get key "$vif" key
				config_get sae_password "$vif" sae_password
				config_get wpa_psk_file  "$vif" wpa_psk_file
				if [ -z "$key" ] && [ -z $wpa_psk_file ]; then
					echo "Key is NULL" > /dev/console
					destroy_vap $ifname
					continue
				fi
				case "$enc" in
					*tkip*|wep*)
						if [ $sae -eq 1 ] || [ $owe -eq 1 ]; then
							echo "With SAE/OWE enabled, tkip/wep enc is not supported" > /dev/console
							destroy_vap $ifname
							continue
						fi
					;;
				esac

				if [ $sae -eq 1 ]; then
					if [ $sae_password -eq 0 ] && [ -z "$key" ]; then
						echo "key and sae_password are NULL" > /dev/console
						destroy_vap $ifname
						continue
					fi
				fi
			;;
			tkip*)
				if [ $sae -eq 1 ] || [ $owe -eq 1 ]
				then
					echo "With SAE/OWE enabled, tkip enc is not supported" > /dev/console
					destroy_vap $ifname
					continue
				fi
			;;
			wapi*)
				start_wapid=1
				config_get key "$vif" key
			;;
			#Needed ccmp*|gcmp* check for SAE OWE auth types
			ccmp*|gcmp*)
				start_hostapd=1
				config_get key "$vif" key
				config_get sae_password "$vif" sae_password
				if [ $sae -eq 1 ]; then
					if [ -z "$key" ] && [ -z $sae_password ]; then
						echo "key and sae_password are NULL" > /dev/console
						destroy_vap $ifname
						continue
					fi
				fi

				if [ $owe -eq 1 ]
				then
					if [ "$mode" = "ap" ]
					then
						check_owe_groups() {
							local owe_groups=$(echo $1 | tr "," " ")
							for owe_group_value in $owe_groups
							do
								case "$owe_group_value" in
									0|19|20|21)
									;;
									*)
										echo "Invalid owe_group: $owe_group_value" > /dev/console
										destroy_vap $ifname
										is_valid_owe_group=1
										break
								esac
							done
						}
						config_list_foreach "$vif" owe_groups check_owe_groups
					elif [ "$mode" = "sta" ]; then
                                                config_get owe_group "$vif" owe_group 0
						case "$owe_group" in
							0|19|20|21)
							;;
							*)
								echo "Invalid owe_group: $owe_group" > /dev/console
								destroy_vap $ifname
								is_valid_owe_group=1
								break
						esac
                                        fi

					[ $is_valid_owe_group = 1 ] && continue
				fi
			;;
			sae*|dpp|psk2)
				start_hostapd=1
			;;
		esac

		case "$mode" in
			sta|adhoc)
				config_get addr "$vif" bssid
				[ -z "$addr" ] || {
#TODO
					iwconfig "$ifname" ap "$addr"
				}
			;;
		esac

		config_get_bool uapsd "$vif" uapsd 1
		"$device_if" "$ifname" uapsd "$uapsd"

		config_get powersave "$vif" powersave
		[ -n "$powersave" ] && "$device_if" "$ifname" powersave "${powersave}"

		config_get ant_ps_on "$vif" ant_ps_on
		[ -n "$ant_ps_on" ] && "$device_if" "$ifname" ant_ps_on "${ant_ps_on}"

		config_get ps_timeout "$vif" ps_timeout
		[ -n "$ps_timeout" ] && "$device_if" "$ifname" ps_timeout "${ps_timeout}"

		config_get mcastenhance "$vif" mcastenhance
		[ -n "$mcastenhance" ] && "$device_if" "$ifname" mcastenhance "${mcastenhance}"

		config_get disable11nmcs "$vif" disable11nmcs
		[ -n "$disable11nmcs" ] && "$device_if" "$ifname" disable11nmcs "${disable11nmcs}"

		config_get conf_11acmcs "$vif" conf_11acmcs
		[ -n "$conf_11acmcs" ] && "$device_if" "$ifname" conf_11acmcs "${conf_11acmcs}"

		config_get metimer "$vif" metimer
		[ -n "$metimer" ] && "$device_if" "$ifname" metimer "${metimer}"

		config_get metimeout "$vif" metimeout
		[ -n "$metimeout" ] && "$device_if" "$ifname" metimeout "${metimeout}"

		config_get_bool medropmcast "$vif" medropmcast
		[ -n "$medropmcast" ] && "$device_if" "$ifname" medropmcast "${medropmcast}"

		config_get me_adddeny "$vif" me_adddeny
		[ -n "$me_adddeny" ] && "$device_if" "$ifname" me_adddeny ${me_adddeny}

		#support independent repeater mode
		config_get vap_ind "$vif" vap_ind
		[ -n "$vap_ind" ] && "$device_if" "$ifname" vap_ind "${vap_ind}"

		#support extender ap & STA
		config_get extap "$vif" extap
		[ -n "$extap" ] && "$device_if" "$ifname" extap "${extap}"
		[ -n "$extap" ] && iw "$ifname" set 4addr on >/dev/null 2>&1

		# miwifi
		config_get intop "$vif" intop
		[ -n "$intop" ] && "$device_if" "$ifname" 11ngvhtintop "${intop}"

		# miwifi
		config_get vht_mcs_10_11 "$vif" vht_mcs_10_11
		[ -n "$vht_mcs_10_11" ] && "$device_if" "$ifname" vht_mcs_10_11_nq2q_peer_supp "${vht_mcs_10_11}"

		config_get scanband "$vif" scanband
		[ -n "$scanband" ] && "$device_if" "$ifname" scanband "${scanband}"

		config_get periodicScan "$vif" periodicScan
		[ -n "$periodicScan" ] && "$device_if" "$ifname" periodicScan "${periodicScan}"

		config_get cwmax "$vif" cwmax
		[ -n "$cwmax" ] && "$device_if" "$ifname" cwmax ${cwmax}

		config_get cwmin "$vif" cwmin
		[ -n "$cwmin" ] && "$device_if" "$ifname" cwmin ${cwmin}

		config_get aifs "$vif" aifs
		[ -n "$aifs" ] && "$device_if" "$ifname" aifs ${aifs}

		config_get txoplimit "$vif" txoplimit
		[ -n "$txoplimit" ] && "$device_if" "$ifname" txoplimit ${txoplimit}

		config_get noackpolicy "$vif" noackpolicy
		[ -n "$noackpolicy" ] && "$device_if" "$ifname" noackpolicy ${noackpolicy}

		config_get_bool wmm "$vif" wmm
		[ -n "$wmm" ] && "$device_if" "$ifname" wmm "$wmm"

		config_get_bool doth "$vif" doth
		[ -n "$doth" ] && "$device_if" "$ifname" doth "$doth"

		config_get doth_chanswitch "$vif" doth_chanswitch
		[ -n "$doth_chanswitch" ] && "$device_if" "$ifname" doth_chanswitch ${doth_chanswitch}

		config_get quiet "$vif" quiet
		[ -n "$quiet" ] && "$device_if" "$ifname" quiet "$quiet"

		config_get mfptest "$vif" mfptest
		[ -n "$mfptest" ] && "$device_if" "$ifname" mfptest "$mfptest"

		config_get dtim_period "$vif" dtim_period
		[ -n "$dtim_period" ] && "$device_if" "$ifname" dtim_period "$dtim_period"

		config_get noedgech "$vif" noedgech
		[ -n "$noedgech" ] && "$device_if" "$ifname" noedgech "$noedgech"

		config_get ps_on_time "$vif" ps_on_time
		[ -n "$ps_on_time" ] && "$device_if" "$ifname" ps_on_time "$ps_on_time"

		config_get inact "$vif" inact
		[ -n "$inact" ] && "$device_if" "$ifname" inact "$inact"

		config_get wnm "$vif" wnm
		[ -n "$wnm" ] && "$device_if" "$ifname" wnm "$wnm"

		config_get ampdu "$vif" ampdu
		[ -n "$ampdu" ] && "$device_if" "$ifname" ampdu "$ampdu"

		config_get amsdu "$vif" amsdu
		[ -n "$amsdu" ] && "$device_if" "$ifname" amsdu "$amsdu"

		config_get maxampdu "$vif" maxampdu
		[ -n "$maxampdu" ] && "$device_if" "$ifname" maxampdu "$maxampdu"

		config_get vhtmaxampdu "$vif" vhtmaxampdu
		[ -n "$vhtmaxampdu" ] && "$device_if" "$ifname" vhtmaxampdu "$vhtmaxampdu"

		config_get setaddbaoper "$vif" setaddbaoper
		[ -n "$setaddbaoper" ] && "$device_if" "$ifname" setaddbaoper "$setaddbaoper"

		config_get addbaresp "$vif" addbaresp
		[ -n "$addbaresp" ] && "$device_if" "$ifname" $addbaresp

		config_get addba "$vif" addba
		[ -n "$addba" ] && "$device_if" "$ifname" addba $addba

		config_get delba "$vif" delba
		[ -n "$delba" ] && "$device_if" "$ifname" delba $delba

		config_get_bool stafwd "$vif" stafwd 0
		[ -n "$stafwd" ] && "$device_if" "$ifname" stafwd "$stafwd"

		#config_get maclist "$vif" maclist
		#[ -n "$maclist" ] && {
		#	# flush MAC list
		#	"$device_if" "$ifname" maccmd 3
		#	for mac in $maclist; do
		#		"$device_if" "$ifname" addmac "$mac"
		#	done
		#}

		#config_get macfilter "$vif" macfilter
		#case "$macfilter" in
		#	allow)
		#		"$device_if" "$ifname" maccmd 1
		#	;;
		#	deny)
		#		"$device_if" "$ifname" maccmd 2
		#	;;
		#	*)
		#		# default deny policy if mac list exists
		#		[ -n "$maclist" ] && "$device_if" "$ifname" maccmd 2
		#	;;
		#esac


		# config_get maclist_sec "$vif" maclist_sec
		# [ -n "$maclist_sec" ] && {
		# 	# flush MAC list
		# 	"$device_if" "$ifname" maccmd_sec 3
		# 	for mac in $maclist_sec; do
		# 		"$device_if" "$ifname" addmac_sec "$mac"
		# 	done
		# }

		# config_get macfilter_sec "$vif" macfilter_sec
		# case "$macfilter_sec" in
		# 	allow)
		# 		"$device_if" "$ifname" maccmd_sec 1
		# 	;;
		# 	deny)
		# 		"$device_if" "$ifname" maccmd_sec 2
		# 	;;
		# 	*)
		# 		# default deny policy if mac list exists
		# 		[ -n "$maclist_sec" ] && "$device_if" "$ifname" maccmd_sec 2
		# 	;;
		# esac

		# miwifi mesh version 3, backhaul ap no need to support macfilter
		local bh_ap_2g=$(uci -q get misc.backhauls.backhaul_2g_ap_iface)
		local bh_ap_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
		local bh_ap_5gh=$(uci -q get misc.backhauls.backhaul_5gh_ap_iface)

		if [ "$ifname" != "$bh_ap_2g" ] \
			&& [ "$ifname" != "$bh_ap_5g" ] \
			&& [ "$ifname" != "$bh_ap_5gh" ]; then
			#miwifi change, should use second mac filter list
		config_get maclist "$vif" maclist
		[ -n "$maclist" ] && {
			# flush MAC list
				"$device_if" "$ifname" maccmd_sec 3
			for mac in $maclist; do
					"$device_if" "$ifname" addmac_sec "$mac"
			done
		}

		config_get macfilter "$vif" macfilter
		case "$macfilter" in
			allow)
				"$device_if" "$ifname" maccmd_sec 1
			;;
			deny)
				"$device_if" "$ifname" maccmd_sec 2
			;;
			*)
				# default deny policy if mac list exists
					[ -n "$maclist" ] && "$device_if" "$ifname" maccmd_sec 2
			;;
		esac
		fi

		config_get nss "$vif" nss
		[ -n "$nss" ] && "$device_if" "$ifname" nss "$nss"

		config_get set_vdev_peer_prot_count "$vif" set_vdev_peer_prot_count
		[ -n "$set_vdev_peer_prot_count" ] && "$device_if" "$ifname" set_vdev_peer_prot_count "$set_vdev_peer_prot_count"

		config_get set_vdev_peer_prot_dropmask "$vif" set_vdev_peer_prot_dropmask
		[ -n "$set_vdev_peer_prot_dropmask" ] && "$device_if" "$ifname" set_vdev_peer_prot_dropmask "$set_vdev_peer_prot_dropmask"

		config_get vht_mcsmap "$vif" vht_mcsmap
		[ -n "$vht_mcsmap" ] && "$device_if" "$ifname" vht_mcsmap "$vht_mcsmap"

		config_get he_mcs "$vif" he_mcs
		[ -n "$he_mcs" ] && "$device_if" "$ifname" he_mcs "$he_mcs"

		config_get chwidth "$vif" chwidth
		[ -n "$chwidth" ] && "$device_if" "$ifname" chwidth "$chwidth"

		config_get chbwmode "$vif" chbwmode
		[ -n "$chbwmode" ] && "$device_if" "$ifname" chbwmode "$chbwmode"

		config_get ldpc "$vif" ldpc
		[ -n "$ldpc" ] && "$device_if" "$ifname" ldpc "$ldpc"

		config_get rx_stbc "$vif" rx_stbc
		[ -n "$rx_stbc" ] && "$device_if" "$ifname" rx_stbc "$rx_stbc"

		config_get tx_stbc "$vif" tx_stbc
		[ -n "$tx_stbc" ] && "$device_if" "$ifname" tx_stbc "$tx_stbc"

		config_get cca_thresh "$vif" cca_thresh
		[ -n "$cca_thresh" ] && "$device_if" "$ifname" cca_thresh "$cca_thresh"

		config_get set11NRetries "$vif" set11NRetries
		[ -n "$set11NRetries" ] && "$device_if" "$ifname" set11NRetries "$set11NRetries"

		config_get chanbw "$vif" chanbw
		[ -n "$chanbw" ] && "$device_if" "$ifname" chanbw "$chanbw"

		config_get maxsta "$vif" maxsta
		[ -z "$maxsta" ] && maxsta=$(uci -q get misc.wireless.maxsta_per_radio)
		if [ "$bdmode" = "24G" ]; then
			maxsta=$(uci -q get misc.wireless.if_2g_maxsta)
		else
			maxsta=$(uci -q get misc.wireless.if_5g_maxsta)
		fi
		[ -n "$maxsta" ] && "$device_if" "$ifname" maxsta "$maxsta"

		config_get sko_max_xretries "$vif" sko_max_xretries
		[ -n "$sko_max_xretries" ] && "$device_if" "$ifname" sko "$sko_max_xretries"

		config_get extprotmode "$vif" extprotmode
		[ -n "$extprotmode" ] && "$device_if" "$ifname" extprotmode "$extprotmode"

		config_get extprotspac "$vif" extprotspac
		[ -n "$extprotspac" ] && "$device_if" "$ifname" extprotspac "$extprotspac"

		config_get_bool cwmenable "$vif" cwmenable
		[ -n "$cwmenable" ] && "$device_if" "$ifname" cwmenable "$cwmenable"

		config_get_bool protmode "$vif" protmode
		[ -n "$protmode" ] && "$device_if" "$ifname" protmode "$protmode"

		config_get enablertscts "$vif" enablertscts
		[ -n "$enablertscts" ] && "$device_if" "$ifname" enablertscts "$enablertscts"

		config_get txcorrection "$vif" txcorrection
		[ -n "$txcorrection" ] && "$device_if" "$ifname" txcorrection "$txcorrection"

		config_get rxcorrection "$vif" rxcorrection
		[ -n "$rxcorrection" ] && "$device_if" "$ifname" rxcorrection "$rxcorrection"

		config_get vsp_enable "$vif" vsp_enable
		[ -n "$vsp_enable" ] && "$device_if" "$ifname" vsp_enable "$vsp_enable"

                config_get qdf_cv_lvl "$vif" qdf_cv_lvl
                [ -n "$qdf_cv_lvl" ] && "$device_if" "$ifname" qdf_cv_lvl "$qdf_cv_lvl"

		config_get mode "$vif" mode
		if [ $mode = "sta" ]; then
			config_get ssid "$vif" ssid
				[ -n "$ssid" ] && {
					cfg80211tool "$ifname" ssid  "$ssid"
				}
		fi

		config_get txqueuelen "$vif" txqueuelen
		[ -n "$txqueuelen" ] && ifconfig "$ifname" txqueuelen "$txqueuelen"

		net_cfg="$(find_net_config "$vif")"

		config_get mtu $net_cfg mtu

		[ -n "$mtu" ] && {
				config_set "$vif" mtu $mtu
				ifconfig "$ifname" mtu $mtu
		}

		config_get tdls "$vif" tdls
		[ -n "$tdls" ] && "$device_if" "$ifname" tdls "$tdls"

		config_get set_tdls_rmac "$vif" set_tdls_rmac
		[ -n "$set_tdls_rmac" ] && "$device_if" "$ifname" set_tdls_rmac "$set_tdls_rmac"

		config_get tdls_qosnull "$vif" tdls_qosnull
		[ -n "$tdls_qosnull" ] && "$device_if" "$ifname" tdls_qosnull "$tdls_qosnull"

		config_get tdls_uapsd "$vif" tdls_uapsd
		[ -n "$tdls_uapsd" ] && "$device_if" "$ifname" tdls_uapsd "$tdls_uapsd"

		config_get tdls_set_rcpi "$vif" tdls_set_rcpi
		[ -n "$tdls_set_rcpi" ] && "$device_if" "$ifname" set_rcpi "$tdls_set_rcpi"

		config_get tdls_set_rcpi_hi "$vif" tdls_set_rcpi_hi
		[ -n "$tdls_set_rcpi_hi" ] && "$device_if" "$ifname" set_rcpihi "$tdls_set_rcpi_hi"

		config_get tdls_set_rcpi_lo "$vif" tdls_set_rcpi_lo
		[ -n "$tdls_set_rcpi_lo" ] && "$device_if" "$ifname" set_rcpilo "$tdls_set_rcpi_lo"

		config_get tdls_set_rcpi_margin "$vif" tdls_set_rcpi_margin
		[ -n "$tdls_set_rcpi_margin" ] && "$device_if" "$ifname" set_rcpimargin "$tdls_set_rcpi_margin"

		config_get tdls_dtoken "$vif" tdls_dtoken
		[ -n "$tdls_dtoken" ] && "$device_if" "$ifname" tdls_dtoken "$tdls_dtoken"

		config_get do_tdls_dc_req "$vif" do_tdls_dc_req
		[ -n "$do_tdls_dc_req" ] && "$device_if" "$ifname" do_tdls_dc_req "$do_tdls_dc_req"

		config_get tdls_auto "$vif" tdls_auto
		[ -n "$tdls_auto" ] && "$device_if" "$ifname" tdls_auto "$tdls_auto"

		config_get tdls_off_timeout "$vif" tdls_off_timeout
		[ -n "$tdls_off_timeout" ] && "$device_if" "$ifname" off_timeout "$tdls_off_timeout"

		config_get tdls_tdb_timeout "$vif" tdls_tdb_timeout
		[ -n "$tdls_tdb_timeout" ] && "$device_if" "$ifname" tdb_timeout "$tdls_tdb_timeout"

		config_get tdls_weak_timeout "$vif" tdls_weak_timeout
		[ -n "$tdls_weak_timeout" ] && "$device_if" "$ifname" weak_timeout "$tdls_weak_timeout"

		config_get tdls_margin "$vif" tdls_margin
		[ -n "$tdls_margin" ] && "$device_if" "$ifname" tdls_margin "$tdls_margin"

		config_get tdls_rssi_ub "$vif" tdls_rssi_ub
		[ -n "$tdls_rssi_ub" ] && "$device_if" "$ifname" tdls_rssi_ub "$tdls_rssi_ub"

		config_get tdls_rssi_lb "$vif" tdls_rssi_lb
		[ -n "$tdls_rssi_lb" ] && "$device_if" "$ifname" tdls_rssi_lb "$tdls_rssi_lb"

		config_get tdls_path_sel "$vif" tdls_path_sel
		[ -n "$tdls_path_sel" ] && "$device_if" "$ifname" tdls_pathSel "$tdls_path_sel"

		config_get tdls_rssi_offset "$vif" tdls_rssi_offset
		[ -n "$tdls_rssi_offset" ] && "$device_if" "$ifname" tdls_rssi_o "$tdls_rssi_offset"

		config_get tdls_path_sel_period "$vif" tdls_path_sel_period
		[ -n "$tdls_path_sel_period" ] && "$device_if" "$ifname" tdls_pathSel_p "$tdls_path_sel_period"

		config_get tdlsmacaddr1 "$vif" tdlsmacaddr1
		[ -n "$tdlsmacaddr1" ] && "$device_if" "$ifname" tdlsmacaddr1 "$tdlsmacaddr1"

		config_get tdlsmacaddr2 "$vif" tdlsmacaddr2
		[ -n "$tdlsmacaddr2" ] && "$device_if" "$ifname" tdlsmacaddr2 "$tdlsmacaddr2"

		config_get tdlsaction "$vif" tdlsaction
		[ -n "$tdlsaction" ] && "$device_if" "$ifname" tdlsaction "$tdlsaction"

		config_get tdlsoffchan "$vif" tdlsoffchan
		[ -n "$tdlsoffchan" ] && "$device_if" "$ifname" tdlsoffchan "$tdlsoffchan"

		config_get tdlsswitchtime "$vif" tdlsswitchtime
		[ -n "$tdlsswitchtime" ] && "$device_if" "$ifname" tdlsswitchtime "$tdlsswitchtime"

		config_get tdlstimeout "$vif" tdlstimeout
		[ -n "$tdlstimeout" ] && "$device_if" "$ifname" tdlstimeout "$tdlstimeout"

		config_get tdlsecchnoffst "$vif" tdlsecchnoffst
		[ -n "$tdlsecchnoffst" ] && "$device_if" "$ifname" tdlsecchnoffst "$tdlsecchnoffst"

		config_get tdlsoffchnmode "$vif" tdlsoffchnmode
		[ -n "$tdlsoffchnmode" ] && "$device_if" "$ifname" tdlsoffchnmode "$tdlsoffchnmode"

		config_get_bool blockdfschan "$vif" blockdfschan
		[ -n "$blockdfschan" ] && "$device_if" "$ifname" blockdfschan "$blockdfschan"

		config_get dbgLVL "$vif" dbgLVL
		[ -n "$dbgLVL" ] && "$device_if" "$ifname" dbgLVL "$dbgLVL"

		config_get dbgLVL_high "$vif" dbgLVL_high
		[ -n "$dbgLVL_high" ] && "$device_if" "$ifname" dbgLVL_high "$dbgLVL_high"

		config_get csl "$vif" csl
		[ -n "$csl" ] && "$device_if" "$ifname" csl "$csl"

		config_get acsmindwell "$vif" acsmindwell
		[ -n "$acsmindwell" ] && "$device_if" "$ifname" acsmindwell "$acsmindwell"

		config_get acsmaxdwell "$vif" acsmaxdwell
		[ -n "$acsmaxdwell" ] && "$device_if" "$ifname" acsmaxdwell "$acsmaxdwell"

		config_get acsreport "$vif" acsreport
		[ -n "$acsreport" ] && "$device_if" "$ifname" acsreport "$acsreport"

		config_get ch_hop_en "$vif" ch_hop_en
		[ -n "$ch_hop_en" ] && "$device_if" "$ifname" ch_hop_en "$ch_hop_en"

		config_get ch_long_dur "$vif" ch_long_dur
		[ -n "$ch_long_dur" ] && "$device_if" "$ifname" ch_long_dur "$ch_long_dur"

		config_get ch_nhop_dur "$vif" ch_nhop_dur
		[ -n "$ch_nhop_dur" ] && "$device_if" "$ifname" ch_nhop_dur "$ch_nhop_dur"

		config_get ch_cntwn_dur "$vif" ch_cntwn_dur
		[ -n "$ch_cntwn_dur" ] && "$device_if" "$ifname" ch_cntwn_dur "$ch_cntwn_dur"

		config_get ch_noise_th "$vif" ch_noise_th
		[ -n "$ch_noise_th" ] && "$device_if" "$ifname" ch_noise_th "$ch_noise_th"

		config_get ch_cnt_th "$vif" ch_cnt_th
		[ -n "$ch_cnt_th" ] && "$device_if" "$ifname" ch_cnt_th "$ch_cnt_th"

		config_get_bool scanchevent "$vif" scanchevent
		[ -n "$scanchevent" ] && "$device_if" "$ifname" scanchevent "$scanchevent"

		config_get_bool send_add_ies "$vif" send_add_ies
		[ -n "$send_add_ies" ] && "$device_if" "$ifname" send_add_ies "$send_add_ies"

		config_get enable_rtt "$vif" enable_rtt
		[ -n "$enable_rtt" ] && "$device_if" "$ifname" enable_rtt "$enable_rtt"

		config_get_bool enable_lci "$vif" enable_lci
		[ -n "$enable_lci" ] && "$device_if" "$ifname" enable_lci "$enable_lci"

		config_get_bool enable_lcr "$vif" enable_lcr
		[ -n "$enable_lcr" ] && "$device_if" "$ifname" enable_lcr "$enable_lcr"

		config_get_bool rrm "$vif" rrm
		[ -n "$rrm" ] && "$device_if" "$ifname" rrm "$rrm"

		config_get_bool rrmslwin "$vif" rrmslwin
		[ -n "$rrmslwin" ] && "$device_if" "$ifname" rrmslwin "$rrmslwin"

		config_get_bool rrmstats "$vif" rrmsstats
		[ -n "$rrmstats" ] && "$device_if" "$ifname" rrmstats "$rrmstats"

		config_get rrmdbg "$vif" rrmdbg
		[ -n "$rrmdbg" ] && "$device_if" "$ifname" rrmdbg "$rrmdbg"

		config_get_bool rrm_capie "$vif" rrm_capie
		[ -n "$rrm_capie" ] && "$device_if" "$ifname" rrm_capie "$rrm_capie"

		config_get acparams "$vif" acparams
		[ -n "$acparams" ] && "$device_if" "$ifname" acparams $acparams

		config_get setwmmparams "$vif" setwmmparams
		[ -n "$setwmmparams" ] && "$device_if" "$ifname" setwmmparams $setwmmparams

		config_get_bool qbssload "$vif" qbssload
		[ -n "$qbssload" ] && "$device_if" "$ifname" qbssload "$qbssload"

		config_get_bool proxyarp "$vif" proxyarp
		[ -n "$proxyarp" ] && "$device_if" "$ifname" proxyarp "$proxyarp"

		config_get_bool dgaf_disable "$vif" dgaf_disable
		[ -n "$dgaf_disable" ] && "$device_if" "$ifname" dgaf_disable "$dgaf_disable"

		config_get setibssdfsparam "$vif" setibssdfsparam
		[ -n "$setibssdfsparam" ] && "$device_if" "$ifname" setibssdfsparam "$setibssdfsparam"

		config_get startibssrssimon "$vif" startibssrssimon
		[ -n "$startibssrssimon" ] && "$device_if" "$ifname" startibssrssimon "$startibssrssimon"

		config_get setibssrssihyst "$vif" setibssrssihyst
		[ -n "$setibssrssihyst" ] && "$device_if" "$ifname" setibssrssihyst "$setibssrssihyst"

		config_get noIBSSCreate "$vif" noIBSSCreate
		[ -n "$noIBSSCreate" ] && "$device_if" "$ifname" noIBSSCreate "$noIBSSCreate"

		config_get setibssrssiclass "$vif" setibssrssiclass
		[ -n "$setibssrssiclass" ] && "$device_if" "$ifname" setibssrssiclass $setibssrssiclass

		config_get offchan_tx_test "$vif" offchan_tx_test
		[ -n "$offchan_tx_test" ] && "$device_if" "$ifname" offchan_tx_test $offchan_tx_test

		handle_vow_dbg_cfg() {
			local value="$1"
			[ -n "$value" ] && "$device_if" "$ifname" vow_dbg_cfg $value
		}

		config_list_foreach "$vif" vow_dbg_cfg handle_vow_dbg_cfg

		config_get_bool vow_dbg "$vif" vow_dbg
		[ -n "$vow_dbg" ] && "$device_if" "$ifname" vow_dbg "$vow_dbg"
#TODO
		handle_set_max_rate() {
			local value="$1"
			[ -n "$value" ] && wlanconfig "$ifname" set_max_rate $value -cfg80211
		}
		config_list_foreach "$vif" set_max_rate handle_set_max_rate

		# miwifi
		config_get txbf "$device" txbf
		if [ "$mode" != "sta" ]; then
			if [ "$txbf" -eq 0 ]; then
				"$device_if" "$ifname" vhtmubfer 0
				"$device_if" "$ifname" he_mubfer 0
				"$device_if" "$ifname" he_ulmumimo 0
				"$device_if" "$ifname" set_eht_mu_bfmr 0
				"$device_if" "$ifname" set_eht_ulmumimo 0
			else
				"$device_if" "$ifname" vhtmubfer 1
				"$device_if" "$ifname" he_mubfer 1
				"$device_if" "$ifname" he_ulmumimo 1
				"$device_if" "$ifname" set_eht_mu_bfmr 3
				"$device_if" "$ifname" set_eht_ulmumimo 3
			fi
		fi

		config_get_bool implicitbf "$vif" implicitbf
		[ -n "$implicitbf" ] && "$device_if" "$ifname" implicitbf "${implicitbf}"

		config_get_bool vhtsubfee "$vif" vhtsubfee
		[ -n "$vhtsubfee" ] && "$device_if" "$ifname" vhtsubfee "${vhtsubfee}"

		config_get_bool vhtmubfee "$vif" vhtmubfee
		[ -n "$vhtmubfee" ] && "$device_if" "$ifname" vhtmubfee "${vhtmubfee}"

		config_get_bool vhtsubfer "$vif" vhtsubfer
		[ -n "$vhtsubfer" ] && "$device_if" "$ifname" vhtsubfer "${vhtsubfer}"

		config_get_bool vhtmubfer "$vif" vhtmubfer
		[ -n "$vhtmubfer" ] && "$device_if" "$ifname" vhtmubfer "${vhtmubfer}"

		config_get vhtstscap "$vif" vhtstscap
		[ -n "$vhtstscap" ] && "$device_if" "$ifname" vhtstscap "${vhtstscap}"

		config_get vhtsounddim "$vif" vhtsounddim
		[ -n "$vhtsounddim" ] && "$device_if" "$ifname" vhtsounddim "${vhtsounddim}"

		config_get enable_11v_dms "$vif" enable_11v_dms
		[ -n "$enable_11v_dms" ] && "$device_if" "$ifname" enable_11v_dms "${enable_11v_dms}"

		config_get he_dcm "$vif" he_dcm
		[ -n "$he_dcm" ] && "$device_if" "$ifname" he_dcm "${he_dcm}"

		config_get he_extrange "$vif" he_extrange
		[ -n "$he_extrange" ] && "$device_if" "$ifname" he_extrange "${he_extrange}"

		config_get he_ltf "$vif" he_ltf
		[ -n "$he_ltf" ] && "$device_if" "$ifname" he_ltf "${he_ltf}"

		config_get he_txmcsmap "$vif" he_txmcsmap
		[ -n "$he_txmcsmap" ] && "$device_if" "$ifname" he_txmcsmap "${he_txmcsmap}"

		config_get he_rxmcsmap "$vif" he_rxmcsmap
		[ -n "$he_rxmcsmap" ] && "$device_if" "$ifname" he_rxmcsmap "${he_rxmcsmap}"

		config_get set_eht_su_bfmr "$vif" set_eht_su_bfmr
		[ -n "$set_eht_su_bfmr" ] && "$device_if" "$ifname" set_eht_su_bfmr "${set_eht_su_bfmr}"

		config_get set_eht_su_bfme "$vif" set_eht_su_bfme
		[ -n "$set_eht_su_bfme" ] && "$device_if" "$ifname" set_eht_su_bfme "${set_eht_su_bfme}"

		config_get ba_bufsize "$vif" ba_bufsize
		[ -n "$ba_bufsize" ] && "$device_if" "$ifname" ba_bufsize "${ba_bufsize}"

		config_get encap_type "$vif" encap_type
		[ -n "$encap_type" ] && "$device_if" "$ifname" encap_type "${encap_type}"

		config_get decap_type "$vif" decap_type
		[ -n "$decap_type" ] && "$device_if" "$ifname" decap_type "${decap_type}"

		config_get rawsim_txagr "$vif" rawsim_txagr
		[ -n "$rawsim_txagr" ] && "$device_if" "$ifname" rawsim_txagr "${rawsim_txagr}"

		config_get clr_rawsim_stats "$vif" clr_rawsim_stats
		[ -n "$clr_rawsim_stats" ] && "$device_if" "$ifname" clr_rawsim_stats "${clr_rawsim_stats}"

		config_get rawsim_debug "$vif" rawsim_debug
		[ -n "$rawsim_debug" ] && "$device_if" "$ifname" rawsim_debug "${rawsim_debug}"

		config_get rsim_en_frmcnt "$vif" rsim_en_frmcnt
		[ -n "$rsim_en_frmcnt" ] && "$device_if" "$ifname" rsim_en_frmcnt "${rsim_en_frmcnt}"

		config_get rsim_de_frmcnt "$vif" rsim_de_frmcnt
		[ -n "$rsim_de_frmcnt" ] && "$device_if" "$ifname" rsim_de_frmcnt "${rsim_de_frmcnt}"

		config_get set_monrxfilter "$vif" set_monrxfilter
		[ -n "$set_monrxfilter" ] && "$device_if" "$ifname" set_monrxfilter "${set_monrxfilter}"

		config_get neighbourfilter "$vif" neighbourfilter
		[ -n "$neighbourfilter" ] && "$device_if" "$ifname" neighbourfilter "${neighbourfilter}"

		config_get athnewind "$vif" athnewind
		[ -n "$athnewind" ] && "$device_if" "$ifname" athnewind "$athnewind"

		config_get osen "$vif" osen
		[ -n "$osen" ] && "$device_if" "$ifname" osen "$osen"

		if [ ! -z $osen]; then
			if [ $osen -ne 0 ]; then
				"$device_if" "$ifname" proxyarp 1
			fi
		fi

		config_get re_scalingfactor "$vif" re_scalingfactor
		[ -n "$re_scalingfactor" ] && cfg80211tool_mesh "$ifname" set_whc_sfactor "$re_scalingfactor"

		config_get ul_hyst "$vif" ul_hyst
		[ -n "$ul_hyst" ] && cfg80211tool_mesh "$ifname" ul_hyst "${ul_hyst}"

		config_get son_event_bcast qcawifi son_event_bcast
		[ -n "$son_event_bcast" ] && cfg80211tool_mesh "$ifname" son_event_bcast "${son_event_bcast}"

		config_get root_distance "$vif" root_distance
		[ -n "$root_distance" ] && cfg80211tool_mesh "$ifname" set_whc_dist "$root_distance"

		config_get caprssi "$vif" caprssi
		[ -n "$caprssi" ] && cfg80211tool_mesh "$ifname" caprssi "${caprssi}"

		config_get_bool ap_isolation_enabled $device ap_isolation_enabled 0
		config_get_bool isolate "$vif" isolate 0

		if [ $ap_isolation_enabled -ne 0 ]; then
			[ "$mode" = "wrap" ] && isolate=1
			"$device_if" "$phy" isolation "$ap_isolation_enabled"
		fi

                config_get_bool ctsprt_dtmbcn "$vif" ctsprt_dtmbcn
                [ -n "$ctsprt_dtmbcn" ] && "$device_if" "$ifname" ctsprt_dtmbcn "${ctsprt_dtmbcn}"

		config_get assocwar160  "$vif" assocwar160
		[ -n "$assocwar160" ] && "$device_if" "$ifname" assocwar160 "$assocwar160"

		config_get rawdwepind "$vif" rawdwepind
		[ -n "$rawdwepind" ] && "$device_if" "$ifname" rawdwepind "$rawdwepind"

		config_get revsig160  "$vif" revsig160
		[ -n "$revsig160" ] && "$device_if" "$ifname" revsig160 "$revsig160"

		config_get channel_block_list "$vif" channel_block_list
		[ -n "$channel_block_list" ] && wifitool "$ifname" block_acs_channel "$channel_block_list"

		config_get custom_chan_list "$vif" custom_chan_list
		[ -n "$custom_chan_list" ] && wifitool "$ifname" custom_chan_list $(printf "%s \n" $custom_chan_list)


		config_get cactimeout  "$vif" cactimeout
		[ -n "$cactimeout" ] && "$device_if" "$ifname" set_cactimeout "$cactimeout"

		config_get meshdbg "$vif" meshdbg
		[ -n "$meshdbg" ] && "$device_if" "$ifname" meshdbg "$meshdbg"

		config_get rmode_pktsim "$vif" rmode_pktsim
		[ -n "$rmode_pktsim" ] && "$device_if" "$ifname" rmode_pktsim "$rmode_pktsim"

		config_get spl_vap_scan "$vif" spl_vap_scan
		[ -n "$spl_vap_scan" ] && "$device_if" "$ifname" spl_vap_scan "$spl_vap_scan"

		config_get advertise_ap_maxcap "$vif" advertise_ap_maxcap
		[ -n "$advertise_ap_maxcap" ] && "$device_if" "$ifname" advertise_ap_maxcap "$advertise_ap_maxcap"

		config_get hlos_tidoverride "$vif" hlos_tidoverride 0
		if [ "$hlos_tidoverride" -eq 1 ]; then
			[ -d /sys/module/qca-nss-mscs ] || insmod_cmd qca-nss-mscs
			echo "Inserting ecm-wifi-plugin"
			[ -d /sys/module/ecm_wifi_plugin ] || insmod_cmd ecm-wifi-plugin
		fi

		[ -n "$hlos_tidoverride" ] && "$device_if" "$ifname" hlos_tidoverride "$hlos_tidoverride"

		config_get mscs "$vif" mscs 0
		if [ "$mscs" -eq 1 ]; then
			[ -d /sys/module/qca-nss-mscs ] || insmod_cmd qca-nss-mscs
			[ -d /sys/module/ecm_wifi_plugin ] || insmod_cmd ecm-wifi-plugin
			echo 1 > /sys/kernel/debug/ecm/ecm_classifier_mscs/enabled
		fi
		[ -n "$mscs" ] && "$device_if" "$ifname" mscs "$mscs"

		config_get scs "$vif" scs 0
		if [ "$scs" -eq 1 ]; then
			[ -d /sys/module/ecm_wifi_plugin ] || insmod_cmd ecm-wifi-plugin
			echo 1 > /sys/kernel/debug/ecm/ecm_classifier_mscs/scs_enabled
			echo 0 > /sys/kernel/debug/ecm/ecm_classifier_dscp/enabled
			echo 5200 > /sys/kernel/debug/ecm/ecm_classifier_mscs/udp_ipsec_port
			if ! pgrep -x "scs_tool" > /dev/null
			then
				scs_tool &
			fi
		fi
		[ -n "$scs" ] && "$device_if" "$ifname" scs "$scs"

		config_get sawf qcawifi sawf
		if [ "$sawf" -eq 1 ]; then
			echo 3 > /sys/kernel/debug/ecm/ecm_classifier_emesh/sawf_enabled
			echo 0 > /sys/kernel/debug/ecm/ecm_classifier_dscp/enabled
		fi

		config_get drop_tx_mcast "$vif" drop_tx_mcast
		[ -n "$drop_tx_mcast" ] && "$device_if" "$ifname" drop_tx_mcast "$drop_tx_mcast"

		config_get dscp_action_policy "$vif" dscp_action_policy 0
		[ -n "$dscp_action_policy" ] && "$device_if" "$ifname" dscp_action_policy "$dscp_action_policy"

                config_get global_wds qcawifi global_wds

		if [ ! -z $global_wds ]; then
			if [ $global_wds -ne 0 ]; then
			"$device_if" "$ifname" athnewind 1
			fi
		fi

                config_get pref_uplink "$device" pref_uplink
                [ -n "$pref_uplink" ] && "$device_if" "$phy" pref_uplink "${pref_uplink}"

                config_get fast_lane "$device" fast_lane
                [ -n "$fast_lane" ] && "$device_if" "$phy" fast_lane "${fast_lane}"

		if [ ! -z $fast_lane ]; then
			if [ $fast_lane -ne 0 ]; then
			"$device_if" "$ifname" athnewind 1
			fi
		fi

		if [ ! -z "$vifs_name" ]; then
			break
		fi
	done
}

start_vifs_qcawificfg80211() {
	local device="$1"
	local vifs_name="$3"
	local vif="$2"
	local flag=0
	local force_hostapd_attach

	local board_name
	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	config_get phy "$device" phy
	config_get device_if "$device" device_if "cfg80211tool"
	config_get band "$device" band 0
	config_get htmode "$device" htmode auto
	config_get channel "$device" channel 0
	[ auto = "$channel" ] && channel=0
	[ AUTO = "$channel" ] && channel=0

	config_get ifname "$vif" ifname
	if [ ! -z "$vifs_name" ]; then
		for tmp_vap in $vifs_name; do
			if [ $tmp_vap = $ifname ]; then
				flag=1
				break
			else
				continue
			fi
		done
		if [ $flag = 0 ]; then
			return
		fi
	fi

	case "$board_name" in
	ap-sdxlemur*) config_get force_hostapd_attach qcawifi force_hostapd_attach 0 ;;
	*) force_hostapd_attach=1 ;;
	esac
	config_set "$device" force_hostapd_attach "$force_hostapd_attach"

	local start_hostapd= vif_txpower=
	config_get ifname "$vif" ifname
	config_get mode "$vif" mode
	config_get enc "$vif" encryption "none"
	enc=$(echo $enc | awk '{ print tolower($0) }')
	config_get_bool disabled "$vif" disabled 0
	[ $disabled = 0 ] || return

	config_set "$vif" ifname "$ifname"

	config_get_bool ap_isolation_enabled $device ap_isolation_enabled 0
	config_get_bool isolate "$vif" isolate 0

	if [ $ap_isolation_enabled -ne 0 ]; then
		[ "$mode" = "wrap" ] && isolate=1
	fi

	mld_netdev=1
	local net_cfg bridge
	case "$board_name" in
	ap-sdxlemur*)
		if [ "$force_hostapd_attach" -eq 1 ]; then
			# In SDX boards, bridge is "bridge0" and netifd is not present.
			# Hence, set the bridge and add $ifname to bridge manually when
			# override option is set
			bridge=bridge0
			config_set "$vif" bridge "$bridge"
			echo "Adding $ifname to bridge $bridge" > /dev/console
			brctl addif $bridge $ifname
		fi
	;;
	ap-sdxpinn*)
		net_cfg="$(find_net_config "$vif")"
			[[ -z "$net_cfg" ] -o [ "$isolate" = 1 -a "$mode" = "wrap" ]] || {
			[ -f /sys/class/net/${ifname}/parent ] && { \
				bridge_json="$(bridge_interface "$net_cfg")"
				json_load "$bridge_json"
				json_get_var bridge bridge
				config_set "$vif" bridge "$bridge"
			}
		}
	;;
	*)
		net_cfg="$(find_net_config "$vif")"
			[[ -z "$net_cfg" ] -o [ "$isolate" = 1 -a "$mode" = "wrap" ]] || {
			[ -f /sys/class/net/${ifname}/parent ] && { \
				bridge="$(bridge_interface "$net_cfg")"
				if [ $mld_netdev == 1 ]; then
					local mldev_mode
					local ini_path
					ini_path=$(get_config_file_path "ini")
					mldev_mode="$(grep "mldev_mode_ap" \
						$ini_path/global.ini | awk -F '=' '{print $2}')"
					# Expose link netdevs to bridge only for hybrid mlo mode
					if [ $mldev_mode -eq 2 ]; then
						config_set "$vif" bridge "$bridge"
					else
						config_get ifmld "$vif" mld
						if [ -z $ifmld ]; then
							config_set "$vif" bridge "$bridge"
						fi
					fi
				else
					config_set "$vif" bridge "$bridge"
				fi
			}
		}
	;;
	esac

	config_get all_vifs "$device" vifs
	for map_vif in $all_vifs; do
		config_get MapBSSType "$map_vif" MapBSSType

		# MapBSSType 64, vap is backhaul BSS
		if [ $(($((MapBSSType&64)) >> 6)) -eq 1 ]; then
			backhaul_BSS=1 # The radio has a backhaul BSS vap configured
			config_get backhaul_ssid "$map_vif" ssid
			config_get backhaul_key "$map_vif" key
			break;
		fi
	done

	case "$enc" in
		wapi*)
			start_wapid=1
			config_get key "$vif" key
		;;
		wep*|mixed*|psk*|ccm*|gcm*|wpa*|8021x|sae*|dpp*)
			start_hostapd=1
			config_get key "$vif" key
		;;
		*)
		# We start hostapd in open mode too
			start_hostapd=1
		;;
	esac

	case "$mode" in
		ap|wrap|ap_smart_monitor|mesh|ap_lp_iot)
			local vendorie_cmd

			"$device_if" "$ifname" ap_bridge "$((isolate^1))"

			config_get_bool l2tif "$vif" l2tif
			[ -n "$l2tif" ] && "$device_if" "$ifname" l2tif "$l2tif"

			if [ -n "$start_wapid" ]; then
				wapid_setup_vif "$vif" nl80211 || {
					echo "enable_qcawifi($device): Failed to set up wapid for interface $ifname" >&2
					ifconfig "$ifname" down
					iw "$ifname" del
					return
				}
			fi

			if [ "$mode" == "ap_lp_iot" ]; then
				default_dtim_period=41
			else
				default_dtim_period=1
			fi
			config_get dtim_period "$vif" dtim_period
			if [ -z "$dtim_period" ]; then
				config_set "$vif" dtim_period $default_dtim_period
			fi

			## XP-29788,XP-30004. cfg 165 20M ; vifs init fail
			## hostapd_setup_vif will use htmode, we should rewrite it before
			config_set "$device" htmode "$htmode"

			if [ -n "$start_hostapd" ] && eval "type hostapd_setup_vif" 2>/dev/null >/dev/null; then
				# If the radio has a backhaul BSS configured, call hostapd_setup_vif() with the
				# backhaul BSS credentials, so that the backhaul BSS credentials get configured
				# for all fronthaul VAPS
				if [ ! -z $backhaul_BSS ]; then
					if [ "$backhaul_BSS" -eq 1 ]; then
						hostapd_setup_vif "$vif" nl80211 no_nconfig bBSS "$backhaul_ssid" "$backhaul_key" || {
						echo "start_qcawifi($device): Failed to set up hostapd for interface $ifname" >&2
						# make sure this wifi interface won't accidentally stay open without encryption
						ifconfig "$ifname" down
						iw "$ifname" del
						return
						}
					else
						hostapd_setup_vif "$vif" nl80211 no_nconfig || {
							echo "start_qcawifi($device): Failed to set up hostapd for interface $ifname" >&2
							# make sure this wifi interface won't accidentally stay open without encryption
							ifconfig "$ifname" down
							iw "$ifname" del
						return
						}

					fi
				else
					hostapd_setup_vif "$vif" nl80211 no_nconfig || {
						echo "start_qcawifi($device): Failed to set up hostapd for interface $ifname" >&2
						# make sure this wifi interface won't accidentally stay open without encryption
						ifconfig "$ifname" down
						iw "$ifname" del
						return
					}
					do_acs_wait
				fi
				config_get vendorie_cmd "$vif" vendorie_cmd
				if [ -n "$vendorie_cmd" ]; then

					add_vendorie() {
						local oui=$1
						local pcap_data=$2
						local ftype_map=$3
						local len=$(expr "${#oui}" + "${#pcap_data}")
						len=$(expr "$len" / 2)
						wlanconfig "$ifname" vendorie add len "$len" oui "$oui" pcap_data "$pcap_data" ftype_map "$ftype_map"
					}

					for data in $vendorie_cmd; do
						data=$(echo $data | tr "," " ")
						add_vendorie $data
					done
				fi
			fi
		;;
		wds|sta)
			if eval "type wpa_supplicant_setup_vif" 2>/dev/null >/dev/null; then
				wpa_supplicant_setup_vif "$vif" nl80211 || {
					echo "start_qcawifi($device): Failed to set up wpa_supplicant for interface $ifname" >&2
					ifconfig "$ifname" down
					iw "$ifname" del
					return
				}
			fi
			# to fix wireless and wired loop problem
			__bhsta_check "$vif" "$ifname"
		;;
		adhoc)
			if eval "type wpa_supplicant_setup_vif" 2>/dev/null >/dev/null; then
				wpa_supplicant_setup_vif "$vif" nl80211 || {
					echo "start_qcawifi($device): Failed to set up wpa"
					ifconfig "$ifname" down
					iw "$ifname" del
					return
				}
			fi
	esac

	[ -z "$bridge" -o "$isolate" = 1 -a "$mode" = "wrap" ] || {
              [ -f /sys/class/net/${ifname}/parent ] && { \
			if [ $mld_netdev == 1 ]; then
				local mldev_mode
				local ini_path
				ini_path=$(get_config_file_path "ini")
				mldev_mode="$(grep "mldev_mode_ap" \
						$ini_path/global.ini | awk -F '=' '{print $2}')"
				if [ $mldev_mode -eq 2 ]; then
					start_net "$ifname" "$net_cfg"
				else
					config_get ifmld "$vif" mld
					if [ -z $ifmld ]; then
						start_net "$ifname" "$net_cfg"
					fi
				fi
			else
				start_net "$ifname" "$net_cfg"
			fi
              }
	}

	ifconfig "$ifname" up
	set_wifi_up "$vif" "$ifname"

	case "$board_name" in
	ap-sdxpinn*)
		local link_local_ipaddr
		config_get link_local_ipaddr "$vif" ipaddr
		if [ -n "$link_local_ipaddr" ]; then
			# Assign link local IP addresses to athX on SDX75 targets
			ifconfig "$ifname" "$link_local_ipaddr" netmask 255.255.255.0
		fi
	;;
	esac

	# configure below options once AP is up , as wireless mode is available now
	config_get frag "$vif" frag
	[ -n "$frag" ] && iw phy "$(cat /sys/class/net/$phy/phy80211/name)"  set frag "${frag%%.*}"

	# Support added for per vap RTS setting using private command in cfg80211 mode
	# But cfg80211tool will take rts parameter as integer.
        # MAX farme size, MAX RTS Threshold i.e 2347, is set to make RTS/CTS protection off.
	config_get rts "$vif" rts
	if [ "$rts" == "off" ]; then
		"$device_if" "$ifname" rts 2347
	else
		[ -n "$rts" ] && "$device_if" "$ifname" rts "${rts%%.*}"
	fi

	config_get set11NRates "$vif" set11NRates
	[ -n "$set11NRates" ] && "$device_if" "$ifname" set11NRates "$set11NRates"

	config_get setwmmparams "$vif" setwmmparams
	[ -n "$setwmmparams" ] && "$device_if" "$ifname" setwmmparams $setwmmparams

	# 256 QAM capability needs to be parsed first, since
	# vhtmcs enables/disable rate indices 8, 9 for 2G
	# only if vht_11ng is set or not
	config_get_bool vht_11ng "$vif" vht_11ng
	[ -n "$vht_11ng" ] && "$device_if" "$ifname" vht_11ng "$vht_11ng"

	config_get_bool vhtintop "$vif" vhtintop
	[ -n "$vhtintop" ] && "$device_if" "$ifname" 11ngvhtintop "$vhtintop"

	config_get vhtmcs "$vif" vhtmcs
	[ -n "$vhtmcs" ] && "$device_if" "$ifname" vhtmcs "$vhtmcs"

	config_get dis_legacy "$vif" dis_legacy
	[ -n "$dis_legacy" ] && "$device_if" "$ifname" dis_legacy "$dis_legacy"

	config_get ext_nss "$device" ext_nss
	case "$ext_nss" in
		1|on|enabled) "$device_if" "$phy" ext_nss 1 >/dev/null 2>&1
			;;
		0|on|enabled) "$device_if" "$phy" ext_nss 0 >/dev/null 2>&1
			;;
		*) ;;
	esac

	config_get ext_nss_sup "$vif" ext_nss_sup
	case "$ext_nss_sup" in
		1|on|enabled) "$device_if" "$ifname" ext_nss_sup 1 >/dev/null 2>&1
			;;
		0|on|enabled) "$device_if" "$ifname" ext_nss_sup 0 >/dev/null 2>&1
			;;
		*) ;;
	esac

	config_get mbo "$vif" mbo
	[ -n "$mbo" ] && "$device_if" "$ifname" mbo "$mbo"

	if [ $mode = "sta" ]; then
		config_get enable_ft "$vif" ieee80211r
		[ -n "$enable_ft" ] && "$device_if" "$ifname" ft "$enable_ft"
	fi

	config_get enable_fils "$vif" ieee80211ai
	config_get fils_discovery_period  "$vif" fils_fd_period 20
	[ -n "$enable_fils" ] && "$device_if" "$ifname" enable_fils "$enable_fils" "$fils_discovery_period"

	config_get bpr_enable  "$vif" bpr_enable
	[ -n "$bpr_enable" ] && "$device_if" "$ifname" set_bpr_enable "$bpr_enable"

	config_get oce "$vif" oce
	[ -n "$oce" ] && "$device_if" "$ifname" oce "$oce"

	if [ ! -z $oce ]; then
		[ "$oce" -gt 0 ] && {

			config_get prb_retry  "$vif" prb_retry 2
			"$device_if" "$ifname" prb_retry "$prb_retry"

			case "$hwmode" in
				11B*|11G*|11NG*)
					"$device_if" "$ifname" set_bcn_rate 5500
					"$device_if" "$ifname" prb_rate 5500
					;;
				*)
					;;
			esac

			[ -z "$enable_fils" ] && {
				config_get fils_discovery_period  "$vif" fils_fd_period 20
				"$device_if" "$ifname" enable_fils 1 "$fils_discovery_period"
			}
		}
	fi

	config_get set_bcn_rate "$vif" set_bcn_rate
	[ -n "$set_bcn_rate" ] && "$device_if" "$ifname" set_bcn_rate "$set_bcn_rate"

	config_get mcast_rate "$vif" mcast_rate
	[ -n "$mcast_rate" ] && "$device_if" "$ifname" mcast_rate "${mcast_rate%%.*}"

	#support nawds
	config_get nawds_mode "$vif" nawds_mode
	[ -n "$nawds_mode" ] && wlanconfig "$ifname" nawds mode "${nawds_mode}" -cfg80211

	handle_nawds() {
		local value="$1"
		[ -n "$value" ] && wlanconfig "$ifname" nawds add-repeater $value -cfg80211
	}
	config_list_foreach "$vif" nawds_add_repeater handle_nawds

	handle_hmwds() {
		local value="$1"
		[ -n "$value" ] && wlanconfig "$ifname" hmwds add_addr $value -cfg80211
	}
	config_list_foreach "$vif" hmwds_add_addr handle_hmwds

	config_get nawds_override "$vif" nawds_override
	[ -n "$nawds_override" ] && wlanconfig "$ifname" nawds override "${nawds_override}" -cfg80211

	config_get nawds_defcaps "$vif" nawds_defcaps
	[ -n "$nawds_defcaps" ] && wlanconfig "$ifname" nawds defcaps "${nawds_defcaps}" -cfg80211

	handle_hmmc_add() {
		local value="$1"
		[ -n "$value" ] && wlanconfig "$ifname" hmmc add $value -cfg80211
	}
	config_list_foreach "$vif" hmmc_add handle_hmmc_add

	# TXPower settings only work if device is up already
	# while atheros hardware theoretically is capable of per-vif (even per-packet) txpower
	# adjustment it does not work with the current atheros hal/madwifi driver
	config_get vif_txpower "$vif" txpower
	config_get country "$device" country

	# use vif_txpower (from wifi-iface) instead of txpower (from wifi-device) if
	# the latter doesn't exist
	# txpower="${txpower:-$vif_txpower}"
	# [ -z "$txpower" ] || iw "$ifname" set txpower fixed "${txpower%%.*}"

	# for miwifi
	device_2g=$(uci -q get misc.wireless.if_2G)
	if [ "$device" = "$device_2g" ]; then 
		max_power=$(uci -q get misc.wireless.if_2g_maxpower)
		if [ -z "$max_power" ]; then
			max_power=30
		fi

		case "$board_name" in
			ap-al02-c6|ap-mi01.2)
				# dynamic edcca
				if [ "$country" == "CN" -o "$country" == "156" ]; then
					wifitool "$ifname" setUnitTestCmd 67 3 16 0 1
				fi
			;;
			ap-al02-c4)
				# fix dhcp frame rate to 6M, wkk firmware .30 or higher
				wifitool "$ifname" setUnitTestCmd 0x48 2 607 1
			;;
		esac

		"$device_if" "$ifname" 11ngvhtintop 1
		"$device_if" "$ifname" vht_mcs_10_11_nq2q_peer_supp 1
		"$device_if" "$ifname" vhtsubfee 0
		"$device_if" "$ifname" he_subfee 0
		#ppdu由2ms-->3ms,性能2G 40M：410-->447,参考运营商分支高通方案调整的参数，增加TXOP时间，提高报文聚合
		wifitool "$ifname" setUnitTestCmd 0x47 2 13 3000
	else
		max_power=$(uci -q get misc.wireless.if_5g_maxpower)

		if [ -z "$max_power" ]; then
			max_power=30
		fi

		# IOT issue with AC88
		"$device_if" "$ifname" vhtstscap 3
		# fix dhcp frame rate to 6M, wkk firmware .30 or higher
		wifitool "$ifname" setUnitTestCmd 0x48 2 607 1

		#5G MCS drop issue workaround
		wifitool "$ifname" setUnitTestCmd 67 5 1 0 16 12 5
		wifitool "$ifname" setUnitTestCmd 67 5 1 0 16 11 2
	fi

	# if max power is xx.5 dBm, max_power = 2 * maxpower + 256
	# plz make sure your driver support this special method.
	float_flag=$(echo $max_power | grep "\.5")
	max_power="${max_power%%.*}"

	config_get txpwr "$device" txpwr
	if [ "$txpwr" = "mid" ]; then
		txpower=`expr $max_power - 1`
	elif [ "$txpwr" = "min" ]; then
		txpower=`expr $max_power - 3`
	else
		txpower="$max_power"
	fi
	
	if [ "$float_flag" != "" ]; then
		txpower=`expr $txpower \* 2 + 1 + 256`
	fi

	if [ "$country" == "CN" -o "$country" == "156" ]; then
	txpower="${txpower:-$vif_txpower}"
		[ -z "$txpower" ] || iwconfig "$ifname" txpower "${txpower%%.*}"
	fi
	if [ $enable_rps_wifi == 1 ] && [ -f "/lib/update_system_params.sh" ]; then
		. /lib/update_system_params.sh
		enable_rps $ifname
	fi

	# for miwifi
	# set dyn_bw_rts of 5G band to 1,make sure the SA MAC of RTS package is write
	if [ "$device" != "$device_2g" ]; then
		"$device_if" "$ifname" dyn_bw_rts 1
	fi

	#for miwifi
	#low down power in re mesh mode
	local init_flag=$(uci -q get xiaoqiang.common.INITTED)
	local netmode=$(uci -q get xiaoqiang.common.NETMODE)
	local is_ftm=`cat /proc/xiaoqiang/ft_mode`
	if [ "$init_flag" != "YES" ] && [ "$is_ftm" != "1" ]; then
		if [ "$netmode" != "whc_cap" ]; then
			if [ "$device" != "$device_2g" ]; then
				mesh_set_low_power $ifname
			fi
		fi
	fi
	#need to check router bind or not
	config_get_bool bindstatus "$vif" bindstatus 0
	config_get_bool userswitch "$vif" userswitch 1
	if [ $ifname == "wl13" ] && [ $bindstatus == 0 -o $userswitch == 0 ];then
		hostapd_cli -i wl13 -p /var/run/hostapd-$device disable
		ifconfig $ifname down
	fi

	local bh_band=$(mesh_cmd backhaul get band)
	local bh_band_upcase=$(echo "$bh_band" | tr '[a-z]' '[A-Z]')
	local netmode=$(uci -q get xiaoqiang.common.NETMODE)
	local backhaul_ap_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)
	if [ -n "$netmode" ] && [ "$netmode" = "whc_re" ]; then
		if [ $ifname = $backhaul_ap_iface ]; then
			local hop_count=$(cat /var/run/topomon/hop_count 2>/dev/null)
			#bring backhaul ap down on power up or hop > 1
			#topomon will check hop status later
			if [ -z $hop_count ] || [ $hop_count != "0" -a $hop_count != "1" ]; then
				cfg80211tool "$ifname" mesh_aplimit 0
			fi
		fi
		local backhaul_5g_sta_iface=$(uci -q get misc.backhauls.backhaul_${bh_band}_sta_iface)
		local mesh_bh_mode=$(uci -q get wireless.meshbhmode.mode)
		if [ $ifname = $backhaul_5g_sta_iface ]; then
			if [ $(cat /var/run/topomon/bh_type) = "wired" -o "$mesh_bh_mode" = "wired" ]; then
				wpa_cli -p /var/run/wpa_supplicant-$ifname disable_network 0
			fi
		fi
	fi

	# meshie with oui_type=MIWIFI_MESH_OUI_TYPE at main backhaul band ap
	# meshie with oui_type=MIWIFI_BHINFO_OUI_TYPE at other backhaul band ap
	if [ "$backhaul_ap_iface" != "$ifname" ]; then
		cfg80211tool "$ifname" meshie_disab 1
	else
		cfg80211tool "$ifname" meshie_disab 0
	fi

	local mesh_role=$(mesh_cmd role)
	local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)
	local ifname_5G=$(uci -q get misc.wireless.ifname_5G)
	local backhaul_5g_ap_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	if [ -n "$mesh_role" ] && [ "CAP" = "$mesh_role" -o "RE" = "$mesh_role" ]; then
		if [ "$mesh_support_dfs" != "1" ] && [ "$ifname" = "$ifname_5G" -o "$ifname" = "$backhaul_5g_ap_iface" ]; then
			wifitool "$ifname" block_acs_channel "52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165"
		fi
	fi

	config_get vap_diff_mode "$vif" vap_diff_mode
	[ -n "$vap_diff_mode" ] && "$device_if" "$ifname" vap_diff_mode "${vap_diff_mode}"

	config_get twt_responder "$vif" twt_responder 0
	[ -n "$twt_responder" ] && "$device_if" "$ifname" twt_responder $twt_responder

	config_get he_dl_ofdma "$vif" he_dl_ofdma
	[ -n "$he_dl_ofdma" ] && "$device_if" "$ifname" he_dl_ofdma "${he_dl_ofdma}"

	config_get he_ul_ofdma "$vif" he_ul_ofdma
	[ -n "$he_ul_ofdma" ] && "$device_if" "$ifname" he_ul_ofdma "${he_ul_ofdma}"

	config_get he_ul_mimo "$vif" he_ul_mimo
	[ -n "$he_ul_mimo" ] && "$device_if" "$ifname" he_ul_mimo "${he_ul_mimo}"

	config_get he_subfee "$vif" he_subfee
	[ -n "$he_subfee" ] && "$device_if" "$ifname" he_subfee "${he_subfee}"

	config_get he_subfer "$vif" he_subfer
	[ -n "$he_subfer" ] && "$device_if" "$ifname" he_subfer "${he_subfer}"

	config_get he_mubfee "$vif" he_mubfee
	[ -n "$he_mubfee" ] && "$device_if" "$ifname" he_mubfee "${he_mubfee}"

	config_get he_mubfer "$vif" he_mubfer
	[ -n "$he_mubfer" ] && "$device_if" "$ifname" he_mubfer "${he_mubfer}"

	if [ "$isolate" = 1 ] && [ "$mode" = "wrap" ]
	then
		brctl delif $bridge $ifname
	fi
}

setup_wps_enhc_device() {
	local device=$1
	local wps_enhc_cfg=

	append wps_enhc_cfg "RADIO" "$N"
	config_get_bool wps_pbc_try_sta_always "$device" wps_pbc_try_sta_always 0
	config_get_bool wps_pbc_skip_ap_if_sta_disconnected "$device" wps_pbc_skip_ap_if_sta_disconnected 0
	config_get_bool wps_pbc_overwrite_ap_settings "$device" wps_pbc_overwrite_ap_settings 0
	config_get wps_pbc_overwrite_ssid_band_suffix "$device" wps_pbc_overwrite_ssid_band_suffix
	[ $wps_pbc_try_sta_always -ne 0 ] && \
			append wps_enhc_cfg "$device:try_sta_always" "$N"
	[ $wps_pbc_skip_ap_if_sta_disconnected -ne 0 ] && \
			append wps_enhc_cfg "$device:skip_ap_if_sta_disconnected" "$N"
	[ $wps_pbc_overwrite_ap_settings -ne 0 ] && \
			append wps_enhc_cfg "$device:overwrite_ap_settings" "$N"
	[ -n "$wps_pbc_overwrite_ssid_band_suffix" ] && \
			append wps_enhc_cfg "$device:overwrite_ssid_band_suffix:$wps_pbc_overwrite_ssid_band_suffix" "$N"

	config_get vifs $device vifs

	for vif in $vifs; do
		config_get ifname "$vif" ifname


		config_get_bool wps_pbc_enable "$vif" wps_pbc_enable 0
		config_get wps_pbc_start_time "$vif" wps_pbc_start_time
		config_get wps_pbc_duration "$vif" wps_pbc_duration
		config_get_bool wps_pbc_noclone "$vif" wps_pbc_noclone 0
		config_get_bool disabled "$vif" disabled 0
		if [ $disabled -eq 0 -a $wps_pbc_enable -ne 0 ]; then
			append wps_enhc_cfg "VAP" "$N"
			[ -n "$wps_pbc_start_time" -a -n "$wps_pbc_duration" ] && {
				if [ $wps_pbc_noclone -eq 0 ]; then
					append wps_enhc_cfg "$ifname:$wps_pbc_start_time:$wps_pbc_duration:$device:clone" "$N"
				else
					append wps_enhc_cfg "$ifname:$wps_pbc_start_time:$wps_pbc_duration:$device:noclone" "$N"
				fi
			}
			[ -n "$wps_pbc_start_time" -a -n "$wps_pbc_duration" ] || {
				if [ $wps_pbc_noclone -eq 0 ]; then
					append wps_enhc_cfg "$ifname:-:-:$device:clone" "$N"
				else
					append wps_enhc_cfg "$ifname:-:-:$device:noclone" "$N"
				fi
			}
		fi
	done

	cat >> /var/run/wifi-wps-enhc-extn.conf <<EOF
$wps_enhc_cfg
EOF
}

setup_wps_enhc() {
	local wps_enhc_cfg=

	append wps_enhc_cfg "GLOBAL" "$N"
	config_get_bool wps_pbc_overwrite_ap_settings_all qcawifi wps_pbc_overwrite_ap_settings_all 0
	[ $wps_pbc_overwrite_ap_settings_all -ne 0 ] && \
			append wps_enhc_cfg "-:overwrite_ap_settings_all" "$N"
	config_get_bool wps_pbc_overwrite_sta_settings_all qcawifi wps_pbc_overwrite_sta_settings_all 0
	[ $wps_pbc_overwrite_sta_settings_all -ne 0 ] && \
			append wps_enhc_cfg "-:overwrite_sta_settings_all" "$N"
	config_get wps_pbc_overwrite_ssid_suffix qcawifi wps_pbc_overwrite_ssid_suffix
	[ -n "$wps_pbc_overwrite_ssid_suffix" ] && \
			append wps_enhc_cfg "-:overwrite_ssid_suffix:$wps_pbc_overwrite_ssid_suffix" "$N"

	cat >> /var/run/wifi-wps-enhc-extn.conf <<EOF
$wps_enhc_cfg
EOF

	config_load wireless
	if [ -n "$1" ]; then
		setup_wps_enhc_device "$1"
	else
		config_foreach setup_wps_enhc_device wifi-device
	fi
}

set_hw_mode_for_dynamic_mode_switch() {
	local new_hw_mode=$1
	local dynamic_hw_mode
	local primary_dev
	local primary_if
	local cnt
	local ini_path

	ini_path=$(get_config_file_path "ini")

	# Check if dynamic hw mode is FAST(=2)
	dynamic_hw_mode=`grep "dynamic_hw_mode" $ini_path/internal/global_i.ini \
		| grep -m1 -v "^[#]" | awk -F'=' '{print $2}'`
	[ $dynamic_hw_mode -ne "2" ] && return

	# Check if new hw mode is DBS(=1) or DBS_SBS(=4)
	[ $new_hw_mode -eq 1 -o $new_hw_mode -eq 4 ] || return
	[ -f /sys/class/net/soc0/pdev_map ] || return

	primary_dev=`grep "*wifi" /sys/class/net/soc0/pdev_map \
		| awk -F'[* ]' '{print $2}'`
	[ -z $primary_dev ] && primary_dev=wifi0
	primary_if=${primary_dev//wifi/wl}

	config_get device_if $primary_dev device_if "cfg80211tool"
	hw_mode=`$device_if $primary_dev get_hw_mode | cut -d: -f2`
	# Check if current hw mode is DBS(=1) or DBS_SBS(=4)
	[ $hw_mode -eq 1 -o $hw_mode -eq 4 ] || return

	[ $hw_mode -eq $new_hw_mode ] && return

	[ ! -d /sys/class/net/$primary_if ] && return

	# Check if ACS is running and if then, wait until the completition
	# (max 10 secs)
	cnt=0
	while [ $cnt -le 10 ]; do
		acs_state=`cfg80211tool $primary_if get_acs_state \
			| awk -F  ':' '{print $2}'`
		[ $acs_state -eq 0 ] && break
		sleep 1
		cnt=$((cnt + 1))
	done
	[ $acs_state -ne 0 ] && return

	[ $cnt -ne 0 ] && sleep 1
	# Check if DFS CAC is running and if then, wait until the completition
	# (max CAC timeout 600 secs)
	cnt=0
	while [ $cnt -le 600 ]; do
		cac_state=`cfg80211tool $primary_if get_cac_state \
			| awk -F  ':' '{print $2}'`
		[ $cac_state -eq 0 ] && break
		sleep 1
		cnt=$((cnt + 1))
	done
	[ $cac_state -ne 0 ] && return

	[ $cnt -ne 0 ] && sleep 1
	$device_if $primary_dev hw_mode $new_hw_mode
}

qcawifi_start_hostapd_cli() {
	local device=$1
	local ifidx=0
	local radioidx=${device#wifi}

	config_get vifs $device vifs

	for vif in $vifs; do
		local config_methods vifname

		config_get vifname "$vif" ifname

		if [ -n $vifname ]; then
			[ $ifidx -gt 0 ] && vifname="wl${radioidx}$ifidx" || vifname="wl${radioidx}"
		fi

		config_get_bool wps_pbc "$vif" wps_pbc 0
		config_get config_methods "$vif" wps_config
		[ "$wps_pbc" -gt 0 ] && append config_methods push_button

		if [ -n "$config_methods" ]; then
			pid=/var/run/hostapd_cli-$vifname.pid
			hostapd_cli -i $vifname -P $pid -a /lib/wifi/wps-hostapd-update-uci -p /var/run/hostapd-$device -B
		fi

		ifidx=$(($ifidx + 1))
	done
}

add_mld_bridge() {
	local net_cfg
	local bridge
	local mld_name="$1"

	if [ -z "$gdevice" ]; then
		gdevice=$DEVICES
	fi

	echo "MLD Single Netdev is ENABLED: Add MLD to Bridge" > /dev/console

	mld_netdev=1
	config_load wireless
	for mld in ${MLD_DEVICES}; do
		if [ ! -z $mld_name ]; then
			if [ $mld_name != $mld ]; then
				continue;
			fi
		fi
		mld_bridge_added=0;
		if [ $mld_netdev == 0 ]; then
			break;
		fi
		for ldevice in $gdevice; do
			config_get vifs "$ldevice" vifs
			for vif in $vifs; do
				config_get vifname "$vif" ifname
				config_get ifmld "$vif" mld
				if [ "$ifmld" = $mld ]; then
					net_cfg="$(find_net_config "$vif")"
					bridge="$(bridge_interface "$net_cfg")"
					if [ -z "$bridge" ]; then
						echo "bridge for $mld if is NULL" > /dev/console
					else
						brctl addif $bridge $mld
						mld_bridge_added=1;
						break;
					fi
				fi
			done
			if [ $mld_bridge_added -eq 1 ]; then
				break;
			fi
		done
	done
}

remove_mld_bridge() {
	local mld_name="$1"
	mld_netdev=1
	for mld in ${MLD_DEVICES}; do
		local wlanmode="__ap"
		if [ $mld_netdev = 0 ]; then
			break;
		fi
		if [ -z $mld_name]; then
			ip link set dev $mld nomaster
		else
			if [ $mld_name = $mld ]; then
				ip link set dev $mld nomaster
			fi
		fi
	done
}

pre_qcawificfg80211() {
	local action=${1}
	local skip_ezmesh_daemon_restart
	local vap_mode=""
	local wifi_3_0_installed="0"
	local board_name
	local devices_t=$DEVICES
	local mld_mac_option=

	if [ -z "$gdevice" ]; then
		gdevice=$DEVICES
	fi

	devices_t=$gdevice

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	if [ -f /sys/module/qca_ol/parameters/is_wifi_3_0_installed ]; then
		wifi_3_0_installed="$(cat /sys/module/qca_ol/parameters/is_wifi_3_0_installed)"
	fi

	get_vap_mode

	# network wifi reload_legacy
	if [ "$vap_mode" = "1" ] && [ "$5" = "network_reload_legacy" ] && [ "$wifi_3_0_installed" = "0" ]; then
		touch /tmp/event_vap_nop
		set "$1" "$2" "$3"
		return
	elif [ "$vap_mode" = "1" ] && [ "$5" = "network_reload_legacy" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		touch /tmp/event_vap_nop
		set "$1" "$2" "$3"
		return
	fi

	# wifi reload_legacy
	if [ "$vap_mode" = "1" ] && [ "$4" = "reload_legacy" ] && [ ! -d /sys/module/wifi_3_0 ]; then
		touch /tmp/event_vap_nop
		set "$1" "$2" "$3"
		return
	fi

	# wifi load
	if [ "$vap_mode" = "1" ] && [ "$action" = "enable" ]; then
		if [ "$3" = "wifi_load" ]; then
			set "$1" "$2"
			if [ ! -d /sys/module/wifi_3_0 ]; then
				touch /tmp/this_is_event
				return
			elif [ "$wifi_3_0_installed" = "1" ]; then
				touch /tmp/event_vap_nop
				return
			fi
		fi
	fi

	# wifi up
	if [ "$vap_mode" = "1" ] && [ "$action" = "enable" ]; then
		if [ "$4" = "wifi_up" ] && [ ! -d /sys/module/wifi_3_0 ] && [ ! -f /tmp/event_fast_boot_in_progress ]; then
			touch /tmp/this_is_event
			set "$1" "$2" "$3"
			return
		fi
		if [ "$3" = "wifi_reload" ] && [ ! -d /sys/module/wifi_3_0 ] && [ ! -f /tmp/event_fast_boot_in_progress ]; then
			touch /tmp/this_is_event
			set "$1" "$2"
			return
		fi
	fi

	[ "$4" = "wifi_up" ] && set "$1" "$2" "$3"
	[ "$3" = "wifi_reload" ] && set "$1" "$2"
	[ "$4" = "reload_legacy" ] && set "$1" "$2" "$3"
	[ "$5" = "reload_legacy" ] && set "$1" "$2" "$3"
	[ "$3" = "wifi_load" ] && set "$1" "$2"

	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		[ ! -f /tmp/event_pre_done_qcawificfg80211_${1} ] || return

		lock /var/run/pre_qcawificfg80211_lock
		if [ -f /tmp/event_pre_done_qcawificfg80211_${1} ]; then
			lock -u /var/run/pre_qcawificfg80211_lock
			return
		fi
	fi

	config_load wireless
	config_get_bool skip_ezmesh_daemon_restart qcawifi skip_ezmesh_daemon_restart '0'

	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		lock /var/run/device_$2
	else
		lock /var/run/wifilock
	fi
	case "${action}" in
		disable)
			config_get_bool wps_vap_tie_dbdc qcawifi wps_vap_tie_dbdc 0

			configure_service_class 0

			# This function pre_qcawificfg80211 disable is called for wifi disable
			# & multup command also.If its multi_up,
			# we will make separate call to remove sepcific MLD from bridge
			if [ "$2" != "multi_up" ]; then
				remove_mld_bridge
			fi

			if [ $wps_vap_tie_dbdc -ne 0 ]; then
				kill "$(cat "/var/run/hostapd.pid")"
				[ -f "/tmp/hostapd_conf_filename" ] &&
					rm /tmp/hostapd_conf_filename
			fi

			local mlo_support="$(mesh_cmd mlo_support)"
			local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
			if [ "$2" = "wifi_update" ] && [ "$mlo_support" = "1" -o "$bh_mlo_support" = "1" ]; then
				pre_mlo_update_qcawificfg80211 "$3"
			fi

			eval "type qwrap_teardown" >/dev/null 2>&1 && qwrap_teardown
			eval "type icm_teardown" >/dev/null 2>&1 && icm_teardown
			eval "type wpc_teardown" >/dev/null 2>&1 && wpc_teardown
			if [ `eval pgrep lowi-server` ]; then
				eval "type lowi_teardown" >/dev/null 2>&1 && lowi_teardown
			fi
			if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
				[ ! -f /etc/init.d/ssid_steering ] || /etc/init.d/ssid_steering stop &
				[ ! -f /etc/init.d/mcsd ] || /etc/init.d/mcsd reload &
				if  [ $skip_ezmesh_daemon_restart -eq 0 ]; then
					if [ -e /tmp/bootup_completed ]; then
						[ ! -f /etc/init.d/lbd ] || /etc/init.d/lbd stop &
						[ ! -f /etc/init.d/hyd ] || /etc/init.d/hyd stop &
						[ ! -f /etc/init.d/wsplcd ] || /etc/init.d/wsplcd stop &
						[ ! -f /etc/init.d/ezmesh ] || /etc/init.d/ezmesh stop &
					fi
				fi
			else
				[ ! -f /etc/init.d/ssid_steering ] || /etc/init.d/ssid_steering stop
				[ ! -f /etc/init.d/mcsd ] || /etc/init.d/mcsd reload
				if  [ $skip_ezmesh_daemon_restart -eq 0 ]; then
					if [ -e /tmp/bootup_completed ]; then
						[ ! -f /etc/init.d/lbd ] || /etc/init.d/lbd stop
						[ ! -f /etc/init.d/hyd ] || /etc/init.d/hyd stop
						[ ! -f /etc/init.d/wsplcd ] || /etc/init.d/wsplcd stop
						[ ! -f /etc/init.d/ezmesh ] || /etc/init.d/ezmesh stop
					fi
				fi
			fi

			rm -f /var/run/wifi-wps-enhc-extn.conf
			[ -r /var/run/wifi-wps-enhc-extn.pid ] && kill "$(cat "/var/run/wifi-wps-enhc-extn.pid")"

			if [ `eval pgrep qldtool` ]; then
				killall qldtool >/dev/null 2>&1
			fi

			if [ -f  "/var/run/son.conf" ]; then
				rm /var/run/son.conf
			fi

			# For dynamic_hw_mode(=2), set hw mode back to DBS_SBS
			# to be able to clean up secondary pdev
			set_hw_mode_for_dynamic_mode_switch 4
			;;

		enable)
			local icm_enable

			config_get_bool icm_enable icm enable 0
			[ ${icm_enable} -gt 0 ] && \
					eval "type icm_setup" >/dev/null 2>&1 && {
				icm_setup cfg80211
			}
			echo "MLD Single Netdev is ENABLED: Add MLD Interface" > /dev/console
			mld_netdev=1
			# Do not Create MLDs if command comes for individual Radios
			for mld in ${MLD_DEVICES}; do
				local wlanmode="__ap"
				local parent_wifi_iface
				if [ $mld_netdev == 0 ]; then
					break;
				fi

				if [ -f /tmp/event_fast_boot_in_progress ]; then
					break;
				fi

				config_get mld_mac $mld mld_macaddr
				config_get role $mld role
				if [ -n "$mld_mac" ]; then
					tmp_mld=$(echo $mld_mac | sed 's/://g' | sed 's/0//g' )
					if [ -n "$tmp_mld" ]; then
						mld_mac_option="mld_addr"
					else
						mld_mac=
					fi
				fi



				for device2 in $devices_t; do
					config_get disabled "$device2" disabled
					[ "$disabled" = "1" ] && {
						echo "'$device2' is disabled"
						continue
					}
					config_get vifs "$device2" vifs

					for vif in $vifs; do
						config_get ifmld "$vif" mld

						if [ "$ifmld" = $mld ]; then
							config_get link_mode "$vif" mode
							config_get wifi_iface "$vif" device
							parent_wifi_iface=$wifi_iface
							if [ "$link_mode" = "sta" ]; then
								wlanmode="managed"
								break
							fi
						fi
					done
				done
				local mld_phy_name
				mld_phy_name=`cat /sys/class/net/$parent_wifi_iface/mldphy_name`
				[ -z "$mld_phy_name" ] && mld_phy_name="mld-phy0"
				echo "mld_phy_name: $mld_phy_name parent_wifi_iface: $parent_wifi_iface" > /dev/console

				if [ "$role" = "Non-AP" ]; then
					iw phy $mld_phy_name interface add $mld type managed $mld_mac_option $mld_mac
					echo "mld: $mld role: $role wlanmode: managed" > /dev/console
					ifconfig $mld up
					continue;
				fi
				if [ "$role" = "AP" ]; then
					iw phy $mld_phy_name interface add $mld type $wlanmode $mld_mac_option $mld_mac
					echo "mld: $mld role: $role wlanmode: $wlanmode" > /dev/console
					ifconfig $mld up
					continue;
				fi

				iw phy $mld_phy_name interface add $mld type $wlanmode $mld_mac_option $mld_mac
				ifconfig $mld up
			done
			;;
		disable_recover)
			if  [ $skip_ezmesh_daemon_restart -eq 0 ]; then
				[ ! -f /etc/init.d/lbd ] || /etc/init.d/lbd stop
			fi
			;;
	esac
	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		touch /tmp/event_pre_done_qcawificfg80211_${1}
		lock -u /var/run/device_$2
		lock -u /var/run/pre_qcawificfg80211_lock
	else
		lock -u /var/run/wifilock
	fi
}
# MIWIFI iot_dev
is_iotwifi_ifname()
{
	local ifname="$1"
	[ -z "$ifname" ] && return 1

	local iot2g_ifname=$(uci -q get wireless.iot_2g.ifname)
	local iot5g_ifname=$(uci -q get wireless.iot_5g.ifname)
	[ "$ifname" = "$iot2g_ifname" -o "$ifname" = "$iot5g_ifname" ] && return 0
	return 1
}

process_iotwifi()
{
	local ifname="$1"
	local _hwmode="$2"

	[ -z "$ifname" -o -z "$_hwmode" ] && return

	local iot_dev_support=$(uci -q get misc.features.iot_dev)
	[ "$iot_dev_support" != "1" ] && return

	local iot2g_disabled=$(uci -q get wireless.iot_2g.disabled)
	local iot5g_disabled=$(uci -q get wireless.iot_5g.disabled)
	local iot2g_device=$(uci -q get wireless.iot_2g.device)
	local iot5g_device=$(uci -q get wireless.iot_5g.device)
	local ax_5g=$(uci -q get wireless.${iot5g_device}.ax)
	local ax_2g=$(uci -q get wireless.${iot2g_device}.ax)
	local iot2g_ifname=$(uci -q get wireless.iot_2g.ifname)
	local iot5g_ifname=$(uci -q get wireless.iot_5g.ifname)

	echo "process_iotwifi: $ifname, iot2g_disabled:$iot2g_disabled, ax_2g:$ax_2g, iot5g_disabled:$iot2g_disabled, ax_5g:$ax_5g" >>/dev/console

	if [ "$ifname" = "$iot2g_ifname" ] && [ "$iot2g_disabled" != "1" ] && [ "$ax_2g" = "1" ]; then
		local hwmode_2g=""
		local iot2g_wifi5mode=$(uci -q get wireless.iot_2g.iotwifi5mode)

		if [ "$iot2g_wifi5mode" -eq 1 ]; then
			case "$_hwmode" in
				*20) hwmode_2g=11NGHT20;;
				*40MINUS) hwmode_2g=11NGHT40MINUS;;
				*40PLUS) hwmode_2g=11NGHT40PLUS;;
				*) hwmode_2g=11NGHT40;;
			esac
		else
			case "$_hwmode" in
				*20) hwmode_2g=11GHE20;;
				*40MINUS) hwmode_2g=11GHE40MINUS;;
				*40PLUS) hwmode_2g=11GHE40PLUS;;
				*) hwmode_2g=11GHE40;;
			esac
		fi
		if [ -n "$hwmode_2g" ]; then
			"$device_if" $iot2g_ifname vap_diff_mode 1
			"$device_if" $iot2g_ifname mode $hwmode_2g
			echo "process_iotwifi $iot2g_ifname set mode to $hwmode_2g" >>/dev/console
		fi
	elif [ "$ifname" = "$iot5g_ifname" ] && [ "$iot5g_disabled" != "1" ] && [ "$ax_5g" = "1" ]; then
		local hwmode_5g=""
		local iot5g_wifi5mode=$(uci -q get wireless.iot_5g.iotwifi5mode)

		if [ "$iot5g_wifi5mode" -eq 1 ]; then
			case "$_hwmode" in
				*20) hwmode_5g=11ACVHT20;;
				*40MINUS) hwmode_5g=11ACVHT40PLUS;;
				*40PLUS) hwmode_5g=11ACVHT40PLUS;;
				*40) hwmode_5g=11ACVHT40;;
				*80) hwmode_5g=11ACVHT80;;
				*160) hwmode_5g=11ACVHT160;;
			esac
		else
			case "$_hwmode" in
				*20) hwmode_5g=11AHE20;;
				*40MINUS) hwmode_5g=11AHE40MINUS;;
				*40PLUS) hwmode_5g=11AHE40PLUS;;
				*40) hwmode_5g=11AHE40;;
				*80) hwmode_5g=11AHE80;;
				*160) hwmode_5g=11AHE160;;
			esac
		fi
		if [ -n "$hwmode_5g" ]; then
			"$device_if" $iot5g_ifname vap_diff_mode 1
			"$device_if" $iot5g_ifname mode $hwmode_5g
			echo "process_iotwifi $iot5g_ifname set mode to $hwmode_5g" >>/dev/console
		fi
	fi
}

post_qcawificfg80211() {
	local mbss_tx_vdev_config_required=1
	local mbss_tx_grp=
	[ "$3" = "wifi_reload" ] && set "$1" "$2"
	[ "$3" = "wifi_load" ] && set "$1" "$2"

	if [ "$2" = "multi_up" ]; then
		mbss_tx_vdev_config_required=$3
		[ -n "$4" ] && mbss_tx_grp=$4
	fi

	local action=${1}
	local board_name skip_ezmesh_daemon_restart
	local vap_mode=""

	rm -f /var/run/iface_mgr.conf
	[ -r /var/run/iface_mgr.pid ] && kill "$(cat "/var/run/iface_mgr.pid")"
	rm -f /var/run/iface_mgr.pid

	get_vap_mode

	# wifi reload_legacy
	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_vap_nop ]; then
		rm -rf /tmp/event_vap_nop
		return
	fi

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	if [ "$vap_mode" = "1" ] && [ -f /tmp/this_is_event ] && [ ! -f /tmp/event_fast_boot_in_progress ]; then
		if [ ! -f /tmp/vap_up_start ]; then
			touch /tmp/vap_up_start
			rm -rf /tmp/wifi_load_done
			rm -rf /tmp/this_is_event
			wifi_config "1"
		fi
		return
	fi


	config_get type "$device" type
	[ "$type" != "qcawificfg80211" ] && return

	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		lock /var/run/device_$2
	else
		lock /var/run/wifilock
	fi

	case "${action}" in
		enable)
			case $2 in
				wifi_update)
					post_update_qcawificfg80211 "$3"
				;;
				multi_up)
				;;
				*)
				start_qcawificfg80211 "$2" "$3"
				[ -f /sbin/applyWifiAccessPolicy.sh ] && {
					/sbin/applyWifiAccessPolicy.sh applyAll
				}
				;;
			esac

			local icm_enable qwrap_enable lowi_enable

			# Run a single hostapd instance for all the radio's
			# Enables WPS VAP TIE feature

			config_get_bool wps_vap_tie_dbdc qcawifi wps_vap_tie_dbdc 0

			if [ $wps_vap_tie_dbdc -ne 0 ]; then
				hostapd_conf_file=$(cat "/tmp/hostapd_conf_filename")
				hostapd -P /var/run/hostapd.pid $hostapd_conf_file -B
				if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
					qcawifi_start_hostapd_cli "$2"
				else
					config_foreach qcawifi_start_hostapd_cli wifi-device
				fi
			fi

			# This function post qcawificfg80211 enable is called for wifi enable
			# & multup command also.If its multi_up,
			# we will make separate call to add sepcific MLD to bridge
			if [ "$2" != "multi_up" ]; then
				add_mld_bridge
			fi

			# Restarts RM APP if enabled in configs
			config_load rsrcmgr
			rm_enabled=$(uci get rsrcmgr.config.Enable)

			if [ "$rm_enabled" = 1 ]; then
				echo "Restarting RM APP.."
				/etc/init.d/rsrcmgr restart
			fi

			if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
				lock -u /var/run/device_$2
				return
			fi
			post_common_qcawificfg80211 "$mbss_tx_vdev_config_required" "$mbss_tx_grp"
		;;
		disable)
			mld_netdev=0
			# Do not delete MLDs if command comes for individual Radios
			for mld in ${MLD_DEVICES}; do
				if [ $mld_netdev == 0 ]; then
					break;
				fi
				ip link set dev $mld nomaster
				iw dev $mld del
			done

			cd /sys/class/net
			for mld in $(ls -d mld* 2>&-); do
				if [ $mld_netdev == 0 ]; then
					break;
				fi
				if [ -f $mld/address ]; then
					echo "Deleting $mld" > /dev/console
					iw dev $mld del
				fi
			done
		;;
		enable_recover)
			if [ "$2" != "multi_up" ]; then
				start_qcawificfg80211 "$2" "$3"
			fi

			[ ! -f /etc/init.d/lbd ] || /etc/init.d/lbd start

			# For dynamic_hw_mode(=2), set hw mode using
			# recover_mode information
			hw_mode=`grep "recover_mode" /sys/class/net/soc0/pdev_map \
				| awk -F'[(=)]' '{print $4}'`
			set_hw_mode_for_dynamic_mode_switch $hw_mode
		;;
	esac

	if [ ! -f /tmp/event_fast_boot_in_progress ]; then
		update_global_daemon_coldboot_qdss_support_variables
		enable_qdss_tracing
		atf_configcfg80211
	fi
	if [ "$vap_mode" = "1" ] && [ -f /tmp/event_fast_boot_in_progress ]; then
		lock -u /var/run/device_$2
	else
		lock -u /var/run/wifilock
	fi
}

unicastflood_configcfg80211() {
	config_load wireless
	config_foreach unicastflood_vap_configcfg80211 wifi-device
}

unicastflood_vap_configcfg80211() {
	local device="$1"

	config_get disabled $device disabled 0
	config_get unicastflood_disable $device unicastflood_disable 0
	if [ $disabled -eq 0 ] && [ $unicastflood_disable -eq 1 ]; then
		config_get vifs "$device" vifs
		for vif in $vifs; do
			config_get vifname $vif ifname
			config_get network $vif network
			config_get vif_disabled $vif disabled 0
			if [ $vif_disabled -eq 0 ]; then
				if [ -e /sys/class/net/br-$network/brif/$vifname/unicast_flood ]; then
					echo 0 > /sys/class/net/br-$network/brif/$vifname/unicast_flood
				fi
			fi
		done
	fi
}

atf_configcfg80211() {
	config_get wfcfg wireless conffile wireless

	config_load $wfcfg
	config_foreach atf_radio_vap_params_configcfg80211 wifi-device

	config_load $wfcfg
	config_foreach atf_group_configcfg80211 atf-config-group

	config_load $wfcfg
	config_foreach atf_ssid_configcfg80211 atf-config-ssid

	config_load $wfcfg
	config_foreach atf_sta_configcfg80211 atf-config-sta

	config_load $wfcfg
	config_foreach atf_ac_configcfg80211 atf-config-ac

	config_load $wfcfg
	config_foreach atf_tput_configcfg80211 atf-config-tput

	config_load $wfcfg
	config_foreach atf_enablecfg80211 wifi-device
}

atf_radio_vap_params_configcfg80211() {
	local device="$1"
	local atf_sched_dur
	local atfstrictsched
	local atfobsssched
	local atfobssscale
	local atfgrouppolicy

	config_get device_if "$device" device_if "cfg80211tool"
	config_get atf_sched_dur "$device" atf_sched_dur
	[ -n "$atf_sched_dur" ] && $device_if "$device" "atf_sched_dur" "$atf_sched_dur"

	config_get atfstrictsched "$device" atfstrictsched
	[ -n "$atfstrictsched" ] && $device_if "$device" "atfstrictsched" "$atfstrictsched"

	config_get atfobsssched "$device" atfobsssched
	[ -n "$atfobsssched" ] && $device_if "$device" "atfobsssched" "$atfobsssched"

	config_get atfobssscale "$device" atfobssscale
	[ -n "$atfobssscale" ] && $device_if "$device" "atfobssscale" "$atfobssscale"

	config_get atfgrouppolicy "$device" atfgrouppolicy
	[ -n "$atfgrouppolicy" ] && $device_if "$device" "atfgrouppolicy" "$atfgrouppolicy"

	config_get disabled $device disabled 0
	if [ $disabled -eq 0 ]; then
		config_get vifs "$device" vifs

		local ifidx=0
		local radioidx=${device#wifi}
		for vif in $vifs; do
			local vifname tvifname
			[ $ifidx -gt 0 ] && tvifname="wl${radioidx}$ifidx" || tvifname="wl${radioidx}"
			config_get vifname "$vif" ifname "tvifname"

			config_get atf_shr_buf "$vif" atf_shr_buf
			[ -n "$atf_shr_buf" ] && $device_if "$vifname" "atf_shr_buf" "$atf_shr_buf"

			config_get atf_max_buf "$vif" atf_max_buf
			[ -n "$atf_max_buf" ] && $device_if "$vifname" "atf_max_buf" "$atf_max_buf"

			config_get atf_min_buf "$vif" atf_min_buf
			[ -n "$atf_min_buf" ] && $device_if "$vifname" "atf_min_buf" "$atf_min_buf"

			config_get commitatf "$vif" commitatf
			[ -n "$commitatf" ] && $device_if "$vifname" "commitatf" "$commitatf"

			config_get atfmaxclient "$vif" atfmaxclient
			[ -n "$atfmaxclient" ] && $device_if "$vifname" "atfmaxclient" "$atfmaxclient"

			config_get atfssidgroup "$vif" atfssidgroup
			[ -n "$atfssidgroup" ] && $device_if "$vifname" "atfssidgroup" "$atfssidgroup"

			config_get atf_tput_at "$vif" atf_tput_at
			[ -n "$atf_tput_at" ] && $device_if "$vifname" "atf_tput_at" "$atf_tput_at"

			config_get atfssidsched "$vif" atfssidsched
			[ -n "$atfssidsched" ] && $device_if "$vifname" "atfssidsched" "$atfssidsched"

			ifidx=$(($ifidx + 1))
		done
	fi

}

atf_group_configcfg80211() {
	local cmd
	local group
	local ssid
	local airtime
	local device
	local vifname

	config_get device "$1" device
	radioidx=${device#wifi}
	[ "$radioidx" = "0" ] && radioidx=1
	[ "$radioidx" = "1" ] && radioidx=0
	config_get vifname "$1" ifname "wl$radioidx"

	config_get cmd "$1" command
	config_get group "$1" group
	config_get ssid "$1" ssid
	config_get airtime "$1" airtime

	if [ -z "$cmd" ] || [ -z "$group" ] ; then
		echo "Invalid ATF GROUP Configuration"
		return 1
	fi

	if [ "$cmd" == "addgroup" ] && [ -n "$ssid" ] && [ -n "$airtime" ]; then
		for word in $ssid; do
			wlanconfig $vifname addatfgroup $group $word -cfg80211
		done
		wlanconfig $vifname configatfgroup $group $airtime -cfg80211
	fi

	if [ "$cmd" == "delgroup" ]; then
		wlanconfig $vifname delatfgroup $group -cfg80211
	fi
}

atf_ssid_configcfg80211() {
	local cmd
	local ssid
	local airtime
	local device
	local vifname

	config_get device "$1" device
	radioidx=${device#wifi}
	[ "$radioidx" = "0" ] && radioidx=1
	[ "$radioidx" = "1" ] && radioidx=0
	config_get vifname "$1" ifname "wl$radioidx"

	config_get cmd "$1" command
	config_get ssid "$1" ssid
	config_get airtime "$1" airtime

	if [ -z "$cmd" ] || [ -z "$ssid" ] ; then
		echo "Invalid ATF SSID Configuration"
		return 1
	fi

	if [ "$cmd" == "addssid" ] && [ -n "$airtime" ]; then
		wlanconfig $vifname $cmd $ssid $airtime -cfg80211
	fi

	if [ "$cmd" == "delssid" ]; then
		wlanconfig $vifname $cmd $ssid -cfg80211
	fi
}

atf_sta_configcfg80211() {
	local cmd
	local ssid
	local airtime
	local device
	local mac
	local vifname

	config_get device "$1" device
	radioidx=${device#wifi}
	[ "$radioidx" = "0" ] && radioidx=1
	[ "$radioidx" = "1" ] && radioidx=0
	config_get vifname "$1" ifname "wl$radioidx"

	config_get cmd "$1" command
	config_get airtime "$1" airtime
	config_get ssid "$1" ssid
	config_get mac "$1" macaddr
	mac="${mac//:}"

	if [ -z "$cmd" ] || [ -z "$mac" ] ; then
		echo "Invalid ATF STA Configuration"
		return 1
	fi

	if [ "$cmd" == "addsta" ] && [ -n "$airtime" ]; then
		wlanconfig $vifname $cmd $mac $airtime $ssid -cfg80211
	fi

	if [ "$cmd" == "delsta" ]; then
		wlanconfig $vifname $cmd $mac -cfg80211
	fi
}

atf_ac_configcfg80211() {
	local cmd
	local ssid
	local device
	local ac
	local airtime
	local vifname

	config_get device "$1" device
	radioidx=${device#wifi}
	[ "$radioidx" = "0" ] && radioidx=1
	[ "$radioidx" = "1" ] && radioidx=0
	config_get vifname "$1" ifname "wl$radioidx"

	config_get cmd "$1" command
	config_get ac "$1" ac
	config_get airtime "$1" airtime
	config_get ssid "$1" ssid

	if [ -z "$cmd" ] || [ -z "$ssid" ] || [ -z "$ac" ] ; then
		echo "Invalid ATF AC Configuration"
		return 1
	fi

	if [ "$cmd" == "atfaddac" ] && [ -n "$airtime" ]; then
		wlanconfig $vifname $cmd $ssid $ac:$airtime -cfg80211
	fi

	if [ "$cmd" == "atfdelac" ]; then
		wlanconfig $vifname $cmd $ssid $ac -cfg80211
	fi
}

atf_tput_configcfg80211() {
	local cmd
	local tput
	local max_airtime
	local device
	local mac
	local vifname

	config_get device_if "$device" device_if "cfg80211tool"
	config_get device "$1" device
	radioidx=${device#wifi}
	[ "$radioidx" = "0" ] && radioidx=1
	[ "$radioidx" = "1" ] && radioidx=0
	config_get vifname "$1" ifname "wl$radioidx"

	config_get cmd "$1" command
	config_get tput "$1" throughput
	config_get max_airtime "$1" max_airtime
	config_get mac "$1" macaddr
	mac="${mac//:}"

	if [ -z "$cmd" ] || [ -z "$mac" ] || [ -z "$tput" ] ; then
		echo "Invalid ATF Throughput Configuration"
		return 1
	fi

	if [ "$cmd" == "addtputsta" ]; then
		$device_if $vifname commitatf 0
		wlanconfig $vifname addtputsta $mac $tput $max_airtime -cfg80211
	fi

	if [ "$cmd" == "deltputsta" ]; then
		$device_if $vifname commitatf 0
		wlanconfig $vifname deltputsta $mac -cfg80211
	fi
}

atf_enablecfg80211() {
	local device="$1"

	config_get device_if "$device" device_if "cfg80211tool"
	config_get disabled $device disabled 0
	if [ $disabled -eq 0 ]; then
		config_get vifs "$device" vifs
		echo "device: $device vifs: $vifs"

		local ifidx=0
		local radioidx=${device#wifi}
		for vif in $vifs; do
			local vifname tvifname
			[ $ifidx -gt 0 ] && tvifname="wl${radioidx}$ifidx" || tvifname="wl${radioidx}"
			config_get vifname "$vif" ifname "tvifname"
			config_get commitatf "$vif" commitatf
			[ -n "$commitatf" ] && $device_if "$vifname" "commitatf" "$commitatf"

			ifidx=$(($ifidx + 1))
		done
	fi
}

qld_enablecfg80211() {
	local device="$1"
	echo "qld linked to device: $device"
	qldtool -i $device -B
}

check_qcawifi_device() {
	[ ${1%[0-9]} = "wifi" ] && config_set "$1" phy "$1"
	config_get phy "$1" phy
	[ -z "$phy" ] && {
		find_qcawifi_phy "$1" >/dev/null || return 1
		config_get phy "$1" phy
	}
	[ "$phy" = "$dev" ] && found=1
}

ftm_qcawificfg80211() {
	local board_name
	local qdf_args
	local ini_path

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=$(cat /tmp/sysinfo/board_name)
	}

	ini_path=$(get_config_file_path "ini")
	case "$board_name" in
	ap-sdxlemur*) ;;
	*)
		echo_cmd -n "$ini_path" /sys/module/firmware_class/parameters/path
	;;
	esac

	case "$board_name" in
	*hk*|*dk*|*ac*|*cp*|*oa*|*mp*|*al*|*mi*)
		echo "Entering FTM mode operation" > /dev/console
	;;
	*)
		echo "FTM mode operation not applicable. Returning" > /dev/console
		return
	;;
	esac

	if [ -e /sys/firmware/devicetree/base/MP_256 ]; then
		sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 1400000
		sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 20432
		sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 0
	fi

	if [ "$board_name" = "ap-hk10-c1" ]; then
		update_internal_ini global_i.ini mode_2g_phyb 1
	fi

	if [ -e /sys/firmware/devicetree/base/MP_256 ]; then
		# Force all the radios in NSS offload mode on 256M profile
		case "$board_name" in
		*hk*|*ac*|*oa*|*cp*|*mp*)
			update_ini_file nss_wifi_olcfg 7
		;;
		*)
		;;
		esac

		[  ! -e  /etc/modules.d/52-diag-char ] &&  {
			echo diagchar > /etc/modules.d/52-diag-char
			insmod_cmd diagchar
		}
	else
		# Force all the radios in NSS offload disabled mode on 1G/512M profile
		case "$board_name" in
		*hk*|*ac*|*oa*|*cp*|*mp*)
			update_ini_file nss_wifi_olcfg 0
		;;
		*)
		;;
		esac
	fi

	rm -rf /etc/config/wireless

	append qdf_args "mem_debug_disabled=1"

	update_ini_file cfg80211_config "1"
	for mod in $(cat /lib/wifi/qca-wifi-modules); do

		case ${mod} in
			umac) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} || { \
					lock -u /var/run/wifilock
					unload_qcawifi
					error=1
				}
			};;

			qdf) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} ${qdf_args} || { \
					lock -u /var/run/wifilock
					unload_qcawifi
					error=2
				}
			};;

			qca_ol) [ -d /sys/module/${mod} ] || { \
				do_cold_boot_calibration_qcawificfg80211
				insmod_cmd ${mod} testmode=1 || { \
					lock -u /var/run/wifilock
					unload_qcawifi
					error=3
				}
			};;

			ath_pktlog) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} || { \
					lock -u /var/run/wifilock
					unload_qcawifi
					error=4
				}
			};;

			qca_da|ath_dev|hst_tx99|ath_rate_atheros|ath_hal)
			;;

			smart_antenna)
			;;

			*) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} || { \
					lock -u /var/run/wifilock
					unload_qcawifi
					error=4
				}
			};;

		esac
	done

	# case "$board_name" in
	# *hk*|*ac*|*cp*|*oa*|*mp*|*al*)
	# 	[ -d /etc/modules.d.bk ] && { \
	# 		rm -rf /etc/modules.d
	# 		mv /etc/modules.d.bk /etc/modules.d
	# 	}
	# ;;
	# *)
	# ;;
	# esac

	sync
	[ $error != 0 ] && echo "FTM error: $error" > /dev/console && return 1
	dmesg -n8
	if [ -f /tmp/ftm.conf ]; then
		ftm -n -c /tmp/ftm.conf &
	else
		ftm -n &
	fi
	#dmesg got disabled earlier in boot-ftm file
	#enable dmesg back
	update_global_daemon_coldboot_qdss_support_variables
	enable_qdss_tracing
	echo "FTM mode interface is ready now" > /dev/kmsg
}

waltest_qcawificfg80211() {
	local board_name ini_path

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	ini_path=$(get_config_file_path "ini")
	case "$board_name" in
	ap-sdxlemur*) ;;
	*)
		echo_cmd -n "$ini_path" /sys/module/firmware_class/parameters/path
	;;
	esac

	case "$board_name" in
	ap-hk*|ap-mi*)
		echo "Entering WALtest mode operation" > /dev/console
	;;
	*)
		echo "WALtest mode operation not applicable. Returning" > /dev/console
		return
	;;
	esac

	if [ -e /sys/firmware/devicetree/base/MP_256 ]; then
		sysctl_cmd dev.nss.n2hcfg.extra_pbuf_core0 1400000
		sysctl_cmd dev.nss.n2hcfg.n2h_high_water_core0 20432
		sysctl_cmd dev.nss.n2hcfg.n2h_wifi_pool_buf 0
	fi

	rm -rf /etc/config/wireless

	update_ini_file cfg80211_config "1"
	for mod in $(cat /lib/wifi/qca-wifi-modules); do

		case ${mod} in
			umac) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawifi
					error=1
				}
			};;

			qdf) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawifi
					error=2
				}
			};;

			qca_ol) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} testmode=3 || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawifi
					error=3
				}
			};;

			qca_da|ath_dev|hst_tx99|ath_rate_atheros|ath_hal)
			;;

			smart_antenna|ath_pktlog)
			;;

			*) [ -d /sys/module/${mod} ] || { \
				insmod_cmd ${mod} || { \
					if [ "$recover" != "1" ]; then
						lock -u /var/run/wifilock
					fi
					unload_qcawifi
					error=4
				}
			};;

		esac
	done

	[ $error != 0 ] && echo "WALtest error: $error" > /dev/console && return 1
	update_global_daemon_coldboot_qdss_support_variables
	enable_qdss_tracing
	echo "WALtest mode interface is ready now" > /dev/kmsg
}

init_mimesh_backhaul()
{
	local bh_ssid="MiMesh_$(head -n10 /dev/urandom | md5sum | cut -c1-9)"
	local bh_pswd="$(head -n10 /dev/urandom | md5sum | cut -c1-17)"
	local bh_mgmt="psk2"

	local lanmac=$(getmac lan)
	local bh_band=$(mesh_cmd backhaul get band)
	local mesh_version=$(mesh_cmd max_mesh_version)
	local bh_mlo_support="$(mesh_cmd bh_mlo_support)"

	local mld_dev=
	local mlo_radios=
	local radio_sets=
	local sta_mlo_radios=
	local sta_mld_dev=
	if [ "$bh_mlo_support" = "1" ]; then
		mlo_radios=$(uci -q get misc.mld.bh_ap_mlo)
		radio_sets=$(echo $mlo_radios | tr , " " | tr '[A-Z]' '[a-z]')
		[ -n "$mlo_radios" ] && mld_dev=$(uci -q get misc.mld.bh_ap)
		sta_mlo_radios=$(uci -q get misc.mld.sta_mlo)
		[ -n "$sta_mlo_radios" ] && sta_mld_dev=$(uci -q get misc.mld.bh_sta)
	fi

	[ -z "$radio_sets" ] && radio_sets="$bh_band"
	for radio in $radio_sets; do
		local radio_upcase=$(echo $radio | tr '[a-z]' '[A-Z]')
		local bh_device=$(uci -q get misc.wireless.if_$radio_upcase)
		local bh_ifname=$(uci get misc.backhauls.backhaul_${radio}_ap_iface)
		local dev_macaddr="$(cat /sys/class/net/${bh_device}/address)"
		local vap_macaddr=""
		if [ "$radio" = "5g" -o "$radio" = "5gh" ]; then
			channel_block_list="52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165"
			vap_macaddr="$(calcbssid -i2 -m $dev_macaddr)"
		fi
		[ "$bh_mlo_support" = "1" ] && sec_name="bh_ap_$radio" || sec_name="bh_ap"
cat <<EOF
config wifi-iface '$sec_name'
	option device '$bh_device'
	option ifname '$bh_ifname'
	option network 'lan'
	option mode 'ap'
	option channel_block_list '$channel_block_list'
	option ssid '$bh_ssid'
	option encryption '$bh_mgmt'
	option key '$bh_pswd'
	option hidden '1'
	option backhaul '1'
	option backhaul_ap '1'
	option wds '1'
	option wps_pbc '1'
	option wps_pbc_enable '0'
	option wps_pbc_start_time '0'
	option wps_pbc_duration '120'
	option group '0'
	option athnewind '1'
	option mesh_apmac '$lanmac'
	option mesh_aplimit '9'
	option mesh_ver '$mesh_version'
	option macaddr '$vap_macaddr'
	option miwifi_mesh '0'
EOF
		if [ -n "$mlo_radios" ]; then
cat <<EOF
	option mld '$mld_dev'
	option disabled '0'
EOF
		elif [ "$radio" = "$bh_band" ]; then
cat <<EOF
	option disabled '0'
EOF
		else
cat <<EOF
	option disabled '1'
EOF
		fi
	done
	if [ -n "$mld_dev" ]; then
cat <<EOF
config wifi-mld '$mld_dev'
	option mld_macaddr '$(mld_macaddr bh_ap)'
	option mld_ssid '$bh_ssid'
EOF
	fi
	if [ -n "$sta_mld_dev" ]; then
cat <<EOF
config wifi-mld '$sta_mld_dev'
	option role 'Non-AP'
	option mld_macaddr '$(mld_macaddr bh_sta)'
EOF
	fi
}

post_detect_qcawificfg80211() {
	cd /sys/class/net
	[ -d $1 ] || return
	dev=$1

	lock /var/run/post_detect_qcawificfg80211_lock
	found=0
	config_load wireless
	config_foreach check_qcawifi_device wifi-device
	lock -u /var/run/post_detect_qcawificfg80211_lock

	touch /tmp/event_fast_boot_in_progress

	if [ "$found" -gt 0 ]; then
		/sbin/wifi event_reload_legacy $1
		return
	fi
}

lock_wifi() {
	# MiWiFi: Do not lock
	return
	lock /var/run/wifi_global_lock
}

unlock_wifi() {
	# MiWiFi: Do not lock
	return
	lock -u /var/run/wifi_global_lock
}

post_load_qcawificfg80211() {
	local load_ol_mod=0
	local qca_da_needed=0
	local device=$1

	lock /var/run/post_load_qcawificfg80211_lock
	if [ ! -f /tmp/event_post_load_qcawificfg80211 ]; then
		[ -f /tmp/sysinfo/board_name  ] && {
			board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
		}

		for mod in $(cat /lib/wifi/qca-wifi-modules); do
			case ${mod} in
				qca_ol) [ -d /sys/module/${mod} ] && { \
					load_ol_mod=1
				}
			;;
			esac
		done

		if [ $load_ol_mod -eq 1 ]; then
			for wmi_dir in /sys/kernel/debug/WMI_SOC*;do
				case "$board_name" in
					ap-hk*|ap-ac*|ap-cp*|ap-oak*|ap-mp*)
					if [ -f $wmi_dir/filtered_wmi_cmds ]; then
						echo 0x5002 > $wmi_dir/filtered_wmi_cmds
						echo 0x5003 > $wmi_dir/filtered_wmi_cmds
						echo 0x5004 > $wmi_dir/filtered_wmi_cmds
						echo 0x5006 > $wmi_dir/filtered_wmi_cmds
						echo 0x5007 > $wmi_dir/filtered_wmi_cmds
						echo 0x5024 > $wmi_dir/filtered_wmi_cmds
						echo 0x4028 > $wmi_dir/filtered_wmi_cmds
					fi
					if [ -f $wmi_dir/filtered_wmi_evts ]; then
						echo 0x5001 > $wmi_dir/filtered_wmi_evts
						echo 0x5002 > $wmi_dir/filtered_wmi_evts
						echo 0x5006 > $wmi_dir/filtered_wmi_evts
						echo 0x5012 > $wmi_dir/filtered_wmi_evts
						echo 0x4023 > $wmi_dir/filtered_wmi_evts
					fi
					;;
					*)
					if [ -f $wmi_dir/filtered_wmi_cmds ]; then
						echo 0x9014 > $wmi_dir/filtered_wmi_cmds
						echo 0x9015 > $wmi_dir/filtered_wmi_cmds
						echo 0x9016 > $wmi_dir/filtered_wmi_cmds
						echo 0x9018 > $wmi_dir/filtered_wmi_cmds
						echo 0x9019 > $wmi_dir/filtered_wmi_cmds
						echo 0x9084 > $wmi_dir/filtered_wmi_cmds
						echo 0x9085 > $wmi_dir/filtered_wmi_cmds
					fi
					if [ -f $wmi_dir/filtered_wmi_evts ]; then
						echo 0x9004 > $wmi_dir/filtered_wmi_evts
						echo 0x9007 > $wmi_dir/filtered_wmi_evts
						echo 0x9047 > $wmi_dir/filtered_wmi_evts
						echo 0x9048 > $wmi_dir/filtered_wmi_evts
					fi
					;;
				esac

			done
		fi

		update_ini_target_dp_default_reo_reset
		touch /tmp/event_post_load_qcawificfg80211
	fi
	lock -u /var/run/post_load_qcawificfg80211_lock

       # Remove DA modules, if no DA chipset found
	[[ -f $device/is_offload ]] || {
		qca_da_needed=1
	}

	if [ $qca_da_needed -eq 0 ]; then
		if [ ! -f /tmp/no_qca_da ]; then
			echo "No Direct-Attach chipsets found." >/dev/console
			rmmod qca_da > /dev/null 2> /dev/null
			rmmod ath_dev > /dev/null 2> /dev/null
			rmmod hst_tx99 > /dev/null 2> /dev/null
			rmmod ath_rate_atheros > /dev/null 2> /dev/null
			rmmod ath_hal > /dev/null 2> /dev/null
			echo 1 > /tmp/no_qca_da
		fi
	fi

	if [ -f "/lib/update_smp_affinity.sh" ]; then
		. /lib/update_smp_affinity.sh
		enable_smp_affinity_wifi $device
	fi
}

create_mlo_config() {
	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	mlo_suppported=$(cat /tmp/sysinfo/board_name | grep -c 'ipq9574')

	if [ $mlo_suppported = 1 ]; then
		case "$board_name" in
		ap-al02-c11)
			cat > /ini/mlo_config.ini <<EOF
mlo_max_num_groups=1

[MLO_GROUP_0]
mlo_max_num_peers=256
mlo_num_chips=4
mlo_soc_chip_ids=0,1,2,3

[MLO_SOC_CHIP_0]
mlo_chip_idx=0
mlo_num_adj_chip=2
mlo_adj_chip_idx=1,3

[MLO_SOC_CHIP_1]
mlo_chip_idx=1
mlo_num_adj_chip=2
mlo_adj_chip_idx=0,2

[MLO_SOC_CHIP_2]
mlo_chip_idx=2
mlo_num_adj_chip=2
mlo_adj_chip_idx=3,1

[MLO_SOC_CHIP_3]
mlo_chip_idx=3
mlo_num_adj_chip=2
mlo_adj_chip_idx=2,0
EOF
			;;
		esac
	fi
}

__detect_nfc() {
	local nfc_support=$(uci -q get misc.nfc.nfc_support)
	if [ -z "$nfc_support" ]; then
		nfc_support=0
	fi
	local dut_inited=$(uci -q get xiaoqiang.common.INITTED)
	if [ -z "$dut_inited" ]; then
		dut_inited=0
	fi
	if [ $nfc_support = 1 ] && [ "$dut_inited" == "0" ]; then
		local nfc_if2g_name=$(uci -q get misc.nfc.if_2g_name)
		local nfc_if5g_name=$(uci -q get misc.nfc.if_5g_name)
		local nfc_pwd="$(getmac lan | tr -d :)""$(head -n10 /dev/urandom | md5sum | cut -c1-20)"
		local nfc_ssid=`nvram get wl0_ssid`
		local nfc_5g_device="wifi1"
		case "$board_name" in
			ap-al02-c6)
				nfc_5g_device="wifi1"
			;;
			ap-al02-c4)
				nfc_5g_device="wifi2"
			;;
		esac
		local dev_macaddr_5g="$(cat /sys/class/net/${nfc_5g_device}/address)"
		local vap_macaddr_5g="$(calcbssid -i3 -m $dev_macaddr_5g)"
cat <<EOF
config wifi-iface 'nfc_2g'
	option device wifi0
	option ifname '$nfc_if2g_name'
	option ssid '${nfc_ssid}_nfc'
	option network 'lan'
	option encryption 'psk2'
	option key '$nfc_pwd'
	option mode 'ap'
	option hidden '1'
	option maxsta '20'
	option disabled '0'
config wifi-iface 'nfc_5g'
	option device '$nfc_5g_device'
	option ifname '$nfc_if5g_name'
	option ssid '${nfc_ssid}_nfc'
	option network 'lan'
	option encryption 'psk2'
	option key '$nfc_pwd'
	option mode 'ap'
	option hidden '1'
	option maxsta '20'
	option disabled '0'
	option macaddr '$vap_macaddr_5g'
EOF
	fi
}
# MIWIFI iot_dev
__detect_iot_device() {
	local iot_dev_support=$(uci -q get misc.features.iot_dev)
	if [ -z "$iot_dev_support" ]; then
		iot_dev_support=0
	fi

	local board_name

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	if [ $iot_dev_support = 1 ]; then
		local iot_dev2g_name=$(uci -q get misc.wireless.wifi5_bk_2G)
		local iot_dev5g_name=$(uci -q get misc.wireless.wifi5_bk_5G)
		local ssid=`nvram get wl0_ssid`
		local device_5g="wifi1"
		local dev_macaddr_5g="$(cat /sys/class/net/${device_5g}/address)"
		local iot5g_macaddr="$(calcbssid -i4 -m $dev_macaddr_5g)"
		local dev_macaddr_2g="$(cat /sys/class/net/wifi0/address)"
		local iot2g_macaddr="$(calcbssid -i4 -m $dev_macaddr_2g)"
cat <<EOF
config wifi-iface 'iot_2g'
	option device wifi0
	option ifname '$iot_dev2g_name'
	option network 'lan'
	option encryption 'mixed-psk'
	option mode 'ap'
	option hidden '0'
	option disabled '1'
	option iotwifi5mode '1'
	option macaddr '$iot2g_macaddr'
config wifi-iface 'iot_5g'
	option device '$device_5g'
	option ifname '$iot_dev5g_name'
	option network 'lan'
	option encryption 'mixed-psk'
	option mode 'ap'
	option hidden '0'
	option disabled '1'
	option iotwifi5mode '1'
	option macaddr '$iot5g_macaddr'
EOF
	fi
}

detect_qcawificfg80211() {
	local enable_cfg80211=`uci show qcacfg80211.config.enable |grep "qcacfg80211.config.enable='0'"`
	[ -n "$enable_cfg80211" ] && echo "qcawificfg80211 configuration is disable" > /dev/console && return 1;

	#is_ftm=`grep wifi_ftm_mode /proc/cmdline | wc -l`
	#[ $is_ftm = 1 ] && ftm_qcawificfg80211 &&  return

	wl0_radio=$(nvram get wl0_radio)
	wl1_radio=$(nvram get wl1_radio)
	wl2_radio=$(nvram get wl2_radio)
	is_ftm=$(cat /proc/xiaoqiang/ft_mode)
	if [ "$is_ftm" = "1" ] && [ "$wl0_radio" != "1" ] && [ "$wl1_radio" != "1" ] && [ "$wl2_radio" != "1" ]; then
		echo "ftm mode" > /dev/console
		ftm_qcawificfg80211 &&  return
	fi

	is_wal=`grep waltest_mode /proc/cmdline | wc -l`
	[ $is_wal = 1 ] && waltest_qcawificfg80211 && return

	config_present=0
	devidx=0
	socidx=0
	olcfg_a=0
	olcfg_ng=0
	olcfg_ac=0
	olcfg_axa=0
	olcfg_axg=0
	nss_olcfg=0
	nss_ol_num=0
	reload=0
	hw_mode_detect=0
	avoid_load=0
	num_chains=0
	is_e_build=0
	local board_name ini_path
	local vap_mode=""

	get_vap_mode

	[ -f /tmp/sysinfo/board_name ] && {
		board_name=ap$(cat /tmp/sysinfo/board_name | awk -F 'ap' '{print$2}')
	}

	if [ "$board_name" = "ap-hk10-c1" ]; then
		update_internal_ini global_i.ini mode_2g_phyb 1
	fi

	if [ "$board_name" = "ap-hk09" ] && [ ! -f "/lib/modules/qca-whunt-modules" ]; then
		update_internal_ini QCA8074V2_i.ini led_gpio_enable_8074 1
	fi

	if [ "$board_name" = "ap-al02-c11" ]; then
		update_internal_ini QCN9224_i.ini ppe_ds_enable 0
	fi

	[ ! -f "/ini/mlo_config.ini" ] && create_mlo_config

	ini_path=$(get_config_file_path "ini")

	for mod in $(cat /lib/wifi/qca-wifi-modules); do
		case ${mod} in
			umac) [ -d /sys/module/${mod} ] && { \
				avoid_load=1
			}
		;;
		esac
	done

	update_ini_reo_remap
	update_ini_napi_scale_factor
	update_ini_refill_ring_size
	update_ini_target_dp_rx_hash_reset
	update_ini_target_dp_default_reo_reset
	update_ini_ppe_vp_core_mask

	if [ "$vap_mode" = "1" ] && [ $1 = "1" ]; then
		[ -f /lib/wifi/.first_time_boot ] && [ -s /etc/config/wireless ] && touch /tmp/event_fast_boot_in_progress
	fi
	load_qcawificfg80211
	if [ "$vap_mode" = "1" ] && [ $1 = "1" ] && [ -f /lib/wifi/.first_time_boot ] && [ -s /etc/config/wireless ]; then
		return
	fi

	config_load wireless
	while :; do
		config_get type "wifi$devidx" type
		[ -n "$type" ] || break
		devidx=$(($devidx + 1))
	done
	cd /sys/class/net
	for soc in $(ls -d soc* 2>&-); do

		if [ -f ${soc}/preferred_hw_mode ]; then
			prefer_hw_mode_id=$(cat ${soc}/preferred_hw_mode)
		elif [ -f ${soc}/hw_modes ]; then
			hw_modes=$(cat ${soc}/hw_modes)
			ini_file=$(cat ${soc}/ini_file)
			case "${hw_modes}" in
				*2G_PHYB:*)
					prefer_hw_mode_id=7;;
				*DBS_SBS:*)
					prefer_hw_mode_id=4;;
				*DBS:*)
					prefer_hw_mode_id=1;;
				*DBS_OR_SBS:*)
					prefer_hw_mode_id=5;;
				*SINGLE:*)
					prefer_hw_mode_id=0;;
				*SBS_PASSIVE:*)
					prefer_hw_mode_id=2;;
				*SBS:*)
					prefer_hw_mode_id=3;;
			esac
		fi
		case ${soc} in
			soc0)
			hw_mode_str="hw_mode_id";;
			*)
			hw_mode_str="hw_mode_id_${soc}";;
		esac
		soc_prefer_hw_mode_id_str=$(grep $hw_mode_str= $ini_path/internal/global_i.ini)
		soc_prefer_hw_mode_id=$(echo $soc_prefer_hw_mode_id_str | awk -F '=' '{print $2}')

		if [ -z "$soc_prefer_hw_mode_id" ]; then
			echo $hw_mode_str=$prefer_hw_mode_id >> $ini_path/internal/global_i.ini
		elif [ $soc_prefer_hw_mode_id -ge 8 ]; then
			update_internal_ini global_i.ini "$hw_mode_str" "$prefer_hw_mode_id"
		fi
	done

	[ -d wifi0 ] || return
	for dev in $(ls -d wifi* 2>&-); do
		found=0
		if [ -f /sys/class/net/${dev}/nssoffload ] && [ $(cat /sys/class/net/${dev}/nssoffload) == "capable" ]; then
			config_nss_wifi_radio_pri_map "$board_name"
		fi

		if [ -f "${dev}/txchains" ] && [ $num_chains -le $(cat ${dev}/txchains) ]; then
			num_chains=$(cat ${dev}/txchains)
		fi

		if [ -f "${dev}/rxchains" ] && [ $num_chains -le $(cat ${dev}/rxchains) ]; then
			num_chains=$(cat ${dev}/rxchains)
		fi

		[ -f ${dev}/is_e_build ] && {
			is_e_build=$(cat ${dev}/is_e_build)
		}

		config_foreach check_qcawifi_device wifi-device
		if [ "$found" -gt 0 ]; then
			config_present=1
			continue
		fi

		hwcaps=$(cat ${dev}/hwcaps)
		case "${hwcaps}" in
			*11a) mode_11=a;;
			*11an) mode_11=na;;
			*11an/ac) mode_11=ac;;
			*11an/ac/ax) mode_11=axa;;
			*11an/ac/ax/be) mode_11=bea;;
			*11abgn/ac) mode_11=ac;;
			*11abgn/ac/ax) mode_11=axa;;
			*11abgn/ac/ax/be) mode_11=bea;;
			*11abgn) mode_11=ng;;
			*11bgn) mode_11=ng;;
			*11bgn/ax) mode_11=axg;;
			*11bgn/ax/be) mode_11=beg;;
			*11/ax) mode_11=axa;;
			*11/ax/be) mode_11=bea;;
		esac
		if [ -f /sys/class/net/${dev}/nssoffload ] && [ $(cat /sys/class/net/${dev}/nssoffload) == "capable" ]; then
			case "${mode_11}" in
				a)
					if [ $olcfg_a -le 2 ]; then
						olcfg_a=$(($olcfg_a + 1))
						nss_olcfg=$(($nss_olcfg|$((1<<$devidx))))
						nss_ol_num=$(($nss_ol_num + 1))
					fi
				;;
				ng)
					if [ $olcfg_ng == 0 ]; then
						olcfg_ng=1
						nss_olcfg=$(($nss_olcfg|$((1<<$devidx))))
						nss_ol_num=$(($nss_ol_num + 1))
					fi
				;;
				na|ac)
					if [ $olcfg_ac == 0 ]; then
						olcfg_ac=1
						nss_olcfg=$(($nss_olcfg|$((1<<$devidx))))
						nss_ol_num=$(($nss_ol_num + 1))
					fi
				;;
				bea|axa)
						if [ $olcfg_axa -le 2 ]; then
								olcfg_axa=$(($olcfg_axa + 1))
								nss_olcfg=$(($nss_olcfg|$((1<<$devidx))))
								nss_ol_num=$(($nss_ol_num + 1))
						fi
				;;
				beg|axg)
						if [ $olcfg_axg == 0 ]; then
								olcfg_axg=1
								nss_olcfg=$(($nss_olcfg|$((1<<$devidx))))
								nss_ol_num=$(($nss_ol_num + 1))
						fi
				;;

			esac
		reload=1
		fi
		#during sysupgrade reload will not be set to 1 as earlier config file is present
		#and NSS offload mode will not come up. To avoid that scenario, we create a file
		#here which will be deleted during sysupgrade and second load can be done based on
		#this check
		touch /lib/wifi/wifi_nss_reload_done
#		cat <<EOF
#config wifi-device  wifi$devidx
#	option type	qcawificfg80211
#	option channel	auto
#	option macaddr	$(cat /sys/class/net/${dev}/address)
#	option hwmode	11${mode_11}
#	# REMOVE THIS LINE TO ENABLE WIFI:
#	option disabled 1
#
#config wifi-iface
#	option device	wifi$devidx
#	option network	lan
#	option mode	ap
#	option ssid	OpenWrt
#	option encryption none

#EOF
#	devidx=$(($devidx + 1))

		wl_if_count=$(uci -q get misc.wireless.wl_if_count)
		devidx24g=0
		radioidx=$devidx
		if [ $devidx = 0 ]; then
			htmode=HT40
			mode=ap
			network=lan
			radioidx=1
			disable=0
			bw=0
		elif [ $devidx = 1 ]; then
			htmode=HT80
			bw=0
			mode=ap
			network=lan
			radioidx=0
			disable=0
		elif [ $wl_if_count = 3 ] && [ $devidx = 2 ]; then
			htmode=HT80
			bw=0
			mode=ap
			network=lan
			disable=0
		else
			htmode=HT20
			bw=20
			mode=sta
			ssid="MIIOT_DEV"
			network=''
			disable=0
		fi
		ssid=`nvram get wl${radioidx}_ssid`
		country_code=`get_bdata_country`
		[ -z "${ssid}" ] && ssid="test"

cat <<EOF
config wifi-device  wifi$devidx
	option type	qcawificfg80211
	option channel	auto
	option macaddr	'$(getmac wifi$devidx)'
	option hwmode	11${mode_11}
	option htmode	'${htmode}'
	option country	'$country_code'
	option disabled '$disable'
	option txpwr 'max'
	option txbf '3'
	option ax '1'
EOF
	if [ -n "$bw" ]; then
cat <<EOF
	option bw '$bw'
EOF
	fi

cat <<EOF
config wifi-iface
	option device	wifi$devidx
	option ifname	'wl$radioidx'
	option network	'$network'
	option mode	'$mode'
	option ssid	'$ssid'
	option encryption none
	option wpsdevicename 'XiaoMiRouter'
	option he_ul_ofdma '0'
	option twt_responder '0'
	option mscs '1'
	option hlos_tidoverride '1'
EOF

	if [ $devidx = 0 ]; then
cat <<EOF
	option amsdu '2'

EOF
	fi

	# 5g band
	if [ $devidx = 1 ]; then
cat <<EOF
	option channel_block_list '52,56,60,64,100,104,108,112,116,120,124,128,132,136,140'
	option miwifi_mesh '1'
EOF
	fi

	# 5g2 band
	if [ $devidx = 2 ]; then
cat <<EOF
	option channel_block_list '52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,165'
	option miwifi_mesh '4'
EOF
	fi
	if [ $devidx = 1 ]; then
cat <<EOF
config wifi-iface 'miot_2G'
	option ifname 'wl13'
	option network 'miot'
	option encryption 'none'
	option device 'wifi$devidx24g'
	option mode 'ap'
	option hidden '1'
	option maxsta '20'
	option ssid '25c829b1922d3123_miwifi'
	option bsd '0'
	option disabled '0'
	option ap_isolate '1'
	option userswitch '1'
EOF
	fi
	devidx=$(($devidx + 1))
	done

	if [ $config_present == 0 ]; then
		# hostap mld
		local mld_dev="$(uci -q get misc.mld.hostap)"
		if [ -n "$mld_dev" ]; then
			local mld_hostap_macaddr="$(mld_macaddr hostap)"
cat <<EOF
config wifi-mld '$mld_dev'
	option mlo_enable '0'
	option mld_macaddr '$mld_hostap_macaddr'
EOF
		fi

		# setup bh_ap
		init_mimesh_backhaul

		__detect_nfc

		__detect_iot_device
	fi

	#config_present 1 indicates that /etc/config/wireless is already having some configuration.
	# In that case we shall not update the olcfg files
	if [ $config_present == 0 ]; then
		case "$board_name" in
		ap-hk*|ap-ac*|ap-oa*|ap-cp*|ap-mp*)
			if [ -f /etc/rc.d/*qca-nss-ecm ]; then
				echo_cmd $nss_olcfg /lib/wifi/wifi_nss_olcfg
				echo_cmd $nss_ol_num /lib/wifi/wifi_nss_olnum
				echo_cmd "$(($olcfg_axa + $olcfg_axg))" /lib/wifi/wifi_nss_hk_olnum
			else
				echo_cmd 0 /lib/wifi/wifi_nss_olcfg
				echo_cmd $nss_ol_num /lib/wifi/wifi_nss_olnum
				echo_cmd "$(($olcfg_axa + $olcfg_axg))" /lib/wifi/wifi_nss_hk_olnum
			fi
			;;
		ap-al*|ap-mi*)
			echo "***Disabling NSS OL for IPQ95xx***" > /dev/console
			echo_cmd 0 /lib/wifi/wifi_nss_olcfg
			echo_cmd $nss_ol_num /lib/wifi/wifi_nss_olnum
			echo_cmd "$(($olcfg_axa + $olcfg_axg))" /lib/wifi/wifi_nss_hk_olnum
			;;
		*)
			echo_cmd $nss_olcfg /lib/wifi/wifi_nss_olcfg
			echo_cmd $nss_ol_num /lib/wifi/wifi_nss_olnum
			;;
		esac
	fi

	if [ $num_chains -le 2 ]; then
		update_internal_ini QCA8074_i.ini dp_mon_2chain_ring 1
		update_internal_ini QCA8074V2_i.ini dp_mon_2chain_ring 1
		update_internal_ini QCA6018_i.ini dp_mon_2chain_ring 1
		update_internal_ini QCA5018_i.ini dp_mon_2chain_ring 1
		update_internal_ini QCN9000_i.ini dp_mon_2chain_ring 1
		update_internal_ini QCN6122_i.ini dp_mon_2chain_ring 1
		update_internal_ini QCN9160_i.ini dp_mon_2chain_ring 1
		update_internal_ini QCA9574_i.ini dp_mon_2chain_ring 1
		update_internal_ini QCN9224_i.ini dp_mon_2chain_ring 1
	elif [ $num_chains -le 4 ]; then
		update_internal_ini QCA8074_i.ini dp_mon_4chain_ring 1
		update_internal_ini QCA8074V2_i.ini dp_mon_4chain_ring 1
		update_internal_ini QCA6018_i.ini dp_mon_4chain_ring 1
		update_internal_ini QCA5018_i.ini dp_mon_4chain_ring 1
		update_internal_ini QCN9000_i.ini dp_mon_4chain_ring 1
		update_internal_ini QCN6122_i.ini dp_mon_4chain_ring 1
		update_internal_ini QCN9160_i.ini dp_mon_4chain_ring 1
		update_internal_ini QCA9574_i.ini dp_mon_4chain_ring 1
		update_internal_ini QCN9224_i.ini dp_mon_4chain_ring 1
	fi

	if [ -e /sys/firmware/devicetree/base/MP_512 ]; then
		update_ini_for_512MP_dp_tx_desc QCA8074_i.ini
		update_ini_for_512MP_dp_tx_desc QCA8074V2_i.ini
		update_ini_for_512MP_dp_tx_desc QCA6018_i.ini
		update_ini_for_512MP_dp_tx_desc QCN9000_i.ini
		update_ini_for_512MP_dp_tx_desc QCA5018_i.ini
		update_ini_for_512MP_dp_tx_desc QCN6122_i.ini
		update_ini_for_512MP_dp_tx_desc QCN9160_i.ini
		update_ini_for_512MP_dp_tx_desc QCA9574_i.ini
		if [ $is_e_build -ne 1 ]; then
			update_ini_for_512MP_P_build QCA8074_i.ini
			update_ini_for_512MP_P_build QCA8074V2_i.ini
			update_ini_for_512MP_P_build QCA6018_i.ini
			update_ini_for_512MP_P_build QCN9000_i.ini
			update_ini_for_512MP_P_build QCA5018_i.ini
			update_ini_for_512MP_P_build QCN6122_i.ini
			update_ini_for_512MP_P_build QCN9160_i.ini
			update_ini_for_512MP_P_build QCA9574_i.ini
		fi
	fi

	case "$board_name" in
		ap-mp*)
			if [ ! -f /sys/firmware/devicetree/base/MP_256 ] && [ ! -f /sys/firmware/devicetree/base/MP_512 ]; then
				update_ini_for_512MP_dp_tx_desc QCA5018_i.ini
				update_ini_for_512MP_dp_tx_desc QCN6122_i.ini
				update_ini_for_512MP_dp_tx_desc QCN9160_i.ini
				update_internal_ini QCA5018_i.ini vdevs_peers_use_512 1
				update_internal_ini QCN6122_i.ini vdevs_peers_use_512 1
				update_internal_ini QCN9160_i.ini vdevs_peers_use_512 1
			fi
			;;
		*)
	esac
	sync

	# Avoid wifi down/up of interfaces in SDX boards as QCMAP takes care of this
	case "$board_name" in
		ap-sdxlemur*)
			return
			;;
		*)
			;;
	esac

	if [ $reload == 1 ] || [ ! -f /lib/wifi/wifi_nss_reload_done ] ; then
		if [ $avoid_load == 1 ]; then
			_wifi_updown "disable" "$2" > /dev/null
			ubus_wifi_cmd "down" "$2"
			scan_wifi
			ubus call network reload
			ubus_wifi_cmd "up" "$2"
			_wifi_updown "enable" "$2" > /dev/null
		else
			unload_qcawificfg80211 > /dev/null
			load_qcawificfg80211 > /dev/null
		fi
	fi

	#start_recovery_daemon

	touch /lib/wifi/.first_time_boot
}

# Handle traps here
trap_qcawifi() {
	# Release any locks taken
	rm -rf /tmp/event_*
	rm -rf /tmp/wifi_load_done
	rm -rf /tmp/vap_up_start
	rm -rf /tmp/this_is_event
	clear_locks
	unlock_wifi
}

son_get_config_qcawificfg80211()
{
    config_load wireless
    local device="$1"
    config_get disabled $device disabled 0
    if [ $disabled -eq 0 ]; then
    config_get vifs $device vifs
    for vif in $vifs; do
        config_get_bool disabled $vif disabled 0
        [ $disabled = 0 ] || continue
        config_get backhaul "$vif" backhaul 0
        config_get mode $vif mode
        config_get ifname $vif ifname
        local macaddr="$(config_get "$device" macaddr)"
        if [ $backhaul -eq 1 ]; then
            echo " $mode $ifname $device $macaddr"  >> /var/run/son.conf
        else
            echo " nbh_$mode $ifname $device $macaddr"  >> /var/run/son.conf
        fi
    done
    fi
}

update_partner_vap() {
	local ifmld=$1
	local adevice=$2

	for ldevice in $gdevice; do
		config_get ldisabled "$ldevice" disabled
		[ "$ldisabled" = "1" ] && {
			continue
		}

		if [ $ldevice = $adevice ]; then
			continue
		fi

		config_get lvifs "$ldevice" vifs
		for lvif in $lvifs; do
			config_get pvifname "$lvif" ifname
			config_get lmld "$lvif" mld
			if [ $ifmld = $lmld ]; then
					hapd "$pvifname" $3
				break
			fi
		done
	done
}

check_mbss_grp_oper() {
	local l_vif="$1"
	local l_dev="$2"
	local mbss_tx_grp="$3"

	if [ -z "$mbss_tx_grp" ]; then
		return
	fi

	config_get vifname "$l_vif" ifname
	grp=$(cfg80211tool $vifname g_mbss_grp)
	grp=${grp##*:}

	if [ -z "$grp" ]; then
		return
	fi

	tx_grp="$l_dev.$grp"
	check_radio_name=$(echo $mbss_tx_grp|grep -c $tx_grp)
	if [ $check_radio_name = 1 ]; then
		mbss_tx_check_var=1
	fi
}

# This API brings down all VDEVs, apply Tx vdev config, and brings up all VDEVs
# if user selects channel as auto, and if tx vdev is not configured in scripts
# then this reset sequence is skipped, in case of recover, mbss tx vdev
# configuration would be invoked though user configures channel as auto
#
mbss_tx_vdev_config() {
	local device="$1"
	local recover="$2"
	local mbss_tx_vdev_config_required=$3
# Empty mbss tx group argument will trigger complete restart on all VDEVS of radio
	local mbss_tx_grp="$4"
	local default_ap_vap=""

	[ $mbss_tx_vdev_config_required -eq 0 ] && {
		echo "Skip bring down/up on all vaps for mbss config"
		return
	}

	config_get disabled $device disabled 0
	if [ $disabled -eq 0 ]; then

		config_get vifs "$device" vifs

		local ifidx=0
		local mbss_tx_vdev_ix=0
		local default_ap_vap=
		local radioidx=${device#wifi}

		for vif in $vifs; do
			config_get mbss_tx_vdev "$vif" mbss_tx_vdev
			config_get mbss_ie_enable qcawifi mbss_ie_enable 0
			config_get band "$device" band 0
			[ -n "$mbss_tx_vdev" ] && mbss_tx_vdev_ix=$ifidx

			if [ -n "$band" -a $band -ge 3 ] || [ "$mbss_ie_enable" != "0" ]; then
				if [ -z "$default_ap_vap" ]; then
					config_get mode "$vif" mode
					if [ $mode = "ap" ]; then
						default_ap_vap=$vif
					fi
				fi
			fi

			ifidx=$(($ifidx + 1))
		done

		if [ $mbss_tx_vdev_ix -eq 0 ]; then
			if [ -n "$default_ap_vap" ]; then
				config_get ifmld "$default_ap_vap" mld
				if [ ! -z $ifmld ]; then
					config_set "$default_ap_vap" mbss_tx_vdev 1
				else
					return
				fi
			else
				return
			fi
		fi

		local icm_enable=0

		config_get_bool icm_enable icm enable 0
		if [ $icm_enable -gt 0 ]; then
			sleep 10
		fi

		acs_state=`cfg80211tool wl${radioidx} get_acs_state \
			| awk -F  ':' '{print $2}'`
		if [ $acs_state -eq 1 ]; then
			sleep 4
		fi

		config_get device_if "$device" device_if "cfg80211tool"
		for vif in $vifs; do
			config_get vifname "$vif" ifname
			config_get mode "$vif" mode
			if [ -n "$mbss_tx_grp" ]; then
				check_mbss_grp_oper "$vif" "$device" "$mbss_tx_grp"
				if [ $mbss_tx_check_var = 0 ]; then
					continue;
				fi
			fi
			if [ $mode = "ap_smart_monitor" ]
			then
				ifconfig "$vifname" down
			else
				hapd "$vifname" disable
				config_get ifmld "$vif" mld
				if [ ! -z $ifmld ]; then
					update_partner_vap $ifmld $device disable
				fi
			fi
			mbss_tx_check_var=0
		done

		for vif in $vifs; do
			config_get vifname "$vif" ifname
			config_get mbss_tx_vdev "$vif" mbss_tx_vdev
			[ -n "$mbss_tx_vdev" ] && "$device_if" "$vifname" mbss_tx_vdev "$mbss_tx_vdev"
		done

		for vif in $vifs; do
			config_get vifname "$vif" ifname
			config_get mode "$vif" mode
			if [ -n "$mbss_tx_grp" ]; then
				check_mbss_grp_oper "$vif" "$device" "$mbss_tx_grp"
				if [ $mbss_tx_check_var = 0 ]; then
					continue;
				fi
			fi
			if [ $mode = "ap_smart_monitor" ]
			then
				ifconfig "$vifname" up
			else
				hapd "$vifname" enable
				config_get ifmld "$vif" mld
				if [ ! -z $ifmld ]; then
					update_partner_vap $ifmld $device enable
				fi
			fi
			mbss_tx_check_var=0
		done
	fi
}

skip_network_restart() {
	skip_network="0"

	get_vap_mode
	[ "$vap_mode" = "0" ] && return

	if [ ! -f /tmp/skip_network_restart_done ]; then
		touch /tmp/skip_network_restart_done
		skip_network="1"
	fi
	return
}

pre_wifi_updown() {
	lock_wifi
}

post_wifi_updown() {
	unlock_wifi
}

pre_wifi_reload_legacy() {
	skip_network_restart
	if [ $skip_network = "1" ]; then
		echo Skip network restart cmd > /dev/ksmg
		exit 0
	fi
	lock_wifi
}

post_wifi_reload_legacy() {
	unlock_wifi
}

pre_wifi_unload() {
	lock_wifi
}

post_wifi_unload() {
	unlock_wifi
}

pre_wifi_load() {
	lock_wifi
}

post_wifi_load() {
	unlock_wifi
}

pre_wifi_config() {
	lock_wifi
}

post_wifi_config() {
	unlock_wifi
}
