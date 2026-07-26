#########################################################################
# File Name: topomon_cb.sh
# Author: xubin
# mail: xubin7@xiaomi.com
# Created Time: 2023年03月29日 星期三 15时12分07秒
#########################################################################
#!/bin/sh

br_dhcp_enable=$(bdata get bridge_dhcp_enable)
easymesh_role=$(uci -q get xiaoqiang.common.EASYMESH_ROLE)
if [ "$easymesh_role" = "agent" ] && [ "$br_dhcp_enable" = "1" ]; then
	rm /var/run/topomon/wan_disconned 2>>/dev/null
fi
