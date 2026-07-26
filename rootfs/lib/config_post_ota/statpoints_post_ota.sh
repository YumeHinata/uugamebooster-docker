#!/bin/ash

readonly CRON_FILE=/etc/crontabs/root

if ! grep -qsw sp_check.sh "$CRON_FILE"; then
	sed -i '1i*/5 * * * * command -v sp_check.sh >/dev/null && sp_check.sh' $CRON_FILE
fi

