#!/bin/sh
# firewall enable.sh v1.10
. "$(dirname "$0")/common.sh"

stop_resolver

# ---- 基本規則：立即生效，不依賴網路 ----
# 為什麼先套基本規則、放行網域之後再補：Wi-Fi 沒開時 DNS 查不到（實測 2026-11-04），
# 舊版在那種情況下一條放行規則都沒加，連上網後也不會補。
iptables -F OUTPUT
iptables -N "$ALLOW_CHAIN" 2>/dev/null
iptables -F "$ALLOW_CHAIN"
iptables -A OUTPUT -o lo -j ACCEPT
for net in $LAN_RANGES; do
    iptables -A OUTPUT -d "$net" -j ACCEPT
done
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
for port in $CALIBRE_BROADCAST_PORTS; do
    iptables -A OUTPUT -p udp -d 255.255.255.255 --dport "$port" -j ACCEPT
done
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  || iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT \
  || log "ERROR: neither conntrack nor state module is available" "錯誤：conntrack 與 state 模組都無法使用"
iptables -A OUTPUT -j "$ALLOW_CHAIN"
iptables -A OUTPUT -j DROP
log "Basic rules applied (WAN blocked)" "基本規則已套用（WAN 已阻斷）"

# ---- 放行網域：清空 FW_ALLOW 後重新解析；連上期間失敗的網域短暫重試 ----
# 同一個 IP 只加一次（ota／build.koreader.rocks、兩個 GitHub 下載網域共用 IP）
refresh_allow() {
    iptables -F "$ALLOW_CHAIN"
    added=" "
    ok=0
    pending="$(echo $ALLOW_DOMAINS)"
    try=0
    while [ -n "$pending" ] && [ "$try" -lt "$RESOLVE_RETRY_MAX" ]; do
        try=$((try + 1))
        still=""
        for d in $pending; do
            ips="$(resolve_ipv4 "$d")"
            if [ -z "$ips" ]; then
                still="$still $d"
                continue
            fi
            ok=$((ok + 1))
            for ip in $ips; do
                case "$added" in *" $ip "*) continue ;; esac
                added="$added$ip "
                for port in $ALLOW_PORTS; do
                    iptables -A "$ALLOW_CHAIN" -p tcp -d "$ip" --dport "$port" -j ACCEPT
                done
            done
        done
        pending="$(echo $still)"
        if [ -n "$pending" ] && [ "$try" -lt "$RESOLVE_RETRY_MAX" ]; then
            sleep "$RESOLVE_RETRY_INTERVAL"
            # 重試期間斷線了就放棄，等下一次連線再整批重來
            [ "$(wifi_state)" = CONNECTED ] || break
        fi
    done
    log "Wi-Fi connected: allowed $ok domains, IPs:$(echo "$added" | sed 's/ *$//')" "Wi-Fi 已連上：已放行上一行的網域"
    [ -n "$pending" ] && log "Could not resolve (will retry on next connection): $pending" "上一行的網域解析失敗，下次連上 Wi-Fi 時再試"
}

# ---- 背景程序：等 Wi-Fi 從「未連線」變成 CONNECTED 才解析 ----
# 為什麼看 cmStateChange 而不是 cmConnected：Wi-Fi 一直連著時 cmConnected 每 30 秒左右會重複出現
# （5.13.5 實測，diagnose_wifi_events.txt），照它觸發等於回到每 30 秒解析一次。
# 飛行模式或沒連上時，程序停在 lipc-wait-event 等事件，不會定時喚醒。
(
    prev=""
    fallback_logged=0
    while :; do
        st="$(wifi_state)"
        if [ "$st" = CONNECTED ] && [ "$prev" != CONNECTED ]; then
            refresh_allow
        fi
        prev="$st"

        lipc-wait-event -s 0 com.lab126.wifid cmStateChange >/dev/null 2>&1 &
        w=$!
        echo "$w" > "$WAITER_PIDFILE"
        # 開始等之前狀態已經變了（剛好在兩步之間發生），就不等、直接重新判斷
        if [ "$(wifi_state)" != "$st" ]; then
            kill "$w" 2>/dev/null
            continue
        fi
        if ! wait "$w"; then
            # lipc-wait-event 失敗（開機初期 wifid 還沒起來、或被 kill）：改用輪詢，不能空轉
            if [ "$fallback_logged" -eq 0 ]; then
                log "Waiting for Wi-Fi service (polling every ${WAIT_FALLBACK_POLL_S}s)" "等待 Wi-Fi 服務啟動中（改用定時檢查）"
                fallback_logged=1
            fi
            sleep "$WAIT_FALLBACK_POLL_S"
        fi
    done
) </dev/null >/dev/null 2>&1 &
echo $! > "$PIDFILE"

notify "Firewall ON"
