#!/bin/sh
# firewall airplane_install.sh v1.11
# Install Airplane-on-Boot：關機時、開機時都進飛行模式，每次開機 Wi-Fi 都是關的
. "$(dirname "$0")/common.sh"

# 關機：掛 stopping wifid。shutdown.conf 會先寫 /tmp/shutdown_in_progress 再停 wifid，
# 這時 com.lab126.cmd 還在（lab126 排在 wifid 之後才停），可以下 lipc 指令。
# 檢查那個檔，是為了只在真的關機／重開機時執行（lab126 因其他原因停止 wifid 時不動）。
# stopping 事件會等這個 task 跑完 wifid 才停，所以整段加 timeout，絕不卡住關機。
# 開機：掛 started cmd（started 事件不會等 job），等待的部分在 airplane_apply.sh 裡丟背景。
# 插件被刪時兩段都直接略過。
write_confs() {
    cat > "$AIRPLANE_SHUTDOWN_CONF" <<CONF
# firewall Airplane-on-Boot, shutdown part (installed by KUAL extension firewall)
start on stopping wifid
task
script
    S="$BASE/bin/airplane_apply.sh"
    [ -e /tmp/shutdown_in_progress ] || exit 0
    [ -f "\$S" ] && timeout -t 10 /bin/sh "\$S" shutdown || true
end script
CONF
    cat > "$AIRPLANE_BOOT_CONF" <<CONF
# firewall Airplane-on-Boot, boot part (installed by KUAL extension firewall)
start on started cmd
task
script
    S="$BASE/bin/airplane_apply.sh"
    [ -f "\$S" ] && timeout -t 10 /bin/sh "\$S" boot || true
end script
CONF
}
with_rootfs_rw write_confs

if [ -f "$AIRPLANE_SHUTDOWN_CONF" ] && [ -f "$AIRPLANE_BOOT_CONF" ]; then
    log "Airplane-on-Boot installed: $AIRPLANE_SHUTDOWN_CONF $AIRPLANE_BOOT_CONF" "開機飛行模式已安裝"
    notify "Airplane-on-Boot installed"
else
    log "ERROR: Airplane-on-Boot install failed" "錯誤：開機飛行模式安裝失敗"
    notify "Install FAILED"
fi
