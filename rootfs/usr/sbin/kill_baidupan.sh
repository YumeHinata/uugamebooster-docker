#!/bin/sh
# Copyright (C) 2020 Xiaomi


ID=$(ps ww| grep baidupan.lua | grep -v grep | awk '{print $1}' 2> /dev/null)

echo "baidupan will kill $ID" >> /tmp/messages

for id in $ID
do
    #kill -9 $id
    if [ -n $id ]; then
        echo "baidupan kill $id success!!!" >> /tmp/messages
        echo `pstree -p $id`|awk 'BEGIN{ FS="(" ; RS=")" } NF>1 { print $NF }'|xargs kill -9 &>/dev/nul
    fi

    echo "baidupan kill $id" >> /tmp/messages
done


