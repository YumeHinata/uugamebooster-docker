#!/bin/ash

/usr/sbin/xqled internet_ready >/dev/null 2>&1
/usr/sbin/xqled internet_ok >/dev/null 2>&1
echo "internet_ok" > /var/run/light.status
