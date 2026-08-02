#!/bin/sh

root_path=$1
root_data=$root_path/userdata

umount $root_data

mkdir -p $root_data

mkdir -p $2/data

mount --bind -r $2/data $root_data
