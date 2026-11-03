#!/bin/sh
# firewall autostart_install.sh v1.7
# 在系統分區放 upstart 設定，開機時自動執行 enable.sh
. "$(dirname "$0")/common.sh"

# 為什麼掛在 starting lab126：這台的 wifid、otaupd、otav3 都是 start on started lab126，
# 「starting」時 task 會先跑完 lab126 才繼續，所以防火牆一定早於 Wi-Fi 與 OTA。
# enable.sh 的放行網域解析在背景跑，不會拖慢開機。
# 腳本不存在時（插件被刪）直接略過，不能讓開機卡住。
mntroot rw || { log "ERROR: mntroot rw 失敗"; notify "Install FAILED"; exit 1; }
cat > "$UPSTART_CONF" <<CONF
# firewall autostart (installed by KUAL extension firewall)
start on starting lab126
task
script
    S="$BASE/bin/enable.sh"
    [ -f "\$S" ] && /bin/sh "\$S" || true
end script
CONF
mntroot ro

if [ -f "$UPSTART_CONF" ]; then
    log "開機自動執行已安裝：$UPSTART_CONF"
    notify "Autostart installed"
else
    log "ERROR: 開機自動執行安裝失敗"
    notify "Install FAILED"
fi
