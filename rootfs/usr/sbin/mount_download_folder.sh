#!/bin/sh

root_path=$1
root_data=$root_path/下载

umount $root_data

mkdir -p $root_data

mkdir -p $2/下载

mount --bind -r $2/下载 $root_data
