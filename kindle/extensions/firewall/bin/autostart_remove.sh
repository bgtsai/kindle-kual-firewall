#!/bin/sh
# firewall autostart_remove.sh v1.5
. "$(dirname "$0")/common.sh"

mntroot rw || { log "ERROR: mntroot rw 失敗"; notify "Remove FAILED"; exit 1; }
rm -f "$UPSTART_CONF"
mntroot ro

if [ -f "$UPSTART_CONF" ]; then
    log "ERROR: 開機自動執行移除失敗"
    notify "Remove FAILED"
else
    log "開機自動執行已移除"
    notify "Autostart removed"
fi
