#!/bin/ash

readonly RUN_PATH=/tmp/miio_spec

mkdir -p "$RUN_PATH"

spec=$1
mac=$2

res=$(flock "/tmp/run/miio_spec_$spec.lock" miio_spec_dev_update.sh "$RUN_PATH/$spec" "$mac")
exit "$res"
