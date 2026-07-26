#!/bin/ash

ubus call mobile status 2>/dev/null | jsonfilter -q -e "@['band']"
