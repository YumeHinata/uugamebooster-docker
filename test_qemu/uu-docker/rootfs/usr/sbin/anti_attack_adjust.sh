#!/bin/sh

# reload all hashlimit rules to apply new rate/burst configurations.
ubus call uci set '{"config": "firewall_cpp", "section": "anti_attack", "values": {"disable": "1"}}'
firewall_cpp
ubus call uci set '{"config": "firewall_cpp", "section": "anti_attack", "values": {"disable": "0"}}'
ubus call uci commit '{"config": "firewall_cpp"}'
