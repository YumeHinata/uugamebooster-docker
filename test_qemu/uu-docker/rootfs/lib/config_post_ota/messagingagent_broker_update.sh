#!/bin/ash

readonly BROKER_API_NAME='miwifi.server.BROKER'

change_broker() {
	local _old=
	local _new=

	_old=$(uci -q get "$BROKER_API_NAME")

	if echo "$_old"|grep api; then
		_new=$(echo "$_old"|sed 's|api|broker|')
		uci set "$BROKER_API_NAME=$_new"
		uci commit "$BROKER_API_NAME"
	fi
}

change_broker
