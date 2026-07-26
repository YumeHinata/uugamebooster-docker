#!/bin/ash

readonly CRON_FILE=/etc/crontabs/root
readonly PARTS_DIR=/etc/periodic

if [ ! -d "$PARTS_DIR" ]; then
	exit 0
fi

if ! grep -qsw "$PARTS_DIR" "$CRON_FILE"; then
	cat <<-EOF >> $CRON_FILE
		* * * * * run-parts -a 1min /etc/periodic
		*/10 * * * * run-parts -a 10min /etc/periodic
		3 * * * * run-parts -a hourly /etc/periodic
		6 1 * * * run-parts -a daily /etc/periodic
	EOF
fi
