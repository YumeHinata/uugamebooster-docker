#!/bin/ash

ubus call trafficd hw '{"debug":true}'
ubus call trafficd ip '{"debug":true}'
