#!/bin/sh
# firewall airplane_apply.sh v1.11
# 由 Airplane-on-Boot 的 upstart 設定呼叫，不是選單項目。
#   shutdown：關機途中把 Wi-Fi 關掉。飛行模式會跨重開機保留（5.13.5 使用者實測），
#             所以下次開機一開始就是飛行模式，Wi-Fi 不會先連上。
#   boot    ：保險。沒電直接斷電時關機那段沒跑到，開機後在背景等 com.lab126.cmd 能回應再設一次。
. "$(dirname "$0")/common.sh"

case "$1" in
shutdown)
    if airplane_on; then
        log "Shutdown: airplane mode on" "關機：已進入飛行模式"
    else
        log "ERROR: shutdown: could not turn on airplane mode" "錯誤：關機時無法進入飛行模式"
    fi
    ;;
boot)
    # 背景等待，不能拖住開機（upstart 的 started 事件不會等這個 job，但還是丟背景保險）
    (
        i=0
        until lipc-get-prop com.lab126.cmd wirelessEnable >/dev/null 2>&1; do
            i=$((i + 1))
            if [ "$i" -ge "$AIRPLANE_BOOT_WAIT_S" ]; then
                log "ERROR: boot: Wi-Fi service did not respond within ${AIRPLANE_BOOT_WAIT_S}s" "錯誤：開機時 Wi-Fi 服務一直沒回應，未能進入飛行模式"
                exit 1
            fi
            sleep 1
        done
        if [ "$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null)" = 0 ]; then
            log "Boot: already in airplane mode" "開機：本來就是飛行模式"
        elif airplane_on; then
            log "Boot: airplane mode on" "開機：已進入飛行模式"
        else
            log "ERROR: boot: could not turn on airplane mode" "錯誤：開機時無法進入飛行模式"
        fi
    ) </dev/null >/dev/null 2>&1 &
    ;;
*)
    log "ERROR: airplane_apply.sh: unknown mode '$1'" "錯誤：airplane_apply.sh 收到未知的模式"
    exit 1
    ;;
esac
