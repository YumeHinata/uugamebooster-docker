#!/bin/sh
# Copyright (C) 2020 Xiaomi

#update mesh config in xiaoqiang
version_list=$(uci -q get misc.mesh.version)
if [ -z "$version_list" ]; then
    return
fi

old_version=$(uci -q get xiaoqiang.common.MESH_VERSION)

max_version=1
for version in $version_list; do
    if [ $version -gt $max_version ]; then
        max_version=$version
    fi
done

uci set xiaoqiang.common.MESH_VERSION="$max_version"

wiface_list=""
bh_mlo_support=$(mesh_cmd bh_mlo_support)
if [ "$bh_mlo_support" = "1" ]; then
    mesh_iface="$(mesh_cmd mesh_iface bh_ap)"
    for iface in $mesh_iface; do
        tmp_iface=$(uci show wireless | grep -w "ifname=\'$iface\'" | awk -F"." '{print $2}')
        [ -z "$tmp_iface" ] && continue
        if [ -n "$wiface_list" ]; then
            wiface_list="$wiface_list $tmp_iface"
        else
            wiface_list="$tmp_iface"
        fi
    done
else
    bh_band=$(mesh_cmd backhaul get band)
    backhaul_ifname="$(uci -q get misc.backhauls.backhaul_${bh_band}_ap_iface)"
    wiface_list="$(uci show wireless | grep -w "ifname=\'$backhaul_ifname\'" | awk -F"." '{print $2}')"
fi

netmod=$(uci -q get xiaoqiang.common.NETMODE)
if [ -z "$old_version" ] && [ "$netmod" = "whc_cap" -o "$netmod" = "whc_re" ]; then
    uci set xiaoqiang.common.CAP_MODE="router"
    for iface in $wiface_list; do
        if [ "$netmod" = "whc_cap" ]; then
            uci set wireless.$iface.mesh_aplimit='9'
        fi
        uci set wireless.$iface.mesh_ver="$max_version"

        lanmac=$(uci -q get network.lan.macaddr)
        uci set wireless.$iface.mesh_apmac="$lanmac"

        uci -q delete wireless.$iface.macfilter
        uci -q delete wireless.$iface.maclist
    done
    uci commit wireless

    #generate NETWORK_ID FROM backhaul ap ssid
    tmp_iface=$(echo "$wiface_list" | awk '{print $1}')
    network_id="`uci -q get wireless.$iface.ssid | md5sum | cut -c 1-8`"
    uci set xiaoqiang.common.NETWORK_ID="$network_id"
fi

uci commit xiaoqiang

cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)
[ -z "$cap_mode" ] && cap_mode="router"
if [ "$netmod" = "whc_cap" -o "$netmod" = "whc_re" -o "$netmod" = "lanapmode" -a "$cap_mode" = "ap" ]; then
    for iface in $wiface_list; do
        uci -q delete wireless.$iface.macfilter
        uci -q delete wireless.$iface.maclist
    done
    uci commit wireless
fi
