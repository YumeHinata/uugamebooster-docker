#!/bin/ash

killall -9 02_check_central.sh 2>/dev/null
touch /tmp/central_normal_stop

miotcentralctl restore
sleep 4
central_software_pack.sh stop
central_software_pack.sh rm
