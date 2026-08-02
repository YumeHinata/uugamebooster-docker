#!/bin/sh

readonly SCRIPTS_DIR=/etc/luci_post_init.d

[ ! -d "$SCRIPTS_DIR" ] && exit 0

# Iterate all scripts
for script_file in "$SCRIPTS_DIR"/*; do
	"$script_file"
done
