#!/bin/sh
# DNS bypass iStoreOS filter
echo "nameserver 114.114.114.114" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# OpenSSL hardcoded path
mkdir -p /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl
cat > /home/bing/git/tun2proxy/src/third_party/openssl-1.0.2q/build/ssl/openssl.cnf << 'CNF'
openssl_conf = default_conf
[default_conf]
ssl_conf = ssl_sect
[ssl_sect]
system_default = system_default_sect
[system_default_sect]
CipherString = DEFAULT:@SECLEVEL=0
MinProtocol = TLSv1
CNF

# Kill old process
kill $(pgrep -f uuplugin) 2>/dev/null
sleep 2
rm -f /var/run/uuplugin.pid

# Start with strace
strace -f -o /tmp/strace2.log /opt/uu/bin/uuplugin /opt/uu/conf/uu.conf &
echo "uuplugin PID=$!"
