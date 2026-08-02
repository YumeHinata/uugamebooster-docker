#!/bin/sh

. /lib/functions.sh


module_name="parentalctl"

time_seg=""
weekdays=""
hosts=""
src_mac=""
start_date=""
stop_date=""

device_set=""


pctl_nat_table="parentalctl_nat"
pctl_filter_device_table="parentalctl_device_filter"
pctl_filter_host_table="parentalctl_host_filter"

pctl_conf_path="/etc/parentalctl/"
_pctl_file="${pctl_conf_path}/${module_name}.conf"
_pctl_ip_file="${pctl_conf_path}/${module_name}_ip.conf"
_has_pctl_file=0
_dnsmasq_file="/etc/dnsmasq.d/${module_name}.conf"
_dnsmasq_var_file="/var/etc/dnsmasq.d/${module_name}.conf"

pctl_logger()
{
    echo "$module_name: $1"
    logger -t $module_name "$1"
}

dnsmasq_restart()
{
    /etc/init.d/dnsmasq restart
}

#format 2015-05-19
date_check()
{
    local _date=$1

    [ "$_date" == "" ] && return 0

    if echo $_date | grep -iqE "^2[0-9]{3}-[0-1][0-9]-[0-3][0-9]$"
    then
         #echo mac address $mac format correct;
         return 0
    else
         echo "date \"$_date\" format(2xxx-xx-xx) error";
         return 1
    fi

    return 0
}

#format "09:20-23:59"
time_check()
{
    local _time_set=$1
    local _time=""

    [ "$_time_set" == "" ] && return 0

    for _time in $_time_set
    do
        if echo $_time | grep -iqE "^[0-2][0-9]:[0-6][0-9]-[0-2][0-9]:[0-6][0-9]$"
        then
            #echo mac address $mac format correct;
            return 0
        else
            echo "time \"$_time\" format(09:20-23:59) error";
            return 1
        fi
    done

    return 0
}

#format 01:02:03:04:05:06
#  mini 00:00:00:00:00:00
#  max  ff:ff:ff:ff:ff:ff
mac_check()
{
    local _mac=$1

    [ "$_mac" == "" ] && return 0

    if echo $_mac | grep -iqE "^([0-9A-F]{2}:){5}[0-9A-F]{2}$"
    then
         #echo mac address $mac format correct;
         return 0
    else
         echo "mac address \"$mac\" format(01:02:03:04:05:06) error";
         return 1
    fi

    return 0
}

#Mon Tue Wed Thu Fri Sat Sun
weekdays_check()
{
    local _weekdays=$1

    [ "$_weekdays" == "" ] && return 0

    if echo $_weekdays |grep -iqE "^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)( (Mon|Tue|Wed|Thu|Fri|Sat|Sun)){0,6}$"
    then
         #echo mac address $mac format correct;
         return 0
    else
         echo "weekdays \"$_weekdays\" format error";
         echo "  format \"Mon Tue Wed Thu Fri Sat Sun\",1-7 items"
         return 1
    fi

    return 0
}

pctl_config_entry_check()
{
    time_check "$time_seg" || return 1
    date_check "$start_date" || return 1
    date_check "$stop_date" || return 1
    mac_check "$src_mac"    || return 1
    weekdays_check "$weekdays" || return 1

    return 0;
}

pctl_config_entry_init()
{
    time_seg=""
    weekdays=""
    hostfile=""
    src_mac=""
    start_date=""
    stop_date=""
    disabled=""

    return
}

####################iptable########################
ipt_table_create()
{
    iptables -t $1 -F $2 >/dev/null 2>&1
    iptables -t $1 -X $2 >/dev/null 2>&1
    iptables -t $1 -N $2 >/dev/null 2>&1
}
####################ipset########################
ipset_create()
{
    _rule_ipset=$1
    [ "$_rule_ipset" == "" ] && return;

    ipset flush   $_rule_ipset >/dev/null 2>&1
    ipset destroy $_rule_ipset >/dev/null 2>&1
    ipset create  $_rule_ipset hash:net >/dev/null

    return
}


ipset_destroy()
{
    _rule_ipset=$1
    [ "$_rule_ipset" == "" ] && return;

    ipset flush   $_rule_ipset >/dev/null 2>&1
    ipset destroy $_rule_ipset >/dev/null 2>&1

    return
}

pctl_ipset_add_ip_file()
{
    local _ipfile=$1
    local ipset_ip_name=$2

    [ -f $_ipfile ] || return

    ipset_create $ipset_ip_name

    #echo "add ip to ipset $ipset_ip_name."
    cat $_ipfile | while read line
    do
        #_has_pctl_file=1
        ipset add $ipset_ip_name $line
    done

}

_ipset_cache_file="/tmp/parentalctl.ipset"
rm $_ipset_cache_file 2>/dev/null

parse_hostfile_one()
{
    local _hostfile=$1
    local _ipsetname=$2
    local _hostfile_tmp="/tmp/parentctl.tmp"
    local _tempfile_host="/tmp/parentctl_host.tmp"
    local _tempfile_ip="/tmp/parentctl_ip.tmp"

    rm $_hostfile_tmp 2>/dev/null
    rm $_tempfile_host 2>/dev/null
    rm $_tempfile_ip 2>/dev/null
    #echo hostfileone" $1 $2"

    cat $_hostfile | awk '{print $2}' |uniq > $_hostfile_tmp

    format2domain -f $_hostfile_tmp -o $_tempfile_host -i $_tempfile_ip 1>/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "format2domain error!"
        return 1
    fi

    cat $_tempfile_host | while read line
    do
        echo "$line $_ipsetname"
    done >> $_ipset_cache_file

    pctl_ipset_add_ip_file $_tempfile_ip $_ipsetname

    rm $_tempfile_host 2>/dev/null
    rm $_tempfile_ip 2>/dev/null

    return 0;
}

parse_hostfile_finish()
{

    sort $_ipset_cache_file | uniq > $_ipset_cache_file".2"

    awk '{
        if($1==x)
        {
            i=i","$2
        } 
        else 
        { 
            if(NR>1) { print i} ; 
            i="ipset=/"$1"/"$2 
        }; 
        x=$1;
        y=$2
    }
    END{print i}' $_ipset_cache_file".2" > $_pctl_file
    
    rm $_ipset_cache_file
    rm $_ipset_cache_file".2"
  


    return 0
}

#config summary 'D04F7EC0D55D'
#       option mac 'D0:4F:7E:C0:D5:5D'
#       option disabled '0'
#       option mode 'black'
parse_summary()
{
    local section="$1"
    local disabled=""
    local mode=""
    local device_id=""

    config_get src_mac    $section mac &>/dev/null;
    [ "$src_mac" == "" ] && return

    config_get disabled   $section disabled &>/dev/null;
    config_get mode   $section mode &>/dev/null;

    device_id=${src_mac//:/};
    eval x${device_id}_disabled=$disabled
    eval x${device_id}_mode=$mode

    return
}

#config rule parentalctl_1
#        option src              lan
#        option dest             wan
#        option src_mac          00:01:02:03:04:05
#        option start_date       2015-06-18
#        option stop_date        2015-06-20
#        option start_time       21:00
#        option stop_time        09:00
#        option weekdays         'mon tue wed thu fri'
#        option target           REJECT
parse_device()
{
    local section="$1"
    local _buffer=""

    local device_id=""
    
    pctl_config_entry_init

    config_get disabled   $section disabled &>/dev/null;
    [ "$disabled" = "1" ] && return

    config_get src_mac    $section mac &>/dev/null;
    [ "$src_mac" = "" ] && return ;

    config_get time_seg   $section time_seg &>/dev/null;
    config_get weekdays   $section weekdays &>/dev/null;
    config_get start_date $section start_date &>/dev/null;
    config_get stop_date  $section stop_date &>/dev/null;

    pctl_config_entry_check || return 0;

    #mac 01:02:03:04:05:06 ->> id 010203040506
    device_id=${src_mac//:/};

    summary_mode=$(eval echo \$x${device_id}_mode)
    summary_disabled=$(eval echo \$x${device_id}_disabled)


    echo  "disabled: $summary_disabled"
    [ "$summary_disabled" != "" -a "$summary_disabled" != 0 ] && return 0;

    echo  "mode: $summary_mode"
    [ "$summary_mode" != "" -a "$summary_mode" != "time" ] && return 0;

    for one_time_seg in $time_seg
    do
        start_time=$(echo $one_time_seg |cut -d - -f 1 2>/dev/null)
        stop_time=$(echo $one_time_seg |cut -d - -f 2 2>/dev/null)

        _cmd_line="-m mac --mac-source $src_mac -m time --kerneltz" 

        [ -z "$start_time" ] && start_time="00:00"
        [ -z "$stop_time" ] && stop_time="23:59"

        _cmd_line="$_cmd_line --timestart $start_time --timestop $stop_time "

        # if start_time > stop_time, then it is a cross day time segment, need to set --contiguous flag
        if [ "$start_time" \> "$stop_time" ]; then
            _cmd_line="$_cmd_line --contiguous "
        fi

        #everyday equals all 7 days in one week
        [ "$weekdays" != "" ] && {
            _cmd_line="$_cmd_line --weekdays ${weekdays//\ /,} "
        }

        #once
        [ "$start_date" != "" -a "$stop_date" != "" ] && {
            the_day=$(date -d "${start_date}" +%a)
            _cmd_line="$_cmd_line --weekdays ${the_day} "
            _cmd_line="$_cmd_line --datestart $start_date --datestop $stop_date "
        }

        iptables -t filter -I $pctl_filter_device_table -p udp $_cmd_line -j REJECT 1>/dev/null
        iptables -t filter -I $pctl_filter_device_table -p tcp $_cmd_line -j REJECT 1>/dev/null
    done

    return 0;
}

parse_rule()
{
    local section="$1"
    local _buffer=""
    local device_id=""
    local _mode=""
    local _mode_extra=""

    pctl_config_entry_init

    config_get disabled   $section disabled &>/dev/null;
    [ "$disabled" == "1" ] && return

    config_get src_mac    $section mac &>/dev/null;
    [ "$src_mac" == "" ] && return ;

    config_get hostfiles  $section hostfile &>/dev/null;

    #mode = [white|black], if mode not set, means black
    config_get _mode $section mode &>/dev/null;

    [ "$_mode" == "white" ] && _mode_extra="!"

    pctl_config_entry_check || return 0;

    #mac 01:02:03:04:05:06 ->> id 010203040506
    device_id=${src_mac//:/};

    #summary_mode=$(eval echo \$x${device_id}_mode)
    summary_disabled=$(eval echo \$x${device_id}_disabled)

    [ "$summary_disabled" != "" ] && {
        [ "$summary_disabled" != 0 ] && return 0;
    }

    local _device_has_hostfile=0;
    _rule_ipset="${module_name}_${device_id}_host"

    ipset_create  $_rule_ipset

    for hostfile in $hostfiles
    do
        local hostfile_linenum=0;
        [ ! -f "$hostfile" ] && continue

        parse_hostfile_one "$hostfile" "$_rule_ipset"

        hostfile_linenum=$(cat $hostfile | wc -l)
        echo "line num: $hostfile_linenum"

        [ "$hostfile_linenum" != "0" ] && {
            _device_has_hostfile=1
            _has_pctl_file=1
        }
    done

    [ "$_mode" == "white" ] && _device_has_hostfile=1;

    [ $_device_has_hostfile == 1 ] && {
        iptables -t filter -D $pctl_filter_host_table -p tcp -m mac --mac-source $src_mac -m set $_mode_extra --match-set $_rule_ipset dst -j REJECT 1>/dev/null
        iptables -t filter -D $pctl_filter_host_table -p udp -m mac --mac-source $src_mac -m set $_mode_extra --match-set $_rule_ipset dst -j REJECT 1>/dev/null
        iptables -t filter -I $pctl_filter_host_table -p tcp -m mac --mac-source $src_mac -m set $_mode_extra --match-set $_rule_ipset dst -j REJECT 1>/dev/null
        iptables -t filter -I $pctl_filter_host_table -p udp -m mac --mac-source $src_mac -m set $_mode_extra --match-set $_rule_ipset dst -j REJECT 1>/dev/null
        iptables -t nat -D $pctl_nat_table -p tcp -m tcp --dport 53 -m mac --mac-source $src_mac -j REDIRECT --to-ports 53 1>/dev/null
        iptables -t nat -D $pctl_nat_table -p udp -m udp --dport 53 -m mac --mac-source $src_mac -j REDIRECT --to-ports 53 1>/dev/null
        iptables -t nat -I $pctl_nat_table -p tcp -m tcp --dport 53 -m mac --mac-source $src_mac -j REDIRECT --to-ports 53 1>/dev/null
        iptables -t nat -I $pctl_nat_table -p udp -m udp --dport 53 -m mac --mac-source $src_mac -j REDIRECT --to-ports 53 1>/dev/null
    }
}

pctl_reload_hosts()
{
    config_foreach parse_rule rule

    parse_hostfile_finish

    [ "$_has_pctl_file" == "0" -a -f "$_dnsmasq_file" ] && {
        rm $_dnsmasq_file 2>/dev/null
        rm $_dnsmasq_var_file 2>/dev/null
        dnsmasq_restart
    }

    [ "$_has_pctl_file" != "0" ] && {
        rm $_dnsmasq_file 2>/dev/null
        rm $_dnsmasq_var_file 2>/dev/null
        cp $_pctl_file $_dnsmasq_file
        dnsmasq_restart
    }

}

pctl_reload_device()
{
    config_foreach parse_device device

    return 0
}

pctl_ipset_delete_all()
{
    local pctl_ipset_list=$(ipset list -n| grep -E "^parentalctl_")
    local pctl_ipset=""
    for pctl_ipset in $pctl_ipset_list
    do
        ipset_destroy $pctl_ipset #maybe failed, but doesn't matter
    done
}


pctl_flush()
{
    #pctl_fw_delete_all
    iptables -t nat -D zone_lan_prerouting  -j $pctl_nat_table >/dev/null 2>&1
    ipt_table_create nat $pctl_nat_table
    iptables -t nat -I zone_lan_prerouting  -j $pctl_nat_table >/dev/null 2>&1

    iptables -t filter -D zone_lan_forward  -j $pctl_filter_host_table >/dev/null 2>&1
    ipt_table_create filter $pctl_filter_host_table
    iptables -t filter -I zone_lan_forward  -j $pctl_filter_host_table >/dev/null 2>&1

    #device table must be ahead off host table. times block control works before host list
    iptables -t filter -D zone_lan_forward  -j $pctl_filter_device_table >/dev/null 2>&1
    ipt_table_create filter $pctl_filter_device_table
    iptables -t filter -I zone_lan_forward  -j $pctl_filter_device_table >/dev/null 2>&1

uci -q batch <<-EOF >/dev/null
    set firewall.parentalctl=include
    set firewall.parentalctl.path="/lib/firewall.sysapi.loader parentalctl"
    set firewall.parentalctl.reload=1
    commit firewall
EOF

    pctl_ipset_delete_all

    pctl_reload_hosts

    pctl_reload_device
    return 0
}

fw3lock="/var/run/fw3.lock"

OPT=$1

config_load "parentalctl"
config_foreach parse_summary summary

case $OPT in
    reload)
        pctl_flush
        return 0
    ;;

    *)
        trap "lock -u $fw3lock; exit 1" SIGHUP SIGINT SIGTERM
        lock $fw3lock
        pctl_flush
        lock -u  $fw3lock
        return 0
    ;;
esac
