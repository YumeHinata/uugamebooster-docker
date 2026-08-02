#!/bin/ash

VPN_UP_PATH="/etc/ppp/ppp.d/vpn-up"
grep -qsw "unset \$IPREMOTE" "$VPN_UP_PATH" && {
	sed  -i 's/unset $IPREMOTE/unset IPREMOTE/g' "$VPN_UP_PATH"
}

