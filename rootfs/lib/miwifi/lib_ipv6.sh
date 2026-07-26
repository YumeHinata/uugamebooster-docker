#!/bin/sh

arch_ipv6_macvlan() { return 0; }
[ -f "/lib/miwifi/arch/lib_arch_ipv6.sh" ] && . /lib/miwifi/arch/lib_arch_ipv6.sh


ipv6_macvlan() {
    arch_ipv6_macvlan "$@"
}