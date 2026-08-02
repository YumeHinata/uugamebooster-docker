#!/bin/sh

if_2g=$(uci -q get misc.wireless.ifname_2G)
if_5g=$(uci -q get misc.wireless.ifname_5G)
guest_2G=$(uci -q get misc.wireless.guest_2G)
guest_5G=$(uci -q get misc.wireless.guest_5G)
wifi5_bk_2g=$(uci -q get misc.wireless.wifi5_bk_2G)
wifi5_bk_5g=$(uci -q get misc.wireless.wifi5_bk_5G)

status=$(uci -q get wireless.$if_5g.macfilter)
if [ -z "$status" ]; then
    status=$(uci -q get wireless.$if_2g.macfilter)
fi
maclist=$(uci -q get wireless.$if_5g.maclist)
if [ -z "$maclist" ]; then
    maclist=$(uci -q get wireless.$if_2g.maclist)
fi

#先清掉maclist表项
iwpriv $if_2g maccmd_sec 3
iwpriv $if_5g maccmd_sec 3

if [ -n "guest_2G" ]; then
    ifconfig $guest_2G > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        if_guest2G_exit="0"
    else
        if_guest2G_exit="1"
        iwpriv $guest_2G maccmd_sec 3
    fi
fi

if [ -n "guest_5G" ]; then
    ifconfig $guest_5G > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        if_guest5G_exit="0"
    else
        if_guest5G_exit="1"
        iwpriv $guest_5G maccmd_sec 3
    fi
fi

if [ -n "wifi5_bk_2g" ]; then
    ifconfig $wifi5_bk_2g > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        if_wifi5_bk_2g_exit="0"
    else
        if_wifi5_bk_2g_exit="1"
        iwpriv $wifi5_bk_2g maccmd_sec 3
    fi
fi

if [ -n "wifi5_bk_5g" ]; then
    ifconfig $wifi5_bk_5g > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        if_wifi5_bk_5g_exit="0"
    else
        if_wifi5_bk_5g_exit="1"
        iwpriv $wifi5_bk_5g maccmd_sec 3
    fi
fi

#设置黑名单
if [ "$status" == "deny" ]; then
    iwpriv $if_2g maccmd_sec 2
    iwpriv $if_5g maccmd_sec 2
    [ "$if_guest2G_exit" = "1" ] && iwpriv $guest_2G maccmd_sec 2
    [ "$if_guest5G_exit" = "1" ] && iwpriv $guest_5G maccmd_sec 2
    [ "$if_wifi5_bk_2g_exit" = "1" ] && iwpriv $wifi5_bk_2g maccmd_sec 2
    [ "$if_wifi5_bk_5g_exit" = "1" ] && iwpriv $wifi5_bk_5g maccmd_sec 2

    for mac in $maclist ; do
        iwpriv $if_2g addmac_sec "$mac"
        iwpriv $if_5g addmac_sec "$mac"
        iwpriv $if_2g kickmac "$mac"
        iwpriv $if_5g kickmac "$mac"
        if [ "$if_guest2G_exit" == "1" ]; then
            iwpriv $guest_2G addmac_sec "$mac"
            iwpriv $guest_2G kickmac "$mac"
        fi
        if [ "$if_guest5G_exit" == "1" ]; then
            iwpriv $guest_5G addmac_sec "$mac"
            iwpriv $guest_5G kickmac "$mac"
        fi
        if [ "$if_wifi5_bk_2g_exit" == "1" ]; then
            iwpriv $wifi5_bk_2g addmac_sec "$mac"
            iwpriv $wifi5_bk_2g kickmac "$mac"
        fi
        if [ "$if_wifi5_bk_5g_exit" == "1" ]; then
            iwpriv $wifi5_bk_5g addmac_sec "$mac"
            iwpriv $wifi5_bk_5g kickmac "$mac"
        fi
    done
elif [ "$status" == "allow" ]; then
    iwpriv $if_2g maccmd_sec 1
    iwpriv $if_5g maccmd_sec 1
    if [ "$if_guest2G_exit" == "1" ]; then
        iwpriv $guest_2G maccmd_sec 0
    fi
    if [ "$if_guest5G_exit" == "1" ]; then
        iwpriv $guest_5G maccmd_sec 0
    fi
    if [ "$if_wifi5_bk_2g_exit" == "1" ]; then
        iwpriv $wifi5_bk_2g maccmd_sec 1
    fi
    if [ "$if_wifi5_bk_5g_exit" == "1" ]; then
        iwpriv $wifi5_bk_5g maccmd_sec 1
    fi
    for mac in $maclist ; do
        iwpriv $if_2g addmac_sec "$mac"
        iwpriv $if_5g addmac_sec "$mac"
    done
    #踢掉5G不在白名单里的在线关联终端
    online_maclist=$(iwinfo $if_5g a | grep MBit/s | awk '{print $1}')
    for online_mac in $online_maclist ; do
        is_in_whitelist="0"
        for mac in $maclist ; do
            if [ "$mac" == "$online_mac" ]; then
                is_in_whitelist="1"
            fi
        done
        if [ "$is_in_whitelist" != "1" ]; then
            iwpriv $if_5g kickmac "$online_mac"
        fi
    done
    #踢掉2G不在白名单里的在线关联终端
    online_maclist=$(iwinfo $if_2g a | grep MBit/s | awk '{print $1}')
    for online_mac in $online_maclist ; do
        is_in_whitelist="0"
        for mac in $maclist ; do
            if [ "$mac" == "$online_mac" ]; then
                is_in_whitelist="1"
            fi
        done
        if [ "$is_in_whitelist" != "1" ]; then
            iwpriv $if_2g kickmac "$online_mac"
        fi
    done
else
    iwpriv $if_2g maccmd_sec 0
    iwpriv $if_5g maccmd_sec 0
    if [ "$if_guest2G_exit" == "1" ]; then
        iwpriv $guest_2G maccmd_sec 0
    fi
    if [ "$if_guest5G_exit" == "1" ]; then
        iwpriv $guest_5G maccmd_sec 0
    fi
    if [ "$if_wifi5_bk_2g_exit" == "1" ]; then
        iwpriv $wifi5_bk_2g maccmd_sec 0
    fi
    if [ "$if_wifi5_bk_5g_exit" == "1" ]; then
        iwpriv $wifi5_bk_5g maccmd_sec 0
    fi
fi

