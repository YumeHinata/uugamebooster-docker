#!/bin/sh
# Copyright (C) 2016 Xiaomi
#

# for d01/r3600, called by trafficd handle whc_sync

USE_ENCODE=1

mesh_version=$(uci -q get xiaoqiang.common.MESH_VERSION)
cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)
if [ "$ap_mode" = "whc_cap" ] || [ "$mesh_version" -ge "2" -a "$ap_mode" = "lanapmode" -a "$cap_mode" = "ap" ]; then
    exit 0
fi

[ $mesh_version -gt 1 ] && {
    . /lib/mimesh/mimesh_public.sh
} || {
    . /lib/xqwhc/xqwhc_public.sh
}

xqwhc_lock="/var/run/xqwhc_wifi.lock"
cfgf_origin="/var/run/xq_whc_sync"
pid=$$
cfgf="${cfgf_origin}_${pid}"
cfgf_fake="/var/run/xq_whc_sync_fake"
gst_disab_changed=0
gst_vlan_changed=0
son_changed=0   # wifi change, need wifi reset
sys_changed=0
miscan_changed=0
iot_switch_changed=0
nfc_changed=0
ax_changed=0
bsd_changed=0
B64_ENC=0

GUEST_SUPPORT="$(uci -q get misc.mesh.guest)"
NFC_SUPPORT="$(uci -q get misc.nfc.nfc_support)" # nfc_support

__wifi_parse_iface()
{
    local band="$1"
    local ifname="$2"
    local cfg_suffix="$3"

    [ -z "$band" -o -z "$cfg_suffix" -o -z "$ifname" ] && return
    local iface=$(uci show wireless | grep "ifname=\'$ifname\'" | awk -F"." '{print $2}')
    [ -z "$iface" ] && return
    local mode=$(uci -q get wireless.$iface.mode)

    local ssid_enc="`cat $cfgf | grep -w "ssid_${cfg_suffix}" | awk -F ":=" '{print $2}'`"
    local pswd_enc="`cat $cfgf | grep -w "pswd_${cfg_suffix}" | awk -F ":=" '{print $2}'`"
    local ssid="$ssid_enc"
    local pswd="$pswd_enc"
    if [ "$USE_ENCODE" -gt 0 ]; then
        ssid="$(base64_dec "$ssid_enc")"
        pswd="$(base64_dec "$pswd_enc")"
    fi
    local mgmt="`cat $cfgf | grep -w "mgmt_${cfg_suffix}" | awk -F ":=" '{print $2}'`"
    local hidden="`cat $cfgf | grep -w "hidden_${cfg_suffix}" | awk -F ":=" '{print $2}'`"
    local disabled="`cat $cfgf | grep -w "disabled_${cfg_suffix}" | awk -F ":=" '{print $2}'`"
    local bsd="`cat $cfgf | grep -w "bsd_${cfg_suffix}" | awk -F ":=" '{print $2}'`"
    local sae="`cat $cfgf | grep -w "sae_${cfg_suffix}" | awk -F ":=" '{print $2}'`"
    local sae_pswd_enc="`cat $cfgf | grep -w "sae_passwd_${cfg_suffix}" | awk -F ":=" '{print $2}'`"
    local sae_pswd="$sae_pswd_enc"
    local twt="$(cat $cfgf | grep -w "twt" | awk -F ":=" '{print $2}')"
    if [ "$USE_ENCODE" -gt 0 ]; then
        sae_pswd="$(base64_dec "$sae_pswd_enc")"
    fi
    local ieee80211w="`cat $cfgf | grep -w "ieee80211w_${cfg_suffix}" | awk -F ":=" '{print $2}'`"

    [ -z "$ssid" ] && {
        WHC_LOGE " xq_whc_sync, wifi options ${band} ssid invalid ignore!"
        cp "$cfgf" "$cfgf_fake"
        return 1
    }

    ssid_cur="`uci -q get wireless.$iface.ssid`"
    pswd_cur="`uci -q get wireless.$iface.key`"
    [ -z "pswd_cur" ] && pswd_cur=""
    mgmt_cur="`uci -q get wireless.$iface.encryption`"
    hidden_cur="`uci -q get wireless.$iface.hidden`"
    [ -z "$hidden_cur" ] && hidden_cur=0
    disabled_cur="`uci -q get wireless.$iface.disabled`"
    [ -z "$disabled_cur" ] && disabled_cur=0
    local bsd_cur="`uci -q get wireless.$iface.bsd`"
    [ -z "$bsd_cur" ] && bsd_cur=0
    local sae_cur="`uci -q get wireless.$iface.sae`"
    [ -z "$sae_cur" ] && sae_cur=""
    local sae_pswd_cur="`uci -q get wireless.$iface.sae_password`"
    [ -z "$sae_pswd_cur" ] && sae_pswd_cur=""
    local ieee80211w_cur="`uci -q get wireless.$iface.ieee80211w`"
    [ -z "$ieee80211w_cur" ] && ieee80211w_cur=""
    local twt_cur="$(uci -q get wireless.$iface.twt_responder)"
    [ -z "$twt_cur" ] && twt_cur=""

    [ "$ssid_cur" != "$ssid" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, ${band} ssid change $ssid_cur -> $ssid"
        uci set wireless.$iface.ssid="$ssid"
    }
    [ "$pswd_cur" != "$pswd" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, ${band} pswd change $pswd_cur -> $pswd"
        if [ -n "$pswd" ]; then
           uci set wireless.$iface.key="$pswd"
        else
           uci -q delete wireless.$iface.key
        fi
    }
    [ "$mgmt_cur" != "$mgmt" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, ${band} mgmt change $mgmt_cur -> $mgmt"
        uci set wireless.$iface.encryption="$mgmt"
    }
    [ "$hidden_cur" != "$hidden" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, ${band} hidden change $hidden_cur -> $hidden"
        uci set wireless.$iface.hidden="$hidden"
    }

    if [ "$mode" = "ap" ]; then
        [ "$disabled_cur" != "$disabled" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, ${band} disabled change $disabled_cur -> $disabled"
            uci set wireless.$iface.disabled="$disabled"
            if [ "$band" = "2g" ]; then
                uci set wireless.miot_2G.disabled="$disabled"
            fi
        }
        [ "$bsd" != "$bsd_cur" ] && {
             son_changed=1
             WHC_LOGI " xq_whc_sync, ${band} bsd change $bsd_cur -> $bsd"
             uci set wireless.$iface.bsd="$bsd"
             uci set lbd.config.PHYBasedPrioritization="$bsd"
             uci commit lbd
             bsd_changed=1
        }
    fi

    [ "$sae" != "$sae_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, ${band} sae change $sae_cur -> $sae"
         if [ -n "$sae" ];then
            uci set wireless.$iface.sae="$sae"
         else
            uci -q delete wireless.$iface.sae
         fi
    }
    [ "$sae_pswd" != "$sae_pswd_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, ${band} sae password change $sae_pswd_cur -> $sae_pswd"
         if [ -n "$sae_pswd" ];then
            uci set wireless.$iface.sae_password="$sae_pswd"
         else
            uci -q delete wireless.$iface.sae_password
         fi
    }
    [ "$ieee80211w" != "$ieee80211w_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, ${band} ieee80211w change $ieee80211w_cur -> $ieee80211w"
         if [ -n "$ieee80211w" ];then
            uci set wireless.$iface.ieee80211w="$ieee80211w"
         else
            uci -q delete wireless.$iface.ieee80211w
         fi
    }
    [ -n "$twt" ] && [ "$twt" != "$twt_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, ${band} twt change $twt_cur -> $twt"
        uci set wireless.$iface.twt_responder="$twt"
    }
}

__wifi_parse_ap_iface()
{
    local band="$1"
    local cfg_suffix="$2"
    local band_upcase="$(echo "$band" | tr '[a-z]' '[A-Z]')"

    [ -z "$band" -o -z "$cfg_suffix" ] && return
    local ifname=$(uci -q get misc.wireless.ifname_${band_upcase})

    __wifi_parse_iface "$band" "$ifname" "$cfg_suffix"
}

__wifi_parse_sta_iface()
{
    local band="$1"
    local ifname="$2"
    local cfg_suffix="$3"

    [ -z "$band" -o -z "$ifname" -o -z "$cfg_suffix" ] && return

    local backhauls="$(mesh_cmd backhaul get band)"
    local flag="$(echo $backhauls | grep "$band")"
    local uplink_backhaul_ap="`uci -q show misc.backhauls.backhaul_${band}_ap_iface|awk -F "'" '{print $2}'`"
    if [ -n "$flag" -a "$uplink_backhaul_ap" == "$ifname" ];then
        local backhaul_sta="`uci show misc.backhauls.backhaul_${band}_sta_iface|awk -F "'" '{print $2}'`"
        __wifi_parse_iface "$band" "$backhaul_sta" "$cfg_suffix"
    fi
}

__wifi_parse_device()
{
    local band="$1"
    local suffix="$2"
    local band_upcase="$(echo $band | tr '[a-z]' '[A-Z]')"
    local bh_band="$(mesh_cmd backhaul get band)"
    local mlo_support="$(mesh_cmd mlo_support)"
    local is_mlo_bhlink=$(mesh_cmd is_mlo_bhlink)

    [ -z "$band" -o -z "$suffix" ] && return
    local device=$(uci -q get misc.wireless.if_${band_upcase})
    local ifname=$(uci -q get misc.wireless.ifname_${band_upcase})
    [ -z "$device" -o -z "$ifname" ] && return

    local txp="`cat $cfgf | grep -w "txpwr_${suffix}" | awk -F ":=" '{print $2}'`"
    local bw="`cat $cfgf | grep -w "bw_${suffix}" | awk -F ":=" '{print $2}'`"
    local bw_auto="`cat $cfgf | grep -w "bw_${suffix}_auto" | awk -F ":=" '{print $2}'`"
    [ "$bw_auto" = "1" ] && bw=0
    local txbf="`cat $cfgf | grep -w "txbf_${suffix}" | awk -F ":=" '{print $2}'`"
    local ax="`cat $cfgf | grep -w "ax_${suffix}" | awk -F ":=" '{print $2}'`"
    local txp_cur="`uci -q get wireless.$device.txpwr`"
    [ -z "$txp_cur" ] && txp_cur="max"
    local ch_cur="`uci -q get wireless.$device.channel`"
    [ -z "$ch_cur" -o "0" = "$ch_cur" ] && ch_cur="auto"
    local bw_cur="`uci -q get wireless.$device.bw`"
    [ -z "$bw_cur" ] && bw_cur=0
    local txbf_cur="`uci -q get wireless.$device.txbf`"
    [ -z "$txbf_cur" ] && txbf_cur=3
    local ax_cur="`uci -q get wireless.$device.ax`"
    [ -z "$ax_cur" ] && ax_cur=1

    local ch_adj_support=$(uci -q get misc.features.ch_adj_support)
    [ "$ch_adj_support" == "1" ] && {
        local ch_adj_en_cur="`uci -q get wireless.$device.ch_adj_en`"
        [ -z "$ch_adj_en_cur" ] && ch_adj_en_cur=0
    }
    local bh_en_cur=$(uci -q get xiaoqiang.common.bhap_enable)

    # cap is dual, and re is tri
    # re's non-backhaul channel fixed to 36 or 149
    if [ $cap_is_dual -eq 1 ] && [ $re_is_tri_band -eq 1 ]\
            && [ "$band" != "$bh_band" ] && [ "$band" != "2g" ]; then

        local bhsta_mlo=" $(uci -q get wireless.bh_sta_mlo.mlo) "
        if [ "$is_mlo_bhlink" = "1" ] \
                && [ "${bhsta_mlo##* $band}" != "$bhsta_mlo" ]; then
            # mlo(5g+5gh) not to sync channel while band in bhsta_mlo
            ch=$ch_cur

            # not to sync bw, while band is mlo backhaul
            bw=$bw_cur
        else
            [ "$band" = "5g" ] && ch=36 || ch=149

            # bw change to auto at non-backhaul band
            bw=0
        fi
    else
        local ch="`cat $cfgf | grep -w "ch_${suffix}" | awk -F ":=" '{print $2}'`"
        [ -z "$ch" -o "0" = "$ch" ] && ch="auto"
        if [ "$ch_adj_support" == "1" ]; then
            local ch_adj_en="`cat $cfgf | grep -w "ch${suffix}_adj_en" | awk -F ":=" '{print $2}'`"
            [ -z "$ch_adj_en" ] && ch_adj_en=0
        fi
    fi

    if [ "$ch_adj_support" == "1" -a "$ch_adj_en" != "$ch_adj_en_cur" ]; then
        uci -q set wireless.$device.ch_adj_en="$ch_adj_en"
    fi

    #1.AC默认会传bh_en=0，AP默认是bh_en=0
    #2.如果上级是老产品cap,默认不传bh_en的配置，需要开启AP的bh
    #3.如果上级是ac,检测到RE存在，则会传bh_en=1，AP需要开启bh
    local bh_en="`cat $cfgf | grep -w "bh_en" | awk -F ":=" '{print $2}'`"
    if [ -z "$bh_en" ] || [ "$bh_en" = "1" -a "$bh_en_cur" = "0" ]; then
        /usr/sbin/mesh_bh_enable
    fi

    if [ "$ch" != "$ch_cur" ]; then
        uci set wireless.$device.channel="$ch"
        #如果开启异信道布网，配置固定信道，不需要重新设置信道给驱动，只修改uci配置
        if [ "$ch_adj_support" == "1" ]; then
            [ "$ch_adj_en" == "1" ] || son_changed=1
        else
            son_changed=1
        fi

        WHC_LOGI " xq_whc_sync, $device dev change channel $ch_cur -> $ch "
    fi

    [ "$txp" != "$txp_cur" -o "$bw" != "$bw_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device dev change $txp_cur:$bw_cur -> $txp:$bw "
        uci set wireless.$device.txpwr="$txp"
        uci set wireless.$device.bw="$bw"
    }

    [ -n "$txbf" -a "$txbf" -ne "$txbf_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device dev change txbf [$txbf_cur] -> [$txbf]"
        uci set wireless.$device.txbf="$txbf"
    }
    [ -n "$ax" -a "$ax" -ne "$ax_cur" ] && {
        ax_changed=1
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device dev change ax [$ax_cur] -> [$ax]"
        uci set wireless.$device.ax="$ax"
    }
}

__wifi_bh_band()
{
    cfg_5g_suffix=""
    cfg_5gh_suffix=""
    cap_type="$(cat $cfgf | grep -w "dev_type" | awk -F ":=" '{print $2}')"
    local iface_cfg_swap="$(cat $cfgf | grep -w "iface_5g_swap" | awk -F ":=" '{print $2}')"

    if [ -z "$cap_type" ]; then
        local nbh_exist="$(cat $cfgf | grep "5g_nbh" | wc -l)"
        [ $nbh_exist -eq 0 ] && cap_type="dual" || cap_type="tri"
    fi

    cap_is_dual=0
    re_is_tri_band=$(mesh_cmd is_tri_band)
    if [ "$re_is_tri_band" = "1" ]; then
        local cur_bh_band=$(mesh_cmd backhaul get band)
        local new_bh_band="$(cat $cfgf | grep -w "bh_band" | awk -F ":=" '{print $2}')"
        local cur_bhap_ifname=$(uci -q get misc.backhauls.backhaul_${cur_bh_band}_ap_iface)
        local new_bhap_ifname=$(uci -q get misc.backhauls.backhaul_${new_bh_band}_ap_iface)
        if [ -n "$new_bh_band" ] && [ "$new_bh_band" != "$cur_bh_band" ]; then
            # main backhaul band updated
            [ -n "$cur_bhap_ifname" ] && cfg80211tool $cur_bhap_ifname meshie_disab 1
            [ -n "$new_bhap_ifname" ] && cfg80211tool $new_bhap_ifname meshie_disab 0
            mesh_cmd backhaul set band $new_bh_band
            bh_changed=1
        fi

        case "$cap_type" in
            tri*)
                #default 5g
                cfg_5g_suffix="5g"
                device_5g_suffix="5g"
                cfg_5gh_suffix="5g_nbh"
                device_5gh_suffix="5g_nbh"

                if [ "$new_bh_band" = "5gh" ]; then
                    cfg_5g_suffix="5g_nbh"
                    device_5g_suffix="5g_nbh"
                    cfg_5gh_suffix="5g"
                    device_5gh_suffix="5g"
                fi

                if [ "$iface_cfg_swap" = "1" ]; then
                    local cfg_tmp_suffix=$cfg_5g_suffix
                    cfg_5g_suffix=$cfg_5gh_suffix
                    cfg_5gh_suffix=$cfg_tmp_suffix
                fi
                ;;
            dual*)
                local bh_device=$(uci -q get misc.wireless.if_$(echo "$cur_bh_band"|tr '[a-z]' '[A-Z]'))
                local cur_bh_chan=$(uci -q get wireless.$bh_device.channel)
                local new_bh_chan="$(cat $cfgf | grep -w "ch_5g" | awk -F ":=" '{print $2}')"
                wifi_bh_change "$cur_bh_chan" "$new_bh_chan"
                if [ "$?" = "1" ]; then
                    local bh_mlo_support="$(mesh_cmd bh_mlo_support)"

                    local new_bh_band=$(mesh_cmd backhaul get band)
                    local bh_band_upcase=$(echo "$new_bh_band" | tr '[a-z]' '[A-Z]')
                    local new_bhap_ifname=$(uci -q get misc.backhauls.backhaul_${new_bh_band}_ap_iface)
                    local new_bhsta_ifname=$(uci -q get misc.backhauls.backhaul_${new_bh_band}_sta_iface)
                    local new_bh_device=$(uci -q get misc.wireless.if_${bh_band_upcase})

                    # trigger topomon to update backhaul band
                    mesh_cmd backhaul set real_band "$new_bh_band"
                    ubus -t5 call topomon bh_band_update

                    if [ "$bh_mlo_support" = "1" ]; then
                        cfg80211tool $cur_bhap_ifname meshie_disab 1
                        cfg80211tool $new_bhap_ifname meshie_disab 0

                        # TODO: to compat dual cap which support mlo(2g+5g/5gh)
                        local mlo_set=$(uci -q get wireless.bh_sta_mlo.mlo)
                        local is_mlo_bhlink=$(mesh_cmd is_mlo_bhlink)
                        if [ "$is_mlo_bhlink" != "1" ] && [ -z "$mlo_set" ]; then
                            local cur_wfsec="bh_sta_$cur_bh_band"
                            local new_wfsec="bh_sta_$new_bh_band"
                            uci -q set wireless.$cur_wfsec.disabled=1
                            uci -q set wireless.$new_wfsec.disabled=0
                        fi
                    elif [ -n "$new_bhap_ifname" -a -n "$new_bhsta_ifname" ]; then
                        uci -q set wireless.bh_ap.ifname="$new_bhap_ifname"
                        uci -q set wireless.bh_ap.device="$new_bh_device"
                        uci -q set wireless.bh_sta.ifname="$new_bhsta_ifname"
                        uci -q set wireless.bh_sta.device="$new_bh_device"
                    fi
                    son_changed=1
                fi
                cfg_5g_suffix="5g"
                cfg_5gh_suffix="5g"
                device_5g_suffix="5g"
                device_5gh_suffix="5g"
                cap_is_dual=1
                ;;
        esac
    else
        device_5g_suffix="5g"
        cfg_5g_suffix="5g"
    fi
}

__wifi_mlo_sync()
{
    local mlo_support="$(mesh_cmd mlo_support)"
    local mlo_vap_support="$(uci -q get misc.features.mlo_vap_support)"
    [ "$mlo_support" != "1" -a "$mlo_vap_support" != "1" ] && return
    [ "$mlo_vap_support" = "1" ] && mlo_support="0"

    [ -z "$(uci -q show misc.mld)" ] && return

    local bhap_mld="$(uci -q get misc.mld.bh_ap)"
    local hostap_mld="$(uci -q get misc.mld.hostap)"
    local cur_main_band=$(mesh_cmd backhaul get band)
    [ "$mlo_support" = "1" ] && {
        local local_hostap_mlo_enable=$(uci -q get wireless.$hostap_mld.mlo_enable)
        local hostap_mlo_enable="`cat $cfgf | grep -w "mlo" | awk -F ":=" '{print $2}'`"

        [ "$ax_changed" != "1" ] && [ "$bsd_changed" != "1" ] && [ "$local_hostap_mlo_enable" == "$hostap_mlo_enable" ] && return
        [ -z "$hostap_mlo_enable" ] && hostap_mlo_enable=1

        # handle hostap mlo sync
        local hostap_mld_radios="$(uci -q get misc.mld.hostap_mlo)"
        if [ -n "$hostap_mld_radios" ]; then
            local mld_ssid=
            local hostap_mlo_clean=0
            for radio in $hostap_mld_radios; do
                local radio_upcase=$(echo "$radio"|tr '[a-z]' '[A-Z]')
                local device=$(uci -q get misc.wireless.if_$radio_upcase)
                local ax=$(uci -q get wireless.$device.ax)
                local ifname=$(uci -q get misc.wireless.ifname_$radio_upcase)
                local iface=$(uci show wireless | grep -w "ifname=\'$ifname\'" | awk -F"." '{print $2}')
                local bsd=$(uci -q get wireless.$iface.bsd)

                [ "$ax" != "1" -o "$bsd" != "1" ] && hostap_mlo_clean=1
                son_changed=1

                if [ "$hostap_mlo_clean" = "1" ] || [ "$hostap_mlo_enable" != "1" ]; then
                    uci -q set wireless.$iface.mld=
                else
                    uci -q set wireless.$iface.mld="$hostap_mld"
                    if [ -z "$mld_ssid" ]; then
                        mld_ssid="$(uci -q get wireless.$iface.ssid)"
                        uci -q set wireless.$hostap_mld.mld_ssid="$mld_ssid"
                        uci -q set wireless.$hostap_mld.mld_macaddr="$(mld_macaddr hostap)"
                    fi
                fi
            done

            [ "$local_hostap_mlo_enable" != "$hostap_mlo_enable" ] && {
                son_changed=1
                WHC_LOGI " xq_whc_sync, hostap mlo change $local_hostap_mlo_enable -> $hostap_mlo_enable"
            }

            if [ "$hostap_mlo_enable" = "1" ] && [ "$hostap_mlo_clean" != "1" ]; then
                uci -q set wireless.$hostap_mld.mlo_enable=1
            else
                uci -q set wireless.$hostap_mld.mlo_enable=0
            fi
        fi
    }
    # for vap_mlo
    [ "$mlo_vap_support" = "1" ] && {
        local mlo_changed="0"
        # check hostap's cfgs
        local local_mlo_enable=$(uci -q get wireless.$hostap_mld.mlo_enable)
        local mlo_enable="$(cat $cfgf | grep -w "mlo_enable" | awk -F ":=" '{print $2}')"
        [ -z "$mlo_enable" ] && mlo_enable='0'

        local local_mlo_ssid=$(uci -q get wireless.$hostap_mld.mlo_ssid)
        local mlo_ssid="$(cat $cfgf | grep -w "mlo_ssid" | awk -F ":=" '{print $2}')"
        if [ "$USE_ENCODE" -gt 0 ]; then
            [ -n "$mlo_ssid" ] && mlo_ssid="$(base64_dec "$mlo_ssid")"
        fi

        local local_mlo_hidden=$(uci -q get wireless.$hostap_mld.mlo_hidden)
        local mlo_hidden="$(cat $cfgf | grep -w "mlo_hidden" | awk -F ":=" '{print $2}')"

        local local_mlo_enc=$(uci -q get wireless.$hostap_mld.mlo_enc)
        local mlo_enc="$(cat $cfgf | grep -w "mlo_enc" | awk -F ":=" '{print $2}')"

        local local_mlo_pwd=$(uci -q get wireless.$hostap_mld.mlo_pwd)
        local mlo_pwd="$(cat $cfgf | grep -w "mlo_pwd" | awk -F ":=" '{print $2}')"
        if [ "$USE_ENCODE" -gt 0 ]; then
            [ -n "$mlo_pwd" ] && mlo_pwd="$(base64_dec "$mlo_pwd")"
        fi

        if [ "$local_mlo_enable" != "$mlo_enable" ] || [ "$local_mlo_ssid" != "$mlo_ssid" ] || [ "$local_mlo_hidden" != "$mlo_hidden" ] || [ "$local_mlo_enc" != "$mlo_enc" ] || [ "$local_mlo_pwd" != "$mlo_pwd" ]; then
            mlo_changed="1"
            son_changed="1"
            WHC_LOGI " xq_whc_sync, mlo vap change $local_mlo_enable -> $mlo_enable, $local_mlo_ssid -> mlo_ssid, $local_mlo_hidden -> mlo_hidden, $local_mlo_enc -> mlo_enc, $local_mlo_pwd -> mlo_pwd "
        fi

        [ "$mlo_changed" = "1" ] && {
            local mlo_vap_clean=0
            local mlo_vap_radios="$(uci -q get misc.mld.hostap_mlo)"
            if [ -n "$mlo_vap_radios" ]; then
                # handle vap sync
                for radio in $mlo_vap_radios; do
                    local radio_upcase=$(echo "$radio"|tr '[a-z]' '[A-Z]')
                    local device=$(uci -q get misc.wireless.if_$radio_upcase)
                    local ax=$(uci -q get wireless.$device.ax)
                    local ifname=$(uci -q get misc.wireless.ifname_mlo_$radio_upcase)
                    local iface=$(uci show wireless | grep -w "ifname=\'$ifname\'" | awk -F"." '{print $2}')

                    [ "$ax" != "1" ] && mlo_vap_clean="1"

                    if [ "$mlo_enable" = "1" ] && [ "$mlo_vap_clean" = "0" ]; then
                        uci -q set wireless.$iface.disabled="0"
                    else
                        uci -q set wireless.$iface.disabled="1"
                    fi
                    uci -q set wireless.$iface.mld="$hostap_mld"
                    uci -q set wireless.$iface.ssid="$mlo_ssid"
                    uci -q set wireless.$iface.hidden="$mlo_hidden"
                    uci -q set wireless.$iface.encryption="ccmp"
                    if [ "$mlo_enc" = "ccmp" ]; then
                        uci -q set wireless.$iface.owe="0"
                        uci -q set wireless.$iface.sae="1"
                        uci -q set wireless.$iface.key=""
                        uci -q set wireless.$iface.sae_password="$mlo_pwd"
                        uci -q set wireless.$iface.ieee80211w="2"
                    elif [ "$mlo_enc" = "owe" ]; then
                        uci -q set wireless.$iface.owe="1"
                        uci -q set wireless.$iface.sae=""
                        uci -q set wireless.$iface.key=""
                        uci -q set wireless.$iface.sae_password=""
                        uci -q set wireless.$iface.ieee80211w="2"
                    fi
                done

                # handle hostap sync
                if [ "$mlo_enable" = "1" ] && [ "$mlo_vap_clean" != "1" ]; then
                    uci -q set wireless.$hostap_mld.mlo_enable="1"
                else
                    uci -q set wireless.$hostap_mld.mlo_enable="0"
                fi
                uci -q set wireless.$hostap_mld.mlo_ssid="$mlo_ssid"
                uci -q set wireless.$hostap_mld.mlo_hidden="$mlo_hidden"
                uci -q set wireless.$hostap_mld.mlo_enc="$mlo_enc"
                uci -q set wireless.$hostap_mld.mlo_pwd="$mlo_pwd"
            fi
        }
    }

    # handle bhap mlo sync
    local bhap_mld_radios="$(uci -q get misc.mld.bh_ap_mlo)"
    local bh_mlo_support="$(mesh_cmd bh_mlo_support)"
    if [ -n "$bhap_mld_radios" ] && [ "$bh_mlo_support" = "1" ]; then
        local bhmld_ssid=
        local bh_mlo_clean=0
        for radio in $bhap_mld_radios; do
            local radio_upcase=$(echo "$radio"|tr '[a-z]' '[A-Z]')
            local device=$(uci -q get misc.wireless.if_$radio_upcase)
            local ax=$(uci -q get wireless.$device.ax)
            [ "$ax" != "1" ] && bh_mlo_clean=1
            son_changed=1

            local bhap_sec="bh_ap_$radio"
            if [ "$bh_mlo_clean" = "1" ]; then
                uci -q set wireless.$bhap_sec.mld=
                if [ "$radio" = "$cur_main_band" ]; then
                    uci -q set wireless.$bhap_sec.disabled=0
                else
                    uci -q set wireless.$bhap_sec.disabled=1
                fi
            else
                uci -q set wireless.$bhap_sec.disabled=0
                uci -q set wireless.$bhap_sec.mld="$bhap_mld"
                if [ -z "$bhmld_ssid" ]; then
                    bhmld_ssid="$(uci -q get wireless.$bhap_sec.ssid)"
                    uci -q set wireless.$bhap_mld.mld_ssid="$bhmld_ssid"
                    uci -q set wireless.$bhap_mld.mld_macaddr="$(mld_macaddr bh_ap)"
                fi
            fi
        done
    fi

    if [ "$ax_changed" = "1" ] && [ "$bh_mlo_support" = "1" ]; then
        # handle bhsta mlo sync
        /usr/sbin/topomon_action.sh wifi_bhcfg_update
        son_changed=1

        if [ "$ax" != "1" ]; then
            mesh_cmd backhaul set real_band "$cur_main_band"
            ubus -t5 call topomon bh_band_update
        fi
    fi
}

__wifi_parse_iotwifi()
{
    local band="$1"

    [ -z "$band" ] && return

    local ssid_cur="`uci -q get wireless.iot_${band}.ssid`"
    local encryption_cur="`uci -q get wireless.iot_${band}.encryption`"
    local wifi5mode_cur="`uci -q get wireless.iot_${band}.iotwifi5mode`"
    local disabled_cur="`uci -q get wireless.iot_${band}.disabled`"
    local key_cur=""

    local ssid="`cat $cfgf | grep -w "iot${band}_ssid" | awk -F ":=" '{print $2}'`"
    local encryption="`cat $cfgf | grep -w "iot${band}_enc" | awk -F ":=" '{print $2}'`"
    local wifi5mode="`cat $cfgf | grep -w "iot${band}_wifi5" | awk -F ":=" '{print $2}'`"
    local disabled="`cat $cfgf | grep -w "iot${band}_disabled" | awk -F ":=" '{print $2}'`"
    local key=""

    if [ "$USE_ENCODE" -gt 0 ]; then
        [ -n "$ssid" ] && ssid="$(base64_dec "$ssid")"
    fi

    if [ "$ssid_cur" != "$ssid" ]; then
        uci set wireless.iot_${band}.ssid="$ssid"
        son_changed=1
        WHC_LOGI " xq_whc_sync, iot_${band} iface change ssid $ssid_cur -> $ssid "
    fi

    if [ "$wifi5mode_cur" != "$wifi5mode" ]; then
        uci set wireless.iot_${band}.iotwifi5mode="$wifi5mode"
        son_changed=1
        WHC_LOGI " xq_whc_sync, iot_${band} iface change iotwifi5mode $wifi5mode_cur -> $wifi5mode "
    fi

    if [ "$disabled_cur" != "$disabled" ]; then
        uci set wireless.iot_${band}.disabled="$disabled"
        son_changed=1
        WHC_LOGI " xq_whc_sync, iot_${band} iface change disabled $disabled_cur -> $disabled "
    fi

    ## 加密方式已更改处理逻辑
    if [ "$encryption_cur" != "$encryption" ]; then
        uci set wireless.iot_${band}.encryption="$encryption"
        son_changed=1
        WHC_LOGI " xq_whc_sync, iot_${band} iface change encryption $encryption_cur -> $encryption "

        if [ "$encryption" != "none" ]; then
            key="`cat $cfgf | grep -w "iot${band}_pwd" | awk -F ":=" '{print $2}'`"
            if [ "$USE_ENCODE" -gt 0 ]; then
                [ -n "$key" ] && key="$(base64_dec "$key")"
            fi
        fi

        if [ "$encryption" == "none" ]; then
            uci set wireless.iot_${band}.sae=""
            uci set wireless.iot_${band}.ieee80211w=""
        elif [ "$encryption" == "ccmp" ]; then
            uci set wireless.iot_${band}.sae=1
            uci set wireless.iot_${band}.key=""
            uci set wireless.iot_${band}.sae_password="$key"
            uci set wireless.iot_${band}.ieee80211w=2
        elif [ "$encryption" == "psk2+ccmp" ]; then
            uci set wireless.iot_${band}.sae=1
            uci set wireless.iot_${band}.key="$key"
            uci set wireless.iot_${band}.sae_password="$key"
            uci set wireless.iot_${band}.ieee80211w=1
        elif [ "$encryption" == "psk2" -o "$encryption" == "mixed-psk" -o "$encryption" == "psk" ]; then
            uci set wireless.iot_${band}.sae=""
            uci set wireless.iot_${band}.key="$key"
            uci set wireless.iot_${band}.sae_password=""
            uci set wireless.iot_${band}.ieee80211w=""
        fi
    else
        ## 加密方式未改变处理逻辑
        if [ "$encryption" != "none" ]; then
            key="`cat $cfgf | grep -w "iot${band}_pwd" | awk -F ":=" '{print $2}'`"
            if [ "$USE_ENCODE" -gt 0 ]; then
                [ -n "$key" ] && key="$(base64_dec "$key")"
            fi
            if [ "$encryption" == "ccmp" ]; then
                key_cur="`uci -q get wireless.iot_${band}.sae_password`"
                if [ "$key_cur" != "$key" ]; then
                    uci set wireless.iot_${band}.sae_password="$key"
                    son_changed=1
                    WHC_LOGI " xq_whc_sync, iot_${band} iface encryption $encryption change key $key_cur -> $key "
                fi
            elif [ "$encryption" == "psk2+ccmp" ]; then
                key_cur="`uci -q get wireless.iot_${band}.sae_password`"
                if [ "$key_cur" != "$key" ]; then
                    uci set wireless.iot_${band}.sae_password="$key"
                    uci set wireless.iot_${band}.key="$key"
                    son_changed=1
                    WHC_LOGI " xq_whc_sync, iot_${band} iface encryption $encryption change key $key_cur -> $key "
                fi
            elif [ "$encryption" == "psk2" -o "$encryption" == "mixed-psk" -o "$encryption" == "psk" ]; then
                key_cur="`uci -q get wireless.iot_${band}.key`"
                if [ "$key_cur" != "$key" ]; then
                    uci set wireless.iot_${band}.key="$key"
                    son_changed=1
                    WHC_LOGI " xq_whc_sync, iot_${band} iface encryption $encryption change key $key_cur -> $key "
                fi
            fi
        fi
    fi
}

wifi_parse()
{
    local ifname_2g="$(uci -q get misc.wireless.ifname_2G)"
    local ifname_5g="$(uci -q get misc.wireless.ifname_5G)"
    local ifname_5gh="$(uci -q get misc.wireless.ifname_5GH)"

    __wifi_bh_band
    __wifi_parse_ap_iface "2g" "2g"
    __wifi_parse_ap_iface "5g" "$cfg_5g_suffix"
    __wifi_parse_ap_iface "5gh" "$cfg_5gh_suffix"

    __wifi_parse_sta_iface "2g" "$ifname_2g" "2g"
    __wifi_parse_sta_iface "5g" "$ifname_5g" "$cfg_5g_suffix"
    __wifi_parse_sta_iface "5gh" "$ifname_5gh" "$cfg_5gh_suffix"

    __wifi_parse_device "2g" "2g"
    __wifi_parse_device "5g" "$device_5g_suffix"
    [ "$re_is_tri_band" = "1" ] && __wifi_parse_device "5gh" "$device_5gh_suffix"

    local iot_dev_support=$(uci -q get misc.features.iot_dev)
    WHC_LOGI " xq_whc_sync, iot_dev_support  = $iot_dev_support"
    if [ "$iot_dev_support" = "1" ]; then
        local miot_access_iotdev="`cat $cfgf | grep -w "miot_access_iotdev" | awk -F ":=" '{print $2}'`"
        local miot_access_iotdev_cur="`uci -q get wireless.miot_2G.miot_access_iotdev`"
        [ -n "$miot_access_iotdev" -a "$miot_access_iotdev"x != "$miot_access_iotdev_cur"x ] && {
            WHC_LOGI " xq_whc_sync, miot_access_iotdev changed [$miot_access_iotdev_cur] -> [$miot_access_iotdev]"
            uci set wireless.miot_2G.miot_access_iotdev="$miot_access_iotdev"
            uci commit wireless
        }

        __wifi_parse_iotwifi "2g"
        __wifi_parse_iotwifi "5g"
    fi

    __wifi_mlo_sync

    #iot switch
    local iot_switch_cur="`uci -q get wireless.miot_2G.userswitch`"
    [ -z "$iot_switch_cur" ] && iot_switch_cur=1
    local iot_switch="`cat $cfgf | grep -w "iot_switch" | awk -F ":=" '{print $2}'`"
    [ -n "$iot_switch" -a "$iot_switch" -ne "$iot_switch_cur" ] && {
        iot_switch_changed=1
        WHC_LOGI " xq_whc_sync, iot user switch changed [$iot_switch_cur] -> [$iot_switch]"
        uci set wireless.miot_2G.userswitch="$iot_switch"
    }

    uci commit wireless && sync

    return 0;
}

guest_parse()
{
    local vlan="$(cat $cfgf | grep -w "gst_vlan" | awk -F ":=" '{print $2}')"
    local disab="`cat $cfgf | grep -w "gst_disab" | awk -F ":=" '{print $2}'`"
    [ -z "$disab" ] && disab=1
    local mgmt="`cat $cfgf | grep -w "gst_mgmt" | awk -F ":=" '{print $2}'`"
    local sae="`cat $cfgf | grep -w "gst_sae" | awk -F ":=" '{print $2}'`"
    local sae_pswd="`cat $cfgf | grep -w "gst_sae_pswd" | awk -F ":=" '{print $2}'`"
    local ieee80211w="`cat $cfgf | grep -w "gst_ieee80211w" | awk -F ":=" '{print $2}'`"
    local ssid_enc="`cat $cfgf | grep -w "gst_ssid" | awk -F ":=" '{print $2}'`"
    local pswd_enc="`cat $cfgf | grep -w "gst_pswd" | awk -F ":=" '{print $2}'`"
    local ssid="$ssid_enc"
    local pswd="$pswd_enc"
    if [ "$USE_ENCODE" -gt 0 ]; then
        [ -n "$ssid" ] && ssid="$(base64_dec "$ssid_enc")"
        [ -n "$pswd" ] && pswd="$(base64_dec "$pswd_enc")"
        [ -n "$sae_pswd" ] && sae_pswd="$(base64_dec "$sae_pswd")"
    fi

    # if guest section no exist, create first
    local disab_cur=""
    local ssid_cur=""
    local pswd_cur=""
    local mgmt_cur=""
    local sae_cur=""
    local sae_pswd_cur=""
    local ieee80211w_cur=""
    local vlan_cur="$(uci -q get port_service.guest.vlan)"

    local gst_sect="guest_2G"
    if uci -q get wireless.$gst_sect >/dev/null 2>&1; then
        disab_cur="`uci -q get wireless.$gst_sect.disabled`"
        [ -z "$disab_cur" ] && disab_cur=0;
        if [ "$disab" != "$disab_cur" -a "$disab" = "1" ]; then
            WHC_LOGI " xq_whc_sync, guest section delete"
            /usr/sbin/guestwifi.sh cleanup
            son_changed=1
            gst_disab_changed=1
            return
        fi

        ssid_cur="`uci -q get wireless.$gst_sect.ssid`"
        pswd_cur="`uci -q get wireless.$gst_sect.key`"
        mgmt_cur="`uci -q get wireless.$gst_sect.encryption`"
        if [ "$mgmt_cur" = "ccmp" ] || [ "$mgmt_cur" = "psk2+ccmp" ]; then
            sae_cur="`uci -q get wireless.$gst_sect.sae`"
            sae_pswd_cur="`uci -q get wireless.$gst_sect.sae_password`"
            ieee80211w_cur="`uci -q get wireless.$gst_sect.ieee80211w`"
        fi
    else
        if [ "$disab" != "1" ]; then
            [ "$mgmt" = "ccmp" -o "$mgmt" = "psk2+ccmp" ] && pswd=$sae_pswd
            WHC_LOGI " xq_whc_sync, guest section newly add[ssid:$ssid, mgmt:$mgmt, pswd:$pswd, disab:$disab], TODO son options"
            /usr/sbin/guestwifi.sh setup "$ssid" "$mgmt" "$pswd" "$disab"
            uci -q set port_service.guest.enable="$((disab ^ 1))"
            uci commit port_service
            son_changed=1
            gst_disab_changed=1
        fi
        return
    fi

    [ -z "$ssid" ] && {
        WHC_LOGE " xq_whc_sync, guest options invalid ignore!"
        cp "$cfgf" "$cfgf_fake"
        return 1
    }

    local device=$(uci -q get misc.wireless.if_5G)
    local ifname=$(uci -q get misc.wireless.ifname_guest_5G)
    [ -z "$device" -o -z "$ifname" ] || {
        gst_support_5g=1
        gst_sect_5g="guest_5G"
    }

    [ "$ssid_cur" != "$ssid" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest ssid change $ssid_cur -> $ssid"
        uci set wireless.$gst_sect.ssid="$ssid"
        [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.ssid="$ssid"
    }
    [ "$pswd_cur" != "$pswd" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest pswd change $pswd_cur -> $pswd"
        uci set wireless.$gst_sect.key="$pswd"
        [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.key="$pswd"
    }
    [ "$mgmt_cur" != "$mgmt" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest mgmt change $mgmt_cur -> $mgmt"
        uci set wireless.$gst_sect.encryption="$mgmt"
        [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.encryption="$mgmt"
    }

    [ "$sae" != "$sae_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, guest sae change $sae_cur -> $sae"
         if [ -n "$sae" ];then
            uci set wireless.$gst_sect.sae="$sae"
            [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.sae="$sae"
         else
            uci -q delete wireless.$gst_sect.sae
            uci -q delete wireless.$gst_sect_5g.sae
         fi
    }
    [ "$sae_pswd" != "$sae_pswd_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, guest sae password change $sae_pswd_cur -> $sae_pswd"
         if [ -n "$sae_pswd" ];then
            uci set wireless.$gst_sect.sae_password="$sae_pswd"
            [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.sae="$sae"
         else
            uci -q delete wireless.$gst_sect.sae_password
            uci -q delete wireless.$gst_sect_5g.sae_password
         fi
    }
    [ "$ieee80211w" != "$ieee80211w_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, guest ieee80211w change $ieee80211w_cur -> $ieee80211w"
         if [ -n "$ieee80211w" ];then
            uci set wireless.$gst_sect.ieee80211w="$ieee80211w"
            [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.ieee80211w="$ieee80211w"
         else
            uci -q delete wireless.$gst_sect.ieee80211w
            uci -q delete wireless.$gst_sect_5g.ieee80211w
         fi
    }

    [ "$vlan_cur" != "$vlan" ] && {
        gst_vlan_changed=1
        WHC_LOGI " xq_whc_sync, guest vlan change $vlan_cur -> $vlan"
        uci -q set port_service.guest.vlan="$vlan"
    }

    if [ "$disab_cur" != "$disab" ]; then
        son_changed=1
        gst_disab_changed=1
        WHC_LOGI " xq_whc_sync, guest disab change $disab_cur -> $disab"
        uci set wireless.$gst_sect.disabled="$disab"
        [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.disabled="$disab"
        uci -q set port_service.guest.enable="$((disab ^ 1))"
    else
        [ "$disab" = 1 -a "$son_changed" -gt 0 ] && {
            WHC_LOGI " xq_whc_sync, guest disab, with option change, ignore reset"
            son_changed=0
        }
    fi

    uci commit wireless && sync
    uci commit port_service && sync

    return 0
}

nfc_parse()
{
    # 最近一次设置生效原则：
    # 首次Mesh组网CAP同步后，如果用户单独在RE界面设置，则覆盖原CAP同步的情况；
    # 用户最新在CAP设置了以后，RE按最新设置同步
    local nfc_mesh_sync_disabled="$(uci -q get nfc.nfc.mesh_sync_disabled)"
    local nfc_enable="$(cat $cfgf | grep -w "nfc_enable" | awk -F ":=" '{print $2}')"
    local nfc_enable_cur="$(uci -q get nfc.nfc.nfc_enable)"
    local nfc_config_id="$(cat $cfgf | grep -w "nfc_id" | awk -F ":=" '{print $2}')"
    local nfc_config_id_cur="$(uci -q get nfc.nfc.config_id)"

    # 如果是旧版不带nfc config id的CAP，且RE上做过修改，则不同步
    [ -z "$nfc_config_id" -a "$nfc_mesh_sync_disabled" == "1" ] && return 0

    # CAP not support nfc sync or nfc config id of CAP hasn't changed, do nothing
    [ -z "$nfc_enable" ] || [ -n "$nfc_config_id" -a "$nfc_config_id" == "$nfc_config_id_cur" ] && return 0
    if [ -z "$(uci -q show nfc)" ]; then
        touch /etc/config/nfc
        uci -q set nfc.nfc=nfc
    fi
    uci -q set nfc.nfc.config_id="$nfc_config_id"

    if [ "$nfc_enable" != "$nfc_enable_cur" ]; then
        uci -q set nfc.nfc.nfc_enable="$nfc_enable"
        nfc_changed=1
    fi
    uci commit nfc
}

system_parse()
{
    local tz_index="$(cat $cfgf | grep -w "tz_index" | awk -F ":=" '{print $2}')"
    local timezone="`cat $cfgf | grep -w "timezone" | awk -F ":=" '{print $2}'`"
    local timezone_cur="`uci -q get system.@system[0].timezone`"
    [ "$timezone_cur" != "$timezone" ] && {
        sys_changed=1
        WHC_LOGI " xq_whc_sync, system timezone change $timezone_cur -> $timezone"
        uci set system.@system[0].timezone="$timezone"
        [ -n "$tz_index" ] && uci set system.@system[0].timezoneindex="$tz_index"
        uci commit system
        /etc/init.d/timezone restart
    }

    local ota_auto="`cat $cfgf | grep -w "ota_auto" | awk -F ":=" '{print $2}'`"
    [ -z "$ota_auto" ] && ota_auto=0
    local ota_auto_cur="`uci -q get otapred.settings.auto`"
    [ -z "$ota_auto_cur" ] && ota_auto_cur=0
    local ota_time="`cat $cfgf | grep -w "ota_time" | awk -F ":=" '{print $2}'`"
    local ota_time_cur="`uci -q get otapred.settings.time`"
    [ -z "$ota_time_cur" ] && ota_time_cur=4
    [ "$ota_auto" != "$ota_auto_cur" -o "$ota_time" != "$ota_time_cur" ] && {
        sys_changed=1
        WHC_LOGI " xq_whc_sync, system ota change $ota_auto_cur,$ota_time_cur -> $ota_auto,$ota_time"
        uci set otapred.settings.auto="$ota_auto"
        uci set otapred.settings.time="$ota_time"
        uci commit otapred
    }

    # 最近一次设置生效原则：
    # 首次Mesh组网CAP同步后，如果用户单独在RE界面设置，则覆盖原CAP同步的情况；
    # 用户最新在CAP设置了以后，RE按最新设置同步
    local led_mesh_sync_disabled="$(uci -q get xiaoqiang.common.led_mesh_sync_disabled)"
    local led_blue_cur="`uci -q get xiaoqiang.common.BLUE_LED`"
    local led_blue="`cat $cfgf | grep -w "led_blue" | awk -F ":=" '{print $2}'`"
    local led_blue_sum="`cat $cfgf | grep -w "led_blue_sum" | awk -F ":=" '{print $2}'`"
    local led_blue_sum_cur="`uci -q get xiaoqiang.common.BLUE_LED_SUM`"
    
    local ethled_cur="`uci -q get xiaoqiang.common.ETHLED`"
    local ethled="`cat $cfgf | grep -w "ethled" | awk -F ":=" '{print $2}'`"
    local ethled_sum="`cat $cfgf | grep -w "ethled_sum" | awk -F ":=" '{print $2}'`"
    local ethled_sum_cur="`uci -q get xiaoqiang.common.ETHLED_SUM`"

    # 兼容旧版，RE修改过配置后，led_mesh_sync_disabled置位，不再同步
    # 如果CAP是新版，带led_blue_sum，则当sum不相等时，说明CAP修改了配置，RE需要同步最新的配置
    if [ -z "$led_blue_sum" -a "$led_mesh_sync_disabled" != "1" ] || [ "$led_blue_sum" != "$led_blue_sum_cur" ] ; then
        uci -q set xiaoqiang.common.led_mesh_sync_disabled=0
        uci -q set xiaoqiang.common.BLUE_LED_SUM="$led_blue_sum"
        uci commit xiaoqiang
        [ -z "$led_blue" ] && led_blue=1
        [ -z "$led_blue_cur" ] && led_blue_cur=1
        if [ "$led_blue" != "$led_blue_cur" ]; then
            WHC_LOGI " xq_whc_sync, system led change $led_blue_cur -> $led_blue"

            if [ "$led_blue" -eq 0 ]; then
                led_ctl led_off
            else
                led_ctl led_on
            fi
        fi
    fi

    # 不相等，说明CAP新修改了配置，RE按最新配置同步
    [ "$ethled_sum" != "$ethled_sum_cur" ] && {
        uci -q set xiaoqiang.common.ETHLED_SUM="$ethled_sum"
        uci commit xiaoqiang
        [ -z "$ethled" ] && ethled=1
        [ -z "$ethled_cur" ] && ethled_cur=1
        [ "$ethled" != "$ethled_cur" ] && {
            WHC_LOGI " xq_whc_sync, ethernet led change $ethled_cur -> $ethled"
            # save ethled
            [ "$ethled" == "0" ] && {
                led_ctl led_off ethled
            } || {
                [ "$ethled" == "1" ] && {
                    led_ctl led_on ethled
                }
            }
        }
    }

    local fan_mode="`cat $cfgf | grep -w "fan_mode" | awk -F ":=" '{print $2}'`"
    local temp_config_sum="`cat $cfgf | grep -w "temp_config_sum" | awk -F ":=" '{print $2}'`"
    local temp_config_sum_cur="`uci -q get mitempctrl.settings.config_sum`"
    [ "$temp_config_sum" != "$temp_config_sum_cur" ] && {
        uci -q set mitempctrl.settings.config_sum="$temp_config_sum"
        uci commit mitempctrl
        [ -z "$fan_mode" ] && fan_mode=0
        local fan_mode_cur="`uci -q get mitempctrl.settings.mode`"
        [ -z "$fan_mode_cur" ] && fan_mode_cur=0
        [ "$fan_mode" != "$fan_mode_cur" ] && {
            WHC_LOGI " xq_whc_sync, fan mode change $fan_mode_cur -> $fan_mode"
            # save fan mode
            uci set mitempctrl.settings.mode="$fan_mode"
            uci commit mitempctrl
            ubus call mitempctrl reload
            /etc/init.d/powerctl restart
        }
    }

    local privacy="`cat $cfgf | grep -w "privacy" | awk -F ":=" '{print $2}'`"
    local privacy_cur="$(uci -q get xiaoqiang.common.PRIVACY)"
    [ "$privacy_cur" != "$privacy" ] && {
        privacy_lua_function='
        XQSysUtil = require("xiaoqiang.util.XQSysUtil")
        XQSysUtil.setSpEnable()
        '

        uci set xiaoqiang.common.PRIVACY="$privacy"
        uci commit xiaoqiang
        lua -e "$privacy_lua_function" 2>/dev/null
    }

    return 0
}

miscan_parse()
{
    local miscan_enable="`cat $cfgf | grep -w "miscan_enable" | awk -F ":=" '{print $2}'`"
    local miscan_enable_cur="`uci -q get miscan.config.enabled`"
    [ "$miscan_enable_cur" != "$miscan_enable" ] && {
        miscan_changed=1
        WHC_LOGI " xq_whc_sync, miscan status change $miscan_enable_cur -> $miscan_enable"
        uci set miscan.config.enabled="$miscan_enable"
        uci commit miscan
    }

    return 0
}

bak_config()
{
    cp "$cfgf_origin" "$cfgf"
}

clean_config()
{
    rm "$cfgf"
}

iot_switch_handle()
{
    if [ "$iot_switch_changed" -gt 0 ]; then
        WHC_LOGI " xq_whc_sync, iot user switch changed!"
        userswitch="`uci -q get wireless.miot_2G.userswitch`"
        miot_2g_ifname="`uci -q get misc.wireless.iface_miot_2g_ifname`"
        bindstatus="`uci -q get wireless.miot_2G.bindstatus`"
        miot_2g_device="`uci -q get wireless.miot_2G.device`"
        if [ "$bindstatus" = "1" ]; then
            if [ "$userswitch" != "0" ]; then
                hostapd_cli -i "$miot_2g_ifname" -p /var/run/hostapd-$miot_2g_device enable
            else
                hostapd_cli -i "$miot_2g_ifname" -p /var/run/hostapd-$miot_2g_device disable
            fi
        fi
        /etc/init.d/miot restart
    fi
}

wifi_handle()
{
    # must call guest_parse first
    [ "$GUEST_SUPPORT" = "1" ] && {
        guest_parse
        local guest_ret=$?
        if [ "$guest_ret" -gt 0 ]; then
            clean_config
            return $guest_ret
        fi
    }

    [ "$NFC_SUPPORT" = "1" ] && nfc_parse

    wifi_parse
    wifi_ret=$?
    if [ "$wifi_ret" -gt 0 ]; then
        clean_config
        return $wifi_ret
    fi

    iot_switch_handle

    if [ "$gst_vlan_changed" -gt 0 ] || [ "$gst_disab_changed" -gt 0 ]; then
        WHC_LOGI " xq_whc_sync, gst_vlan_changed or gst_disab_changed, restart guest!"
        ##TODO reload network config
        ubus call network reload
    fi

    if [ "$son_changed" -gt 0 ]; then
        WHC_LOGI " xq_whc_sync, son_changed, update wifi!"
        /sbin/wifi update
    else
        # if wifi cfg not changed, do nfc update here
        [ "$nfc_changed" = "1" ] && /usr/sbin/nfc.lua &

        WHC_LOGD " xq_whc_sync, son NO change!"
    fi
}

system_handle()
{
    if [ "$sys_changed" -gt 0 ]; then
        WHC_LOGI " xq_whc_sync, sys_changed, restart ntp!"
        # wait son update and reconnect
        if [ "$son_changed" -gt 0 ]; then
            (sleep 60; ntpsetclock now) &
        else
            (ntpsetclock now) &
        fi
    fi
}

bak_config

system_parse
miscan_parse

if [ "$miscan_changed" -gt 0 -a -x "/etc/init.d/scan" ]; then
    WHC_LOGI " xq_whc_sync, miscan_changed, restart miscan!"
    (/etc/init.d/scan restart) &
fi

(trap "clean_config; lock -u $xqwhc_lock; exit 1" INT TERM ABRT QUIT ALRM HUP;
    lock "$xqwhc_lock";
    wifi_handle;
    system_handle;
    clean_config;
lock -u "$xqwhc_lock" ) &
