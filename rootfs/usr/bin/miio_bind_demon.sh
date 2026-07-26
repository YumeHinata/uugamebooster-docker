#!/bin/sh

while ! nettb; do
	sleep 30
done

/usr/bin/miio_bind.sh
