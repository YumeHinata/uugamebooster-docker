#
# Copyright (c) 2022-2023 Qualcomm Technologies, Inc.
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#
#!/bin/sh
#

#Increase Max skb recycler buffer count per CPU pool
echo "16384" > /proc/net/skb_recycler/max_skbs

#Enable PPE RFS feature for fair flow round robin across all CPUs
echo 1 > /sys/sfe/ppe_rfs_feature

#Configure System CPU to Max clock speed
echo "performance" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo "performance" > /sys/devices/system/cpu/cpu1/cpufreq/scaling_governor
echo "performance" > /sys/devices/system/cpu/cpu2/cpufreq/scaling_governor
echo "performance" > /sys/devices/system/cpu/cpu3/cpufreq/scaling_governor

#Disable WLAN extended Statistics collection
cfg80211tool wifi0 enable_ol_stats 0
cfg80211tool wifi1 enable_ol_stats 0
cfg80211tool wifi2 enable_ol_stats 0
cfg80211tool wifi3 enable_ol_stats 0

#Flushout stale accelerated connections if any
echo 1 > /sys/kernel/debug/ecm/ecm_db/defunct_all
echo f > /proc/net/nf_conntrack

#Disable QDISCs on egress interfaces
tc qdisc replace dev eth0 root noqueue
tc qdisc replace dev eth1 root noqueue
tc qdisc replace dev eth4 root noqueue
tc qdisc replace dev eth5 root noqueue
tc qdisc replace dev ath0 root noqueue
tc qdisc replace dev ath1 root noqueue
tc qdisc replace dev ath2 root noqueue
tc qdisc replace dev wifi0 root noqueue
tc qdisc replace dev wifi1 root noqueue
tc qdisc replace dev wifi2 root noqueue

#Disable Generic receive offload(GRO) on interfaces
ethtool -K eth0 gro off
ethtool -K eth1 gro off
ethtool -K eth4 gro off
ethtool -K eth5 gro off
ethtool -K ath0 gro off
ethtool -K ath1 gro off
ethtool -K ath2 gro off

/etc/init.d/firewall disable
/etc/init.d/firewall stop

#Disable Wdiag log
cfg80211tool wifi0 dl_loglevel 0xffff0006
cfg80211tool wifi1 dl_loglevel 0xffff0006
cfg80211tool wifi2 dl_loglevel 0xffff0006
cfg80211tool wifi0 dcs_enable 0
cfg80211tool wifi1 dcs_enable 0
cfg80211tool wifi2 dcs_enable 0

#Enable flow control on ethernet interfaces
ssdk_sh port flowctrl set 1 enable
ssdk_sh port flowctrl set 2 enable
ssdk_sh port flowctrl set 3 enable
ssdk_sh port flowctrl set 4 enable
ssdk_sh port flowctrl set 5 enable
ssdk_sh port flowctrl set 6 enable
ssdk_sh port autoneg restart 1
ssdk_sh port autoneg restart 2
ssdk_sh port autoneg restart 3
ssdk_sh port autoneg restart 4
ssdk_sh port autoneg restart 5
ssdk_sh port autoneg restart 6
