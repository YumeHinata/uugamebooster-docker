#!/bin/sh
sleep 2
nvram set restore_defaults=1 && nvram commit && reboot -f
