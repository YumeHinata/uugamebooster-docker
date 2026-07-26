#! /bin/ash

/etc/init.d/miio_bt stop

rm -rf /data/local/miio_bt/
rm /data/bt_mesh

logger -p 2 -t "miio_bt" "unbind event, call stop finish"
