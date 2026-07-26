#!/bin/sh

logger -t ntp "miio ntp hook"

if [ -n "$(pgrep miio_bind.sh)" ]; then
	logger -t miio_ntp "miio_bind.sh is running, skip it"
else
	miio_bind.sh -c
fi
