#!/bin/sh
# firewall enable.sh v1.14
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

# ---- 沒有 DNS 伺服器時的證據：誰該寫 DNS 設定、寫到哪、向路由器直接查得到嗎 ----
dns_debug_snapshot() {
    gw="$(default_gateway)"
    {
        echo "firewall dns_debug v1.14  $(date)"
        echo "$(net_desc) gateway=$gw"
        echo; echo "===== resolv.conf (link target + content) ====="
        ls -la /etc/resolv.conf 2>&1
        readlink -f /etc/resolv.conf 2>&1
        cat /etc/resolv.conf 2>&1
        echo; echo "===== /etc/resolv.d ====="
        ls -la /etc/resolv.d 2>&1
        for f in /etc/resolv.d/* /var/run/resolv* /var/run/*.resolv* /tmp/resolv*; do
            [ -e "$f" ] && { echo "--- $f"; cat "$f" 2>&1; }
        done
        echo; echo "===== dhcp / dns related processes ====="
        ps 2>&1 | grep -i -E 'dhcp|dns|resolv|wpa|wifid|cmd' | grep -v grep
        echo; echo "===== route / wlan0 ====="
        cat /proc/net/route 2>&1
        ifconfig wlan0 2>&1
        echo; echo "===== nslookup github.com (default) ====="
        nslookup github.com 2>&1
        echo; echo "===== nslookup github.com $gw (gateway) ====="
        nslookup github.com "$gw" 2>&1
        echo; echo "===== lipc ====="
        for p in cmState enable; do printf 'wifid %s: ' "$p"; lipc-get-prop com.lab126.wifid "$p" 2>&1; done
        echo; echo "===== iptables OUTPUT counters ====="
        iptables -L OUTPUT -n -v 2>&1
        echo; echo "===== syslog: dhcp / resolv / dns (last 60) ====="
        grep -i -E 'dhcp|resolv|dns|nameserver' /var/log/messages 2>&1 | tail -n 60
    } > "$DNS_DEBUG" 2>&1
}

# ---- 放行網域：清空 FW_ALLOW 後重新解析；連上後失敗的網域固定重試 ----
# 同一個 IP 只加一次（ota／build.koreader.rocks、兩個 GitHub 下載網域共用 IP）
# 為什麼重試期間不再因「狀態不是 CONNECTED」提前放棄：v1.11 開機後第一次連線 12 個全部失敗、
# 而且沒有完整重試就停了；固定試完，最多多花一分鐘。
refresh_allow() {
    log "Wi-Fi up, resolving ($(net_desc))" "Wi-Fi 已連上，開始查詢放行網域（狀態見上一行）"
    # 還沒有 DNS 伺服器時先等；等不到就留證據，改向預設閘道查詢
    srv=""
    if [ -z "$(dns_server)" ]; then
        waited=0
        while [ -z "$(dns_server)" ] && [ "$waited" -lt "$DNS_WAIT_MAX_S" ]; do
            sleep "$RESOLVE_RETRY_INTERVAL"
            waited=$((waited + RESOLVE_RETRY_INTERVAL))
        done
        log "Waited ${waited}s for a DNS server ($(net_desc))" "等待 DNS 伺服器設定（等待秒數與結果見上一行）"
        if [ -z "$(dns_server)" ]; then
            dns_debug_snapshot
            srv="$(default_gateway)"
            log "No DNS server configured; querying gateway '$srv' directly. Details: dns_debug.txt" "系統沒有 DNS 伺服器設定，改向路由器直接查詢；細節寫在 dns_debug.txt"
        fi
    fi
    iptables -F "$ALLOW_CHAIN"
    added=" "
    ok=0
    pending="$(echo $ALLOW_DOMAINS)"
    try=0
    while [ -n "$pending" ] && [ "$try" -lt "$RESOLVE_RETRY_MAX" ]; do
        try=$((try + 1))
        still=""
        for d in $pending; do
            ips="$(resolve_ipv4 "$d" $srv)"
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
        if [ -n "$pending" ]; then
            first="${pending%% *}"
            err="$(nslookup "$first" $srv 2>&1 | tail -n 1)"
            log "Round $try/$RESOLVE_RETRY_MAX: $(echo $pending | wc -w) not resolved ($(net_desc)); nslookup $first: $err" "第 $try 輪：仍有網域查不到（細節見上一行）"
            [ "$try" -lt "$RESOLVE_RETRY_MAX" ] && sleep "$RESOLVE_RETRY_INTERVAL"
        fi
    done
    log "Wi-Fi connected: allowed $ok domains, IPs:$(echo "$added" | sed 's/ *$//')" "Wi-Fi 已連上：已放行上一行的網域"
    [ -n "$pending" ] && log "Could not resolve (will retry on next connection): $pending" "上一行的網域解析失敗，下次連上 Wi-Fi 時再試"
}

# ---- 背景程序：等 Wi-Fi 從「未連線」變成「已連上」才解析 ----
# 為什麼看 cmStateChange 而不是 cmConnected：Wi-Fi 一直連著時 cmConnected 每 30 秒左右會重複出現
# （5.13.5 實測，diagnose_wifi_events.txt），照它觸發等於回到每 30 秒解析一次。
# 每次等事件最多 WAIT_MAX_S 秒，醒來重新檢查一次，避免 lipc-wait-event 卡住時永遠不知道已連上。
(
    trap 'log "Background process stopped (signal)" "背景程序被結束（收到訊號）"; exit 0' TERM INT HUP
    log "Background process started (pid $$, $(net_desc))" "背景程序已啟動（狀態見上一行）"
    prev=no
    fallback_logged=0
    while :; do
        if net_up; then now=yes; else now=no; fi
        if [ "$now" = yes ] && [ "$prev" = no ]; then
            refresh_allow
        elif [ "$now" = no ] && [ "$prev" = yes ]; then
            log "Wi-Fi down ($(net_desc))" "Wi-Fi 已中斷（狀態見上一行）"
        fi
        prev="$now"

        t0=$(date +%s)
        timeout -t "$WAIT_MAX_S" lipc-wait-event -s 0 com.lab126.wifid cmStateChange >/dev/null 2>&1 &
        w=$!
        echo "$w" > "$WAITER_PIDFILE"
        # 開始等之前狀態已經變了（剛好在兩步之間發生），就不等、直接重新判斷
        if net_up; then n2=yes; else n2=no; fi
        if [ "$n2" != "$now" ]; then
            kill "$w" 2>/dev/null
            continue
        fi
        wait "$w"
        rc=$?
        if [ "$rc" -ne 0 ] && [ $(( $(date +%s) - t0 )) -lt "$WAIT_FAST_FAIL_S" ]; then
            # lipc-wait-event 一啟動就失敗（開機初期 wifid 還沒起來）：改用輪詢，不能空轉
            if [ "$fallback_logged" -eq 0 ]; then
                log "lipc-wait-event failed (rc=$rc), polling every ${WAIT_FALLBACK_POLL_S}s ($(net_desc))" "等待 Wi-Fi 事件失敗，改用定時檢查（細節見上一行）"
                fallback_logged=1
            fi
            sleep "$WAIT_FALLBACK_POLL_S"
        fi
    done
) </dev/null >/dev/null 2>&1 &
echo $! > "$PIDFILE"

notify "Firewall ON"
