#!/bin/sh

####################################################################################
#/etc/config/smartvpn example
#
#config global "settings"
#	option disabled "1"
#      	option status "off"
#        option type vpn
#        option domain_file /etc/smartvpn/proxy.txt
#        option proxy_local_port  10080
#        option proxy_remote_ip   54.85.90.122

#mac: devices which transfer through vpn
#notmac: devices which not transfer through vpn
#config device 'device'
#        list mac '34:17:eb:d0:e6:f9'
#        list mac '34:17:eb:d0:e6:a9'
#host: website which transfer through vpn
#nothost: website which not transfer through vpn
#config dest 'dest'
#        list host '.google.com'
#        list notnet '169.254.0.0/16'
#        list notnet '0.0.0.0/8'
#        list notnet '10.0.0.0/8'
#        list notnet '127.0.0.0/8'
#        list notnet '169.254.0.0/16'
#        list notnet '172.16.0.0/12'
#        list notnet '192.168.0.0/16'
#        list notnet '224.0.0.0/4'
#        list notnet '240.0.0.0/4'
####################################################################################

. /lib/functions/network.sh

ipset_name="smartvpn"
ipset_ip_name="smartvpn_ip"
ipset_mark="0x10/0x10"

vpn_status="down"
smartvpn_cfg_domain_disabled=1
smartvpn_cfg_status="off"
smartvpn_cfg_type="vpn"
smartvpn_cfg_domainfile=""

dnsmasq_conf_path="/etc/dnsmasq.d"
smartdns_conf_path="/etc/smartvpn"
smartdns_conf_name="smartdns.conf"
smartdns_conf="$smartdns_conf_path/$smartdns_conf_name"

rule_file_ip="/etc/smartvpn/smartvpn_ip.txt"

smartvpn_device_table="smartvpn_device"
smartvpn_mark_table="smartvpn_mark"


smartvpn_logger()
{
    echo "smartvpn: $1"
    logger -t smartvpn "$1"
}

smartvpn_usage()
{
    echo "usage: ./smartvpn.sh on|off"
    echo "value: on  -- enable smartvpn"
    echo "value: off -- disable smartvpn"
    echo "note:  smartvpn only used when vpn is UP!"
    echo ""
}

dnsmasq_restart()
{
    local dnamasq_lock="/var/run/samartvpn.dnsmasq.lock"
    trap "lock -u $dnamasq_lock; exit 1" SIGHUP SIGINT SIGTERM
    lock $dnamasq_lock

    local process_pid=$(ps | grep "/usr/sbin/dnsmasq" |grep -v "grep /usr/sbin/dnsmasq" | awk '{print $1}' 2>/dev/null)

    local retry_times=0
    while [ $retry_times -le 2 ]
    do
        let retry_times+=1
        rm /var/etc/dnsmasq.conf &>/dev/null
        /etc/init.d/dnsmasq restart &>/dev/null
        sleep 1

        local process_newpid=$(ps | grep "/usr/sbin/dnsmasq" |grep -v "grep /usr/sbin/dnsmasq" | awk '{print $1}' 2>/dev/null)
        smartvpn_logger "dnsmasq_restart oldpid: $process_pid newpid: $process_newpid"

        [ "$process_pid" != "$process_newpid" ] && break
    done

    lock -u $dnamasq_lock
}

smartvpn_dns_start()
{
    smartvpn_dns_stop

    [ -f "$smartdns_conf" ] && mv  $smartdns_conf $dnsmasq_conf_path &>/dev/null
    dnsmasq_restart
}

smartvpn_dns_stop()
{
    # del smartvpn dnsmasq conf
    rm "$dnsmasq_conf_path/$smartdns_conf_name" &>/dev/null
    rm "/var/etc/dnsmasq.d/$smartdns_conf_name" &>/dev/null
    rm "/tmp/etc/dnsmasq.d/$smartdns_conf_name" &>/dev/null
    rm "/tmp/dnsmasq.d/$smartdns_conf_name" &>/dev/null

    # flush dnsmasq
    [ "$1" = "restart" ] && dnsmasq_restart
}

smartvpn_ipset_create()
{
    [ -s "$smartdns_conf" ] && {
        smartvpn_logger "create $ipset_name."
        ipset list | grep $ipset_name &>/dev/null
        [ $? -ne 0 ] && ipset create $ipset_name hash:ip &>/dev/null
    }
}

smartvpn_ipset_add_by_file()
{
    [ ! -s "$rule_file_ip" ] && return

    smartvpn_logger "create $ipset_ip_name."
    ipset list | grep $ipset_ip_name &>/dev/null
    [ $? -ne 0 ] && ipset create $ipset_ip_name hash:net &>/dev/null

    smartvpn_logger "add ip to ipset $ipset_ip_name."
    cat "$rule_file_ip" | while read line
    do
        ipset add $ipset_ip_name $line &>/dev/null
    done
}

smartvpn_ipset_delete()
{
    ipset flush $ipset_name &>/dev/null
    ipset flush $ipset_ip_name &>/dev/null

    ipset destroy $ipset_name &>/dev/null # maybe failed, but doesn't matter
    ipset destroy $ipset_ip_name &>/dev/null # maybe failed, but doesn't matter
}

smartvpn_vpn_route_delete()
{
    # del subnet default routing
    network_get_subnet subnet lan
    ip rule del from $(fix_subnet $subnet) table vpn &>/dev/null
    smartvpn_logger "delete $subnet to vpn."
}

smartvpn_vpn_route_add()
{
    network_get_subnet subnet lan
    smartvpn_logger "add $subnet to vpn."
    ip rule del from $(fix_subnet $subnet) table vpn &>/dev/null
    ip rule add from $(fix_subnet $subnet) table vpn &>/dev/null
}

smartvpn_wandns2vpn_change()
{
    local dnsservers
    local opt=$1
    [ "$opt" != "add" -a "$opt" != "del" ] && return

    network_get_dnsserver vpn_dnsservers vpn
    network_get_dnsserver wan_dnsservers $bind_wan

    for wandns in $wan_dnsservers; do
        local duplicate=0
        for vpndns in $vpn_dnsservers; do
            [ "$wandns" = "$vpndns" ] && duplicate=1
        done
        [ "$duplicate" = 0 ] && dnsservers="$dnsservers $wandns"
    done

    for dns in $dnsservers; do
        smartvpn_logger "wan dns del $dns to vpn"
        ip rule $opt to $dns table vpn &>/dev/null
    done
}

smartvpn_firewall_reload_add()
{
    local smartvpn_fw=$(uci -q get firewall.smartvpn)
    [ -n "$smartvpn_fw" ] && return

    uci -q batch <<-EOF >/dev/null
    set firewall.smartvpn=include
    set firewall.smartvpn.path="/lib/firewall.sysapi.loader smartvpn"
    set firewall.smartvpn.reload=1
    commit firewall
EOF
}

smartvpn_firewall_reload_delete()
{
    local smartvpn_fw=$(uci -q get firewall.smartvpn)
    [ -z "$smartvpn_fw" ] && return

    uci -q batch <<-EOF >/dev/null
    delete firewall.smartvpn
    commit firewall
EOF
}

smartvpn_status_set()
{
    local status=$(uci -q get smartvpn.vpn.status)
    [ "$status" = "$1" ] && return

    uci -q batch <<-EOF >/dev/null
       set smartvpn.vpn.status=$1
       commit smartvpn
EOF
}

smartvpn_vpn_mark_redirect_open()
{
    smartvpn_vpn_mark_redirect_close

    ip rule add fwmark $ipset_mark table vpn &>/dev/null
    iptables -t mangle -N $smartvpn_mark_table &>/dev/null

    #allowmacs not NULL
    if [ "$smartvpn_cfg_devicedisabled" = "0" -a -n "$smartvpn_cfg_devicemac" ]; then
        iptables -t mangle -N $smartvpn_device_table &>/dev/null

        smartvpn_logger "add all host mark $ipset_mark to vpn."
        for mac in $smartvpn_cfg_devicemac
        do
            smartvpn_logger "device mac add $mac."
            iptables -t mangle -A $smartvpn_device_table  -m mac --mac-source $mac -j MARK --set-mark $ipset_mark &>/dev/null
        done

        # iptables -t mangle -A $smartvpn_device_table -j ACCEPT &>/dev/null
        # iptables -t mangle -A $smartvpn_mark_table -j MARK --set-mark $ipset_mark &>/dev/null
        iptables -t mangle -A PREROUTING -j smartvpn_device &>/dev/null
    fi

    #dns mark not NULL
    if [ "$smartvpn_cfg_domain_disabled" = "0" ]; then
        smartvpn_logger "add dns mark $ipset_mark to vpn."
        [ -s "$dnsmasq_conf_path/$smartdns_conf_name" ] && {
            smartvpn_logger "add ipset $ipset_name mark $ipset_mark to vpn."
            iptables -t mangle -A $smartvpn_mark_table -m set --match-set $ipset_name dst -j MARK --set-mark $ipset_mark &>/dev/null
        }
        [ -s "$rule_file_ip" ] && {
            smartvpn_logger "add ipset $ipset_ip_name mark $ipset_mark to vpn."
            iptables -t mangle -A $smartvpn_mark_table -m set --match-set $ipset_ip_name dst -j MARK --set-mark $ipset_mark &>/dev/null
    }
    fi

    iptables -t mangle -A PREROUTING -j smartvpn_mark &>/dev/null
}

smartvpn_vpn_mark_redirect_close()
{
    iptables -t mangle -D PREROUTING -j smartvpn_device &>/dev/null
    iptables -t mangle -D PREROUTING -j smartvpn_mark &>/dev/null

    iptables -t mangle -F $smartvpn_device_table &>/dev/null
    iptables -t mangle -X $smartvpn_device_table &>/dev/null

    iptables -t mangle -F $smartvpn_mark_table &>/dev/null
    iptables -t mangle -X $smartvpn_mark_table &>/dev/null

    ip rule del fwmark $ipset_mark table vpn &>/dev/null
}

vpn_status_get()
{
    network_is_up vpn
    if [ $? -eq 0 ]; then
        vpn_status="up"
    else
        vpn_status="down"
    fi
}

#config remote "vpn"
#	option disabled "1"
#      	option status "off"
#       option domain_file /etc/smartvpn/vpn.txt
#       option type vpn

smartvpn_config_get()
{
    smartvpn_cfg_domain_switch=$(uci -q get smartvpn.vpn.switch)
    smartvpn_cfg_domain_disabled=$(uci -q get smartvpn.vpn.disabled)
    smartvpn_cfg_status=$(uci -q get smartvpn.vpn.status)
    smartvpn_cfg_type=$(uci -q get smartvpn.vpn.type)
    smartvpn_cfg_domainfile=$(uci -q get smartvpn.vpn.domain_file)
    smartvpn_cfg_devicemac=$(uci -q get smartvpn.device.mac)
    smartvpn_cfg_devicedisabled=$(uci -q get smartvpn.device.disabled)
    smartvpn_cfg_hostnotnet=$(uci -q get smartvpn.dest.notnet)

    [ -z "$smartvpn_cfg_domain_disabled" ] && smartvpn_cfg_domain_disabled="0"
    [ -z "$smartvpn_cfg_status" ] && smartvpn_cfg_status="off"
}

smartvpn_open()
{
    smartvpn_firewall_reload_add

    if [ "$vpn_status" != "up" ]; then
        smartvpn_logger "vpn_status($vpn_status) is down, return."
        return 1
    fi

    smartvpn_ipset_delete
    [ "$smartvpn_cfg_domain_disabled" = "0" -a -s "$smartvpn_cfg_domainfile" ] && {
        rm "$rule_file_ip" &>/dev/null
        smartvpn_logger "translet domain to ipset."
        gensmartdns.sh "$smartvpn_cfg_domainfile" "$smartdns_conf" "$rule_file_ip" "$ipset_name"
        smartvpn_ipset_create
        smartvpn_ipset_add_by_file
    }   
    smartvpn_dns_start

    ### enable smartvpn
    smartvpn_wandns2vpn_change "del"
    smartvpn_vpn_route_delete
    smartvpn_vpn_mark_redirect_open
    ip route flush table cache

    smartvpn_status_set "on"
    smartvpn_logger "smartvpn open!"

    return 0
}

smartvpn_close()
{
    smartvpn_firewall_reload_delete

    if [ "$smartvpn_cfg_status" = "off" ]; then
        smartvpn_logger "status already off!"
        return 0
    fi

    smartvpn_vpn_mark_redirect_close
    smartvpn_ipset_delete
    smartvpn_dns_stop "restart"

    # after smartvpn is off, add wan route if vpn is still up
    if [ "$vpn_status" = "up" ]; then
        smartvpn_wandns2vpn_change "add"
        smartvpn_vpn_route_add
        ip route flush table cache
    fi

    smartvpn_status_set "off"
    smartvpn_logger "smartvpn close!"

    return 0
}

opt=$1
bind_wan=$2
[ -z "$bind_wan" ] && bind_wan="wan"

vpn_status_get
smartvpn_config_get
[ "$smartvpn_cfg_type" != "vpn" ] && return 1

smartvpn_lock="/var/run/smartvpn.lock"
trap "lock -u $smartvpn_lock; exit 1" SIGHUP SIGINT SIGTERM
lock $smartvpn_lock

case $opt in
    on)
        [ "$smartvpn_cfg_domain_switch" = "1" ] && smartvpn_open
        lock -u $smartvpn_lock
        return $?
    ;;

    off)
        smartvpn_close
        lock -u $smartvpn_lock
        return $?
    ;;

    fw)
        if [ "$smartvpn_cfg_domain_switch" = "1" ]; then
            smartvpn_vpn_mark_redirect_open
        else
            smartvpn_vpn_mark_redirect_close
        fi
        lock -u $smartvpn_lock
        return $?
    ;;

    *)
        smartvpn_usage
        lock -u $smartvpn_lock
        return 1
    ;;
esac

