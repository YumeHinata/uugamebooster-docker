#!/bin/sh

option=$1
case $option in
    "init")
        inited=$(uci -q get xiaoqiang.common.INITTED)
        [ "$inited" = "YES" ] && exit 0

        sim_pnp=$(uci -q get misc.features.simPlugAndPlay)
        sim_ccode=$(uci -q get mobile.sim.country_code | tr '[a-z]' '[A-Z]')
        [ "$sim_pnp" = "1" ] && [ "$sim_ccode" != "CN" ] && exit 0

        exit 1
    ;;
    "server")
        sim_pnp=$(uci -q get misc.features.simPlugAndPlay)
        [ "$sim_pnp" = "1" ] && {
            inited=$(uci -q get xiaoqiang.common.INITTED)
            [ "$inited" != "YES" ] && exit 1
        }
        exit 0
    ;;
    "config")
        configured=$(uci -q get xiaoqiang.common.CONFIGURED)
        [ "$configured" = "YES" ] && exit 0

        sim_pnp=$(uci -q get misc.features.simPlugAndPlay)
        [ "$sim_pnp" = "1" ] &&  exit 0

        exit 1
    ;;
esac

exit 1
