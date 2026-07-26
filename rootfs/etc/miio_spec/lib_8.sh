#!/bin/ash


lib_8_lock="/var/run/lib_8.lock"


run_with_lock()
{
  {
       flock -x -w 5 1004
       [ $? -eq "1" ] && { logger -t miio_proxy "lib_8 lock failed." ; exit 1 ; }

       $@ 1004>&-
       flock -u 1004
   } 1004<>$lib_8_lock
}

generate_unlimited_token() {
    local unlimited_token
    local unlimited_token_save="/tmp/luci-sessions/unlimited_token"

    if [ -f "$unlimited_token_save" ]; then
        unlimited_token="$(cat "$unlimited_token_save")"
        if [ -n "$unlimited_token" ]; then
            if [ -f "/tmp/luci-sessions/${unlimited_token}" ]; then
                # already have a valid unlimited token, return it
                echo "$unlimited_token"
                return
            else
                # token expired, delete and regenerete it
                rm -rf "$unlimited_token_save"
            fi
        fi
    fi

    # generate a new unlimited token
    unlimited_token="$(lua -e '
        local sauth = require "luci.sauth";
        local token = luci.sys.uniqueid(16);
        sauth.prepare();
        sauth.write(token, {
            user="admin",
            token=token,
            ltype="2",
            secret=luci.sys.uniqueid(16)
        });
        print(tostring(token));
    ' 2>/dev/null)"

    [ -n "$unlimited_token" ] && {
        # save the token to file
        [ -d "/tmp/luci-sessions" ] && echo "$unlimited_token" > "$unlimited_token_save"
        echo "$unlimited_token"
    }
    return
}

get_8_1() {
    run_with_lock generate_unlimited_token
    return
}