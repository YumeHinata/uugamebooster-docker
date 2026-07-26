#!/bin/sh
#
# rule_file->format2domain->domain_file_formated->sort->domain_file_sorted->domain_file+ip_file

domain_file_formated="/tmp/smartvpn_domain_format.tmp"
domain_file_sorted="/tmp/smartvpn_domain_sort.tmp"
#domain_file_smartvpn="/etc/smartvpn/smartdns.conf"

#ipset_name="smartvpn"

rule_file=$1
domain_file=$2
ip_file=$3
ipset_name=$4
dnsserver=$5

usage()
{
    echo "gensmartdns.sh rule_file domain_file ip_file ipset_name [dnsserver]"
    echo "-- rule_file : must specify"
    echo "-- domain_file : must specify, writable, domain list output"
    echo "-- ip_file : must specify, writable, ip list output"
    echo "-- ipset_name : must specify"
    echo "-- dnsserver : optional, default is empty"
    echo ""
}


echo "gen arg list: "$*"!!!!!!!!!"

[ -z $rule_file ] && {
    usage
    return 1
}

[ -z $ip_file ] && {
    usage
    return 1
}

[ -z $dnsserver ] && {
	. /lib/functions/network.sh
	network_get_dnsserver vpn_dnsservers vpn
	if [ -n "$vpn_dnsservers" ]; then
		dnsserver="$(echo "$vpn_dnsservers" | head -n1 | awk '{print $1;}')"
		logger -t gensmartdns "dnsserver: $dnsserver"
	fi
}

[ -z $ipset_name ] && {
    ipset_name="smartvpn"
}

echo "gensmartdns: domain_file=$rule_file, ip_file=$ip_file, dnsserver=$dnsserver"

format2domain -f $rule_file -o $domain_file_formated -i $ip_file
[ $? -ne 0 ] && {
    echo "format2domain error!"
    return 1
}

sort $domain_file_formated | uniq > $domain_file_sorted
cat $domain_file_sorted | while read line
do
    [ -n "$dnsserver" ] && echo "server=/$line/$dnsserver"
    [ -n "$ipset_name" ] && echo "ipset=/$line/$ipset_name"
done > $domain_file

rm $domain_file_formated
rm $domain_file_sorted
echo "Gen smartdns conf done!"

