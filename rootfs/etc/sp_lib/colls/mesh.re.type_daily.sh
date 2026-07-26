#!/bin/ash

topomon_action.sh current_status bh_type \
	|sed -e '/isolated/d' -e 's/wired/wire/'
