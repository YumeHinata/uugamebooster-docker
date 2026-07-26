#!/bin/sh

. /usr/share/libubox/jshn.sh

logger -p 2 -t "miio_unbind" "start"

if [ -z "$(uci -q get miio_ot.ot.bind_key)" ]; then
    logger -p 2 -t "miio_unbind" "miio_ot bind_key is null"
    exit 0
fi

/etc/init.d/miio_client stop
/etc/init.d/miio_bt stop

uci -q set miio_ot.ot.bind_key=""
uci -q set miio_ot.ot.partner_id=""
uci -q set miio_ot.ot.uid=""
uci -q set miio_ot.ot.token=""
uci commit miio_ot

rm -rf /data/miio_ot/
rm -rf /data/bt_mesh
rm -rf /data/local/miio_bt

logger -p 2 -t "miio_unbind" "finish"
