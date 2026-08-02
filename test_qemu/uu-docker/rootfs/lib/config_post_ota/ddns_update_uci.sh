#!/bin/sh

is_old_ddns=$(cat /etc/config/ddns | grep -wc "ip_url")
[ $is_old_ddns -eq 0 ] && return

sections=$(uci show ddns | grep "=service" | cut -d'.' -f2 | cut -d'=' -f1)

for section in $sections; do
    uci delete ddns.$section.ip_url
    uci delete ddns.$section.ip_script
    uci set ddns.$section.ip_source='network'
    uci set ddns.$section.ip_network='wan'
    uci set ddns.$section.retry_count='3'
    uci set ddns.$section.use_ipv6='0'
done

uci commit ddns
