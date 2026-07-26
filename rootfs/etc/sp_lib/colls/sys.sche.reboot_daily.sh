#!/bin/ash

# refer to /cgi-bin/luci/api/xqsmarthome/request_smartcontroller
result=$(thrifttunnel 2 'eyJjb21tYW5kIjoiZ2V0X211bHRpcGxlX3NjZW5lX3NldHRpbmciLCJzdGFydF9pZCI6MzAwMTAsImVuZF9pZCI6MzAwMTl9')

for id in $(seq 0 9); do
    type=$(echo "$result" | jsonfilter -e "@['scene_list'][$id]['action_list'][0]['type']")
    repeat=$(echo "$result" | jsonfilter -e "@['scene_list'][$id]['launch']['timer']['repeat']")
    enabled=$(echo "$result" | jsonfilter -e "@['scene_list'][$id]['launch']['timer']['enabled']")

    [ "$type" = "normal_reboot" -a "$enabled" = "true" -a -n "$repeat" ] && {
        echo 1
        return
    }
done

echo 0

