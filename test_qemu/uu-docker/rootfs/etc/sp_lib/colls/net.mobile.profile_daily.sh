#!/bin/ash

apncurid=$(uci -q get mobile.common.apncurid)
[ -z "$apncurid" ] && return
pdp=$(uci -q get mobile.$apncurid.pdp)
apn=$(uci -q get mobile.$apncurid.apn)
enc=$(uci -q get mobile.$apncurid.encryption)
username=$(uci -q get mobile.$apncurid.user)
passwd=$(uci -q get mobile.$apncurid.passwd)

echo "$pdp;$apn;$enc;$username;$passwd" | sed 's/ //g'
