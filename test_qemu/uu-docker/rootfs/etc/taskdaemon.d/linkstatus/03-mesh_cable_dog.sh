#!/bin/sh

#only triggered by linkup
[ "$LINK_STATUS" != "linkup" ] && exit 0

wan_port=$(uci -q get misc.sw_reg.sw_wan_port)
[ -z "$wan_port" ] && exit 0

#cannot work for RE/lanap/wifiap mode
mesh_mode=$(uci -q get xiaoqiang.common.NETMODE)
[ "$mesh_mode" == "whc_re" -o "$mesh_mode" == "lanapmode" -o "$mesh_mode" == "wifiapmode" ] && exit 0

inited=$(uci -q get xiaoqiang.common.INITTED)
if [ "$inited" = "YES" ]; then
    #CAP

    #only work for LAN
    [ "$wan_port" = "$PORT_NUM" ] && exit 0

    (
        logger -t "meshd" -p9 "=== start CAP meshd to nego mesh-NET. === "
        /etc/init.d/cab_meshd start
    ) &

else
    #RE

    #only work for WAN
    [ "$wan_port" = "$PORT_NUM" ] || exit 0

    (
        logger -t "meshd" -p9 "=== start RE cab_meshd to nego mesh-NET. === "
        /etc/init.d/cab_meshd start
    ) &
fi
