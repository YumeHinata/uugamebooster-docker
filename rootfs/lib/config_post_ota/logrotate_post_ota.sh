#!/bin/ash

readonly CRON_FILE=/etc/crontabs/root

if ! grep -qsw logrotate "$CRON_FILE"; then
	sed -i '1i*/2 * * * * command -v logrotate >/dev/null && logrotate /etc/logrotate.conf' $CRON_FILE
fi

