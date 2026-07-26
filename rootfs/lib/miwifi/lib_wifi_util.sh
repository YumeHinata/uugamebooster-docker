#!/bin/sh

_set_scan() { return; }
_get_connect() { return; }
_set_inactive() { return; }
_update_apcli() { return; }
_get_scan_result() { return; }
_set_ch_quality() { return; }
_set_channel() { return; }
_get_signal() { return; }
_set_connect() { return; }
_get_work_ch() { return; }
_app_acl_mode() { return; }
_add_acl_mac() { return; }
_kick_wl_mac() { return; }
_set_mac_temporary_black() { return; }

if [ -f "/lib/miwifi/wifitool/lib_wifi_tool.sh" ]; then
    . /lib/miwifi/wifitool/lib_wifi_tool.sh
fi
. /lib/miwifi/miwifi_functions.sh

