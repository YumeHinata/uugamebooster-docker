#!/bin/sh

add_key_val()
{
    local table="$1"
    local key="$2"
    local val=$(echo $table | awk -v k="$key" 'BEGIN { RS=";" } $1 ~ k { split($0, a, "="); print a[2] }')
    if [ -z "$val" ]; then
        val=0
        table="$table$key=$val;"
    else
        val=$(($val + 1))
        table=$(echo "$table" | sed "s/$key=[^;]*/$key=$val/g")
    fi
    echo "$table"
}

wifi_onlines()
{
    local wifi_count=0
    local ifname_count=0
    local mld_count=0
    local ifname_list=""
    local assoc_mld_string=""
    local mld_table=""
    local mld_mac=""
    local iwinfo_string=""

    local mlo_support=$(uci -q get misc.features.mlo_support)

    local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
    [ -n "$ifname_2g" ] && ifname_list="$ifname_list $ifname_2g"

    local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
    [ -n "$ifname_5g" ] && ifname_list="$ifname_list $ifname_5g"

    local ifname_5gh=$(uci -q get misc.wireless.ifname_5GH)
    [ -n "$ifname_5gh" ] && ifname_list="$ifname_list $ifname_5gh"

    local ifname_6g=$(uci -q get misc.wireless.ifname_6G)
    [ -n "$ifname_6g" ] && ifname_list="$ifname_list $ifname_6g"

    local ifname_guest_2g=$(uci -q get misc.wireless.ifname_guest_2G)
    [ -n "$ifname_guest_2g" ] && ifname_list="$ifname_list $ifname_guest_2g"

    local ifname_guest_5g=$(uci -q get misc.wireless.ifname_guest_5G)
    [ -n "$ifname_guest_5g" ] && ifname_list="$ifname_list $ifname_guest_5g"

    local mlo_vap_support=$(uci -q get misc.features.mlo_vap_support)
    local iot_vap_support=$(uci -q get misc.features.iot_dev)

    [ "$mlo_vap_support" = '1' ] && {
        local ifname_mlo_2g=$(uci -q get misc.wireless.ifname_mlo_2G)
        [ -n "$ifname_mlo_2g" ] && ifname_list="$ifname_list $ifname_mlo_2g"

        local ifname_mlo_5g=$(uci -q get misc.wireless.ifname_mlo_5G)
        [ -n "$ifname_mlo_5g" ] && ifname_list="$ifname_list $ifname_mlo_5g"

        local ifname_mlo_5gh=$(uci -q get misc.wireless.ifname_mlo_5GH)
        [ -n "$ifname_mlo_5gh" ] && ifname_list="$ifname_list $ifname_mlo_5gh"

        local ifname_mlo_6g=$(uci -q get misc.wireless.ifname_mlo_6G)
        [ -n "$ifname_mlo_6g" ] && ifname_list="$ifname_list $ifname_mlo_6g"
    }

    [ "$iot_vap_support" = '1' ] && {
        local ifname_iot_2g=$(uci -q get misc.wireless.wifi5_bk_2G)
        [ -n "$ifname_iot_2g" ] && ifname_list="$ifname_list $ifname_iot_2g"

        local ifname_iot_5g=$(uci -q get misc.wireless.wifi5_bk_5G)
        [ -n "$ifname_iot_5g" ] && ifname_list="$ifname_list $ifname_iot_5g"
    }

    for ifname in $ifname_list; do
        iwinfo_string=$(iwinfo $ifname a 2>>/dev/null)
        [ -z "$iwinfo_string" ] && continue

        ifname_count=$(echo "$iwinfo_string" | grep stacount | awk '{print $2}')
        [ -z "$ifname_count" ] && ifname_count=0
        wifi_count=$((wifi_count + ifname_count))

        if [ x"$mlo_support" = x'1' ]; then
            assoc_mld_string=$(echo "$iwinfo_string" | sed '1,7d'| grep -iE '[a-f0-9:]{17}.*[a-f0-9:]{17}.*' | sed -E 's/^([a-f0-9:]{17}).*([a-f0-9:]{17}).*/\1 \2/i' | awk -F" " '{print $2}' | tr '\n' ' ')
            for mld_mac in ${assoc_mld_string}; do
                mld_table=$(add_key_val "$mld_table" "$mld_mac")
            done
        fi
    done
    if [ -n "$mld_table" ]; then
        mld_count=$(echo "$mld_table" | awk -F'=' '{sum+=$2} END{print sum}')
        wifi_count=$((wifi_count - mld_count))
    fi
    echo $wifi_count
}

# TODO: 有线下挂设备存在多种特殊情况，目前未包含，具体方案待定
# 可以通过brctl showmacs获取设备总数，需要过滤掉无线设备、re子节点（有线组网）
# 但无法处理re和sta同时通过交换机接入cap/re的情况
eth_onlines()
{
    local count=$(/sbin/online_clients_wired.lua 2>>/dev/null)
    [ -z "$count" ] && count=0
    echo "$count"
}

all_onlines()
{
    local wifi_stations=$(wifi_onlines)
    local eth_stations=$(eth_onlines)
    local onlines=$((wifi_stations + eth_stations))

    echo $onlines
}

case $1 in
    all_onlines)
        all_onlines
        return 0
        ;;
    wifi_onlines)
        wifi_onlines
        return 0
        ;;
    *) # default return all_onlines
        all_onlines
        return 0
        ;;
esac
