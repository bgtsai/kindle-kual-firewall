#!/bin/sh
# firewall airplane_remove.sh v1.11
. "$(dirname "$0")/common.sh"

remove_confs() { rm -f "$AIRPLANE_SHUTDOWN_CONF" "$AIRPLANE_BOOT_CONF"; }
with_rootfs_rw remove_confs

if [ -f "$AIRPLANE_SHUTDOWN_CONF" ] || [ -f "$AIRPLANE_BOOT_CONF" ]; then
    log "ERROR: Airplane-on-Boot removal failed" "錯誤：開機飛行模式移除失敗"
    notify "Remove FAILED"
else
    log "Airplane-on-Boot removed" "開機飛行模式已移除"
    notify "Airplane-on-Boot removed"
fi
