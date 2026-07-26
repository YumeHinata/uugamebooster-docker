#!/bin/ash

readonly LOG_FILE="/userdisk/data/.pluginConfig/2882303761517344979/micloudBackup.log"

[ -e "$LOG_FILE" ] && tail -c $((4*1024*1024)) "$LOG_FILE"
