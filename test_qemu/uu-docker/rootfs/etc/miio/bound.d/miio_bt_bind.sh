#! /bin/ash

/etc/init.d/miio_bt restart

logger -p 2 -t "miio_bt" "call start after bind"
