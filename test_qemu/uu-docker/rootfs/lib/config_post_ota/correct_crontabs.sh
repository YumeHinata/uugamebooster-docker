#!/bin/ash

[ -f /etc/crontabs/root ] && {
	awk '!seen[$0]++' /etc/crontabs/root > /etc/crontabs/root.tmp && mv /etc/crontabs/root.tmp /etc/crontabs/root
}