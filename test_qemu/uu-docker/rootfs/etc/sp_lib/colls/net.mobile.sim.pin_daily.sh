#!/bin/ash

ubus call mobile sim 2>/dev/null | jsonfilter -q -e "@['lock']"
