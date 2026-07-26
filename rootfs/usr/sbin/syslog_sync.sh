#!/bin/sh

# Force rotate the log, keep to disk if exist
logrotate -f /etc/logrotate.conf

sync
